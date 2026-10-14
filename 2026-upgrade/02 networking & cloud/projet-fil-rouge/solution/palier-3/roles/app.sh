#!/bin/bash
# app — un serveur d'application. Aucun secret dans son « user data » : il s'authentifie auprès
# d'OpenBao avec SON certificat client (émis par Terraform, signé par l'AC intermédiaire), comme
# une instance cloud avec un rôle IAM ; l'agent OpenBao écrit /etc/marche/*.env avec des
# identifiants de base TEMPORAIRES et redémarre le service quand ils changent.
# Palier 3 (Zero Trust) : l'application n'écoute plus que sur 127.0.0.1. Devant elle, un « sidecar »
# (nginx) en mTLS sur le port 8443 : il ne laisse entrer que des identités — le répartiteur (lb) pour
# l'API, la supervision pour /metrics — et PAS des adresses. Vers la base : TLS vérifié, et un
# certificat client. Identité de 24 h, renouvelée par l'agent.
# shellcheck source=commun.sh
. /lab/roles/commun.sh
vlan "$VLAN" "$ADRESSE4" "$GW" "$ADRESSE6"; reseau_pret "baie.$VLAN" "$ADRESSE4"; resolveur "$GW"
install -d -m 750 -o root -g marche /etc/marche
# la version déployée (celle du groupe) : exposée par /healthz et dans les métriques de chaque service
for s in gateway orders payments; do printf 'SERVICE_VERSION=%s\n' "${VERSION:-inconnue}" > "/etc/marche/$s.env"; done

# ------------------------------------------------------------------ l'identité, et le sidecar mTLS
identite app app.svc.marche.test marche "systemctl reload-or-restart nginx"
cat > /etc/nginx/sites-available/default <<'EOF2'
# Le sidecar : la seule porte d'entrée de l'application. TLS 1.3, certificat client OBLIGATOIRE
# (signé par l'AC des identités de service), et l'autorisation se fait sur l'IDENTITÉ présentée.
map $ssl_client_s_dn $identite {
    ~CN=lb\.svc\.marche\.test           lb;
    ~CN=supervision\.svc\.marche\.test  supervision;
    default                             inconnue;
}
server {
    listen 8443 ssl;
    ssl_protocols TLSv1.3;
    ssl_certificate         /etc/identite/service.crt;
    ssl_certificate_key     /etc/identite/service.key;
    ssl_client_certificate  /etc/identite/ca.pem;
    ssl_verify_client       on;
    location = /metrics {
        if ($identite != supervision) { return 403; }
        proxy_pass http://127.0.0.1:8000;
    }
    location / {
        if ($identite != lb) { return 403; }
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
        proxy_set_header X-Identite-Client $identite;
    }
}
EOF2
nginx -t -q && systemctl enable -q nginx && systemctl restart nginx

cat > /etc/bao-agent/app.hcl <<'EOF2'
template {
  destination = "/etc/marche/marche.env"
  perms       = "0640"
  # restart, pas try-restart : try-restart ne DÉMARRE pas un service arrêté (au premier rendu, il l'est)
  command     = "chgrp marche /etc/marche/marche.env && systemctl restart marche.target"
  # Les options TCP de la connexion : une base qui DISPARAÎT (région perdue) ne répond plus rien — pas
  # même un refus. Sans borne, chaque requête attend la fin des retransmissions TCP (des minutes) et
  # bloque tous les fils du service. tcp_user_timeout : 5 s sans accusé de réception → connexion morte.
  # Palier 3 : TLS VÉRIFIÉ (le serveur doit être db.marche.test, signé par l'AC des services), et notre
  # certificat d'identité en guise de pièce d'identité — en plus de l'identifiant temporaire.
  contents    = <<TPL
{{ with secret "base/creds/app" -}}
DATABASE_URL=postgresql://{{ .Data.username }}:{{ .Data.password }}@db.marche.test:5432/marche?connect_timeout=3&tcp_user_timeout=5000&keepalives_idle=5&keepalives_interval=2&keepalives_count=2&sslmode=verify-full&sslrootcert=/etc/identite/ca.pem&sslcert=/etc/identite/service.crt&sslkey=/etc/identite/service.key
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
# Un arrêt « propre » attend que les connexions se ferment ; à Lomé, des requêtes vers la base
# d'Europe peuvent pendre — sans borne, systemd attend 90 s avant de tuer (le site est 503 d'autant).
install -d /etc/systemd/system/marche@.service.d
printf '[Service]\nTimeoutStopSec=10\n' > /etc/systemd/system/marche@.service.d/arret.conf
agent_openbao app
# (le réseau ne choisit plus qui entre : seul le port du sidecar est ouvert — l'identité fait le reste)
pare_feu "        ip saddr { ${LB_SOURCE}, ${SUPERVISION:-127.0.0.1} } tcp dport 8443 accept
        ip saddr ${ADMIN} tcp dport 22 accept"
systemctl enable -q marche.target
# l'application démarre dès que l'agent a écrit sa configuration (qu'il redémarre ensuite lui-même)
for _ in $(seq 30); do [ -s /etc/marche/marche.env ] && break; sleep 2; done
[ -s /etc/marche/marche.env ] && systemctl restart marche.target
cle_admin
echo "app prête"
