#!/bin/bash
# app — un serveur d'application. Aucun secret dans son « user data » : il s'authentifie auprès
# d'OpenBao avec SON certificat client (émis par Terraform, signé par l'AC intermédiaire), comme
# une instance cloud avec un rôle IAM ; l'agent OpenBao écrit /etc/marche/*.env avec des
# identifiants de base TEMPORAIRES et redémarre le service quand ils changent.
# shellcheck source=commun.sh
. /lab/roles/commun.sh
vlan "$VLAN" "$ADRESSE4" "$GW" "$ADRESSE6"; reseau_pret "baie.$VLAN" "$ADRESSE4"; resolveur "$GW"
install -d -m 750 -o root -g marche /etc/marche
install -d -m 700 /etc/bao-agent
install -m 600 /lab/tls/client.key /etc/bao-agent/client.key
install -m 644 /lab/tls/client.crt /etc/bao-agent/client.crt
install -m 644 /lab/tls/racine.crt /etc/bao-agent/racine.crt
# la version déployée (celle du groupe) : exposée par /healthz et dans les métriques de chaque service
for s in gateway orders payments; do printf 'SERVICE_VERSION=%s\n' "${VERSION:-inconnue}" > "/etc/marche/$s.env"; done
printf 'LISTEN_HOST=0.0.0.0\n' >> /etc/marche/gateway.env
cat > /etc/bao-agent/agent.hcl <<'EOF2'
vault {
  address     = "https://coffre.marche.test:8200"
  ca_cert     = "/etc/bao-agent/racine.crt"
  client_cert = "/etc/bao-agent/client.crt"
  client_key  = "/etc/bao-agent/client.key"
}
auto_auth {
  method "cert" {
    config = { name = "app" }
    # instance démarrée avant la plateforme : réessayer vite (par défaut, l'attente monte à 5 min)
    min_backoff = "2s"
    max_backoff = "10s"
  }
}
template_config { exit_on_retry_failure = false }
template {
  destination = "/etc/marche/marche.env"
  perms       = "0640"
  # restart, pas try-restart : try-restart ne DÉMARRE pas un service arrêté (au premier rendu, il l'est)
  command     = "chgrp marche /etc/marche/marche.env && systemctl restart marche.target"
  # Les options TCP de la connexion : une base qui DISPARAÎT (région perdue) ne répond plus rien — pas
  # même un refus. Sans borne, chaque requête attend la fin des retransmissions TCP (des minutes) et
  # bloque tous les fils du service. tcp_user_timeout : 5 s sans accusé de réception → connexion morte.
  contents    = <<TPL
{{ with secret "base/creds/app" -}}
DATABASE_URL=postgresql://{{ .Data.username }}:{{ .Data.password }}@db.marche.test:5432/marche?connect_timeout=3&tcp_user_timeout=5000&keepalives_idle=5&keepalives_interval=2&keepalives_count=2
{{- end }}
ORDERS_URL=http://127.0.0.1:8001
PAYMENTS_URL=http://127.0.0.1:8002
LISTEN_HOST=127.0.0.1
TPL
}
template {
  destination = "/etc/marche/s3.env"
  perms       = "0640"
  command     = "chgrp marche /etc/marche/s3.env"
  contents    = <<TPL
{{ with secret "kv/data/marche/s3-app" -}}
AWS_ACCESS_KEY_ID={{ .Data.data.access_key }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.secret_key }}
{{- end }}
TPL
}
EOF2
cat > /etc/systemd/system/bao-agent.service <<'EOF2'
[Unit]
Description=Agent OpenBao — identifiants temporaires de l'application
After=network-online.target
[Service]
ExecStart=/usr/local/bin/bao agent -config=/etc/bao-agent/agent.hcl
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF2
# Un arrêt « propre » attend que les connexions se ferment ; à Lomé, des requêtes vers la base
# d'Europe peuvent pendre — sans borne, systemd attend 90 s avant de tuer (le site est 503 d'autant).
install -d /etc/systemd/system/marche@.service.d
printf '[Service]\nTimeoutStopSec=10\n' > /etc/systemd/system/marche@.service.d/arret.conf
systemctl daemon-reload && systemctl enable -q bao-agent && systemctl restart bao-agent
pare_feu "        ip saddr ${LB_SOURCE} tcp dport 8000 accept
        ip saddr ${SUPERVISION:-127.0.0.1} tcp dport 8000 accept
        ip saddr ${ADMIN} tcp dport 22 accept"
systemctl enable -q marche.target
# l'application démarre dès que l'agent a écrit sa configuration (qu'il redémarre ensuite lui-même)
for _ in $(seq 30); do [ -s /etc/marche/marche.env ] && break; sleep 2; done
[ -s /etc/marche/marche.env ] && systemctl restart marche.target
cle_admin
echo "app prête"
