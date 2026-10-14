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
# l'identité de service de la supervision : elle seule peut lire /metrics sur les applications
identite supervision supervision.svc.marche.test prometheus "systemctl reload prometheus"
agent_openbao supervision

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
    # (Palier 3 : par le sidecar mTLS — la supervision présente SON identité, et vérifie la leur)
    scheme: https
    tls_config: { ca_file: /etc/identite/ca.pem, cert_file: /etc/identite/service.crt, key_file: /etc/identite/service.key, server_name: app.svc.marche.test }
    dns_sd_configs:
      - { names: ['apps-europe.gslb.marche.test'], type: A, port: 8443, refresh_interval: 15s }
      - { names: ['apps-lome.gslb.marche.test'], type: A, port: 8443, refresh_interval: 15s }
    relabel_configs:
      - { source_labels: [__meta_dns_name], regex: 'apps-([a-z]+)\..*', target_label: region }
  - job_name: passerelles       # (Palier 3 : dont les alertes de l'IDS)
    static_configs:
      - { targets: ['10.0.1.1:9100'], labels: { region: europe } }
      - { targets: ['10.1.0.81:9100'], labels: { region: lome } }
  - job_name: securite          # (Palier 3 : la surveillance de conformité, sur la console, par le VPN)
    static_configs: [{ targets: ['10.99.0.2:9100'] }]
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
      - alert: IntrusionDetectee
        expr: sum by (region, sid) (increase(marche_ids_alertes_total{action="allowed"}[5m])) > 0
        labels: { gravite: mineure }
        annotations: { resume: "IDS {{ $labels.region }} : signature {{ $labels.sid }} (balayage, SSH cherché depuis Internet…)" }
      - alert: AttaqueBloquee
        expr: sum by (region, sid) (increase(marche_ids_alertes_total{action="blocked"}[5m])) > 0
        labels: { gravite: majeure }
        annotations: { resume: "IPS {{ $labels.region }} : trafic BLOQUÉ (signature {{ $labels.sid }}) — une attaque est en cours" }
      - alert: NonConformite
        expr: marche_cspm_conforme == 0
        for: 1m
        labels: { gravite: majeure }
        annotations: { resume: "Conformité : la règle « {{ $labels.regle }} » n'est plus respectée (détails : /var/log/cspm.log sur la console)" }
      - alert: ConformiteMuette
        expr: time() - marche_cspm_derniere_execution > 900
        labels: { gravite: mineure }
        annotations: { resume: "La surveillance de conformité ne tourne plus depuis 15 min" }
      - alert: CibleMuette
        expr: up == 0
        for: 1m
        labels: { gravite: mineure }
        annotations: { resume: "{{ $labels.job }} {{ $labels.instance }} ne répond plus à la supervision" }
