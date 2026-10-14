#!/bin/bash
# supervision — Prometheus, Alertmanager et sondes synthétiques, à LOMÉ : la supervision doit survivre
# à la perte de la région qu'elle surveille le plus (l'Europe, qui porte la base et le coffre).
# Ce qu'elle mesure : le site vu d'un client (sondes), les répartiteurs (débit, erreurs, serveurs
# actifs — l'autoscaler s'en sert), les applications (/metrics), les bases (réplication, archivage,
# WAL retenus : collecteur « textfile » du node exporter), le coffre (scellé ?), le GSLB.
# Les alertes partent vers un « pager » : un petit récepteur de webhooks qui les écrit au journal.
# shellcheck source=commun.sh
. /lab/roles/commun.sh
lien pub "" "$GW" "$ADRESSE6"; reseau_pret pub "$ADRESSE6"; resolveur "$GW"
install -m 644 /lab/tls/racine.crt /etc/prometheus/racine.crt

# ------------------------------------------------------------------ sondes (blackbox exporter)
cat > /etc/prometheus/blackbox.yml <<'EOF'
modules:
  site:                       # le site, comme un client : TLS avec NOTRE racine, HTTP 200
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: ip4
      tls_config: { ca_file: /etc/prometheus/racine.crt, server_name: www.marche.test }
      headers: { Host: www.marche.test }
  coffre:                     # /v1/sys/health : 200 descellé, 503 scellé
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: ip4
      valid_status_codes: [200]
      tls_config: { ca_file: /etc/prometheus/racine.crt, server_name: coffre.marche.test }
  www_vers_lome:              # le GSLB envoie-t-il les clients à Lomé ?
    prober: dns
    timeout: 3s
    dns:
      query_name: www.gslb.marche.test
      query_type: A
      preferred_ip_protocol: ip4
      validate_answer_rrs: { fail_if_none_matches_regexp: ['.*\t192\.0\.2\.100$'] }
EOF
sed -i 's|^ARGS=.*|ARGS="--config.file=/etc/prometheus/blackbox.yml"|' /etc/default/prometheus-blackbox-exporter

# ------------------------------------------------------------------ Prometheus
cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 10s
  evaluation_interval: 10s
alerting:
  alertmanagers: [{ static_configs: [{ targets: ['127.0.0.1:9093'] }] }]
rule_files: ['/etc/prometheus/alertes.yml']
scrape_configs:
  - job_name: repartiteurs
    static_configs:
      - { targets: ['10.0.1.10:8405'], labels: { region: europe } }
      - { targets: ['10.1.0.82:8405'], labels: { region: lome } }
  - job_name: applications      # découvertes comme le fait le répartiteur : par le DNS
    dns_sd_configs:
      - { names: ['apps-europe.gslb.marche.test'], type: A, port: 8000, refresh_interval: 15s }
      - { names: ['apps-lome.gslb.marche.test'], type: A, port: 8000, refresh_interval: 15s }
    relabel_configs:
      - { source_labels: [__meta_dns_name], regex: 'apps-([a-z]+)\..*', target_label: region }
  - job_name: bases
    static_configs:
      - { targets: ['10.0.3.10:9100'], labels: { region: europe, base: db } }
      - { targets: ['10.1.0.70:9100'], labels: { region: lome, base: db-lome } }
  - job_name: site
    metrics_path: /probe
    params: { module: [site] }
    static_configs:
      - { targets: ['https://203.0.113.10/api/products'], labels: { region: europe } }
      - { targets: ['https://192.0.2.100/api/products'], labels: { region: lome } }
    relabel_configs: &sonde
      - { source_labels: [__address__], target_label: __param_target }
      - { source_labels: [__param_target], target_label: instance }
      - { target_label: __address__, replacement: '127.0.0.1:9115' }
  - job_name: coffre
    metrics_path: /probe
    params: { module: [coffre] }
    static_configs: [{ targets: ['https://10.0.3.30:8200/v1/sys/health'] }]
    relabel_configs: *sonde
  - job_name: gslb
    metrics_path: /probe
    params: { module: [www_vers_lome] }
    static_configs:
      - { targets: ['192.0.2.101'], labels: { serveur: gslb2-lome } }
      - { targets: ['203.0.113.11'], labels: { serveur: gslb1-europe } }
    relabel_configs: *sonde
EOF