EOF
# ------------------------------------------------------------------ SLO (Palier 3) et budget d'erreur
# L'objectif : 99,5 % des requêtes servies sans erreur serveur (5xx), sur 30 jours. Le budget : 0,5 %.
# On n'alerte pas sur « il y a des erreurs », mais sur la VITESSE à laquelle on consomme le budget
# (burn rate) — sur deux fenêtres à la fois : la longue prouve que c'est sérieux, la courte que ça
# dure ENCORE (sinon l'alerte sonnerait une heure après la fin de l'incident).
#   14,4× sur 1 h ET 5 min : 2 % du budget mensuel en une heure → on réveille quelqu'un
#   6× sur 6 h ET 30 min   : 5 % en six heures → un ticket
# (et une copie « lab », fenêtres divisées par 12, pour pouvoir le voir en quelques minutes)
sed -i "s|^rule_files: \['/etc/prometheus/alertes.yml'\]|rule_files: ['/etc/prometheus/alertes.yml', '/etc/prometheus/slo.yml']|" /etc/prometheus/prometheus.yml
{
    printf 'groups:\n  - name: slo-disponibilite\n    rules:\n'
    for w in 30s 2m30s 5m 30m 1h 6h 1d; do
        printf '      - record: marche:sli_erreurs:ratio_rate%s\n        expr: |\n' "$w"
        printf '          sum(rate(haproxy_frontend_http_responses_total{proxy="https",code="5xx"}[%s]))\n' "$w"
        printf '            / clamp_min(sum(rate(haproxy_frontend_http_responses_total{proxy="https"}[%s])), 1e-9)\n' "$w"
    done
    cat <<'EOF2'
      - record: marche:budget_erreur:restant_1d      # (sur 1 jour ici : la rétention du lab est de 7 jours)
        expr: 1 - marche:sli_erreurs:ratio_rate1d / 0.005
      - alert: BudgetErreurRapide
        expr: marche:sli_erreurs:ratio_rate1h > 14.4 * 0.005 and marche:sli_erreurs:ratio_rate5m > 14.4 * 0.005
        labels: { gravite: critique }
        annotations: { resume: "Le budget d'erreur brûle 14× trop vite (1 h et 5 min) : 2 % du budget du mois en une heure" }
      - alert: BudgetErreurLent
        expr: marche:sli_erreurs:ratio_rate6h > 6 * 0.005 and marche:sli_erreurs:ratio_rate30m > 6 * 0.005
        labels: { gravite: majeure }
        annotations: { resume: "Le budget d'erreur brûle 6× trop vite (6 h et 30 min)" }
      - alert: BudgetErreurRapideLab
        expr: marche:sli_erreurs:ratio_rate5m > 14.4 * 0.005 and marche:sli_erreurs:ratio_rate30s > 14.4 * 0.005
        labels: { gravite: critique, echelle: lab }
        annotations: { resume: "(échelle du lab, fenêtres ÷ 12) le budget d'erreur brûle 14× trop vite" }
      - alert: BudgetErreurLentLab
        expr: marche:sli_erreurs:ratio_rate30m > 6 * 0.005 and marche:sli_erreurs:ratio_rate2m30s > 6 * 0.005
        labels: { gravite: majeure, echelle: lab }
        annotations: { resume: "(échelle du lab, fenêtres ÷ 12) le budget d'erreur brûle 6× trop vite" }
EOF2
} > /etc/prometheus/slo.yml
promtool check rules /etc/prometheus/slo.yml >/dev/null

# ------------------------------------------------------------------ FinOps (Palier 3) : le coût d'UNE commande
# « Combien coûte l'infrastructure ? » ne dit rien au métier ; « combien coûte une commande, et
# pourquoi ça change ? » oui. Un modèle SIMPLE, aux prix FICTIFS (à remplacer par ceux de votre
# fournisseur) : les instances d'application (0,05 €/h chacune), une base fixe (le reste de la
# plateforme : 1,20 €/h), et le trafic entre régions (0,02 €/Go — il traverse le circuit ou le tunnel).
sed -i "s|^rule_files: \['/etc/prometheus/alertes.yml', '/etc/prometheus/slo.yml'\]|rule_files: ['/etc/prometheus/alertes.yml', '/etc/prometheus/slo.yml', '/etc/prometheus/finops.yml']|" /etc/prometheus/prometheus.yml
cat > /etc/prometheus/finops.yml <<'EOF2'
groups:
  - name: finops
    interval: 1m
    rules:
      - record: marche:instances_application:nombre
        expr: count by (region) (up{job="applications"} == 1)
      - record: marche:cout_euros:par_heure
        labels: { poste: applications }
        expr: sum(marche:instances_application:nombre) * 0.05
      - record: marche:cout_euros:par_heure
        labels: { poste: plateforme }
        expr: vector(1.20)
      - record: marche:cout_euros:par_heure
        labels: { poste: trafic_inter_regions }
        expr: sum(rate(node_network_transmit_bytes_total{job="passerelles",device=~"wg0|fibre"}[1h])) * 3600 / 1e9 * 0.02
      - record: marche:commandes:par_heure
        expr: sum(rate(http_requests_total{job="applications",route="/api/orders",method="POST",status=~"201|402"}[1h])) * 3600
      # l'unit economics : le coût complet d'une commande (et il BAISSE quand l'activité monte : les
      # coûts fixes se partagent — c'est ce que l'autoscaler doit préserver en réduisant la nuit)
      - record: marche:cout_euros:par_commande
        expr: sum(marche:cout_euros:par_heure) / clamp_min(marche:commandes:par_heure, 1)
EOF2
promtool check rules /etc/prometheus/finops.yml >/dev/null
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