cat > /etc/prometheus/alertes.yml <<'EOF'
groups:
  - name: marche
    rules:
      - alert: SiteIndisponible
        expr: probe_success{job="site"} == 0
        for: 30s
        labels: { gravite: critique }
        annotations: { resume: "Le site ne répond plus via la région {{ $labels.region }}" }
      - alert: ErreursServeur
        expr: |
          sum by (region) (rate(haproxy_backend_http_responses_total{proxy="applications",code="5xx"}[1m]))
            / sum by (region) (rate(haproxy_backend_http_responses_total{proxy="applications"}[1m])) > 0.05
        for: 1m
        labels: { gravite: critique }
        annotations: { resume: "Plus de 5 % d'erreurs 5xx en {{ $labels.region }}" }
      - alert: CapaciteReduite
        expr: haproxy_backend_active_servers{proxy="applications"} < 2
        for: 1m
        labels: { gravite: majeure }
        annotations: { resume: "Moins de 2 instances en service en {{ $labels.region }}" }
      - alert: CoffreIndisponible
        expr: probe_success{job="coffre"} == 0
        for: 30s
        labels: { gravite: critique }
        annotations: { resume: "Le coffre est scellé ou injoignable : plus de nouveaux identifiants" }
      - alert: RepliqueAbsente
        expr: max(marche_pg_primaire) == 1 and sum(marche_replication_repliques * marche_pg_primaire) < 1
        for: 1m
        labels: { gravite: majeure }
        annotations: { resume: "La base primaire n'a plus de réplique en flux" }
      - alert: RepliqueEnRetard
        expr: max(marche_replication_retard_secondes * on (instance) marche_pg_primaire) > 30
        for: 1m
        labels: { gravite: majeure }
        annotations: { resume: "La réplique a plus de 30 s de retard" }
      - alert: WalRetenus
        expr: max(marche_slot_wal_retenu_octets) > 256 * 1024 * 1024
        for: 1m
        labels: { gravite: majeure }
        annotations: { resume: "Un slot de réplication retient {{ $value | humanize1024 }}o de WAL : le disque se remplit" }
      - alert: ArchivageEnPanne
        # (PAS « aucun WAL archivé depuis 5 min » : une base sans écriture ne produit rien à archiver —
        #  fausse alerte, vécu. Le vrai signal : des WAL qui ATTENDENT, ou un échec plus récent qu'un succès.)
        expr: max((marche_archivage_en_attente > 2 or marche_archivage_echec == 1) * on (instance) marche_pg_primaire) > 0
        for: 1m
        labels: { gravite: majeure }
        annotations: { resume: "Les WAL ne partent plus vers les sauvegardes : le RPO des sauvegardes s'envole" }
      - alert: GslbHorsDeLome
        expr: probe_success{job="gslb"} == 0
        for: 30s
        labels: { gravite: mineure }
        annotations: { resume: "{{ $labels.serveur }} n'envoie plus les clients à Lomé (Lomé en panne… ou sa sonde ?)" }
      - alert: CibleMuette
        expr: up == 0
        for: 1m
        labels: { gravite: mineure }
        annotations: { resume: "{{ $labels.job }} {{ $labels.instance }} ne répond plus à la supervision" }
EOF
promtool check config /etc/prometheus/prometheus.yml >/dev/null
sed -i 's|^ARGS=.*|ARGS="--storage.tsdb.retention.time=7d --web.listen-address=:9090"|' /etc/default/prometheus

# ------------------------------------------------------------------ Alertmanager → le « pager »
cat > /etc/prometheus/alertmanager.yml <<'EOF'
route:
  receiver: pager
  group_by: [alertname, region]
  group_wait: 10s
  group_interval: 1m
  repeat_interval: 1h
receivers:
  - name: pager
    webhook_configs: [{ url: 'http://127.0.0.1:9099/', send_resolved: true }]
EOF
cat > /usr/local/bin/pager <<'EOF'
#!/usr/bin/env python3
# le « pager » : reçoit les notifications d'Alertmanager et les écrit au journal (journalctl -u pager)
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class Recepteur(BaseHTTPRequestHandler):
    def do_POST(self):
        corps = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        for a in corps.get("alerts", []):
            etat = "🔥 DÉCLENCHÉE" if a["status"] == "firing" else "✅ résolue"
            print(f'{etat} {a["labels"].get("alertname")} [{a["labels"].get("gravite", "?")}] '
                  f'{a["annotations"].get("resume", "")}', flush=True)
        self.send_response(200); self.end_headers()
    def log_message(self, *args): pass
HTTPServer(("127.0.0.1", 9099), Recepteur).serve_forever()
EOF
chmod 755 /usr/local/bin/pager
cat > /etc/systemd/system/pager.service <<'EOF'
[Unit]
Description=Pager — les alertes reçues
[Service]
ExecStart=/usr/local/bin/pager
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sed -i 's|^ARGS=.*|ARGS="--config.file=/etc/prometheus/alertmanager.yml"|' /etc/default/prometheus-alertmanager
systemctl daemon-reload
systemctl enable -q prometheus prometheus-alertmanager prometheus-blackbox-exporter pager
systemctl restart prometheus-blackbox-exporter prometheus-alertmanager pager prometheus

pare_feu "        ip saddr ${ADMIN} tcp dport { 22, 9090, 9093 } accept"
cle_admin
echo "supervision prête"
