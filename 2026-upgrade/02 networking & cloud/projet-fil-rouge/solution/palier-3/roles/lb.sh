#!/bin/bash
# lb — répartiteur L7 d'une région : TLS, HTTP/2, HSTS, routage par chemin, contrôles de santé.
# DECOUVERTE : le nom DNS des instances (plusieurs A) ; DNS_DECOUVERTE : le serveur qui le sert ;
# STATIQUE : « adresse:port » de l'API S3 (ou vide) ; SUPERVISION : qui peut lire les métriques.
# shellcheck source=commun.sh
. /lab/roles/commun.sh
lien pub "" "$GW" "$ADRESSE6"; reseau_pret pub "$ADRESSE6"; resolveur "$GW"
install -d -m 750 -o root -g haproxy /etc/haproxy/certs
install -m 640 -o root -g haproxy /lab/tls/www.pem /etc/haproxy/certs/www.pem
# l'identité de service du répartiteur (24 h, renouvelée ; provisoire tant que le coffre ne l'a pas délivrée)
identite lb lb.svc.marche.test haproxy "systemctl reload haproxy"
agent_openbao lb
{
cat <<'EOF2'
global
    log /dev/log local0
    user haproxy
    group haproxy
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305
defaults
    log global
    mode http
    option httplog
    option forwardfor
    timeout connect 5s
    timeout client  30s
    timeout server  30s
frontend http
    bind :80
    # /sante : la santé de la RÉGION, pour le GSLB — 503 si plus aucune application n'est en service.
    # (Vérifier seulement que le port 443 répond ne suffit pas : un répartiteur sans serveurs l'ouvre
    #  très bien, et renvoie des 503 à tout le monde.)
    monitor-uri /sante
    monitor fail if { nbsrv(applications) lt 1 }
    http-request redirect scheme https code 301
frontend https
    bind :443 ssl crt /etc/haproxy/certs/www.pem alpn h2,http/1.1
    http-response set-header Strict-Transport-Security "max-age=31536000"
    http-request deny if { path_beg /admin }
EOF2
# quelle région a répondu : visible du client (anycast : la plus proche… ou la seule encore debout)
printf '    http-response set-header X-Marche-Region %s\n' "$REGION"
[ -z "${STATIQUE:-}" ] || echo "    use_backend statique if { path_beg /static/ }"
cat <<EOF2
    default_backend applications
# Les instances ne sont pas écrites ici : HAProxy les DÉCOUVRE dans le DNS (le « target group » du
# cloud). Un nom, plusieurs A — un par instance du groupe actif — publiés par la couche plateforme ;
# HAProxy remplit ses emplacements (server-template) et les vide quand une adresse disparaît.
resolvers decouverte
    nameserver pdns ${DNS_DECOUVERTE}:53
    accepted_payload_size 8192
    hold valid 5s
    hold obsolete 5s
    hold nx 5s
    timeout resolve 1s
    timeout retry 1s
    resolve_retries 3
backend applications
    balance leastconn
    option httpchk GET /healthz
    http-check expect status 200
    # une instance qui s'arrête (réduction, déploiement) refuse les connexions : on rejoue la requête
    # AILLEURS — sans risque, puisque rien n'a été envoyé (pas de « response-timeout » : une commande
    # rejouée après coup serait une commande en double)
    retry-on conn-failure empty-response
    retries 3
    option redispatch
    # Zero Trust (Palier 3) : mTLS vers chaque instance — NOTRE identité (lb.svc…) présentée, la SIENNE
    # vérifiée (app.svc.marche.test, signée par l'AC des services). Le contrôle de santé aussi.
    default-server inter 2s fall 2 rise 2 check resolvers decouverte init-addr none resolve-prefer ipv4 ssl verify required ca-file /etc/identite/ca.pem crt /etc/identite/combine.pem verifyhost app.svc.marche.test
    server-template app 8 ${DECOUVERTE}:8443
EOF2
if [ -n "${STATIQUE:-}" ]; then
    printf 'backend statique\n    http-request set-path /marche-statique%%[path,regsub(^/static,)]\n'
    printf '    option httpchk GET /marche-statique/logo.svg\n    server stockage %s check inter 5s\n' "$STATIQUE"
fi
printf 'frontend stats\n    bind 127.0.0.1:8404\n    stats enable\n    stats uri /\n'
# les métriques, pour la supervision (débit, erreurs, serveurs actifs : l'autoscaler s'en sert)
printf 'frontend metriques\n    bind :8405\n    no log\n    http-request use-service prometheus-exporter if { path /metrics }\n'
} > /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null
pare_feu "        tcp dport { 80, 443 } accept
        ip saddr ${SUPERVISION:-127.0.0.1} tcp dport 8405 accept
        ip saddr ${ADMIN} tcp dport 22 accept"
systemctl enable -q haproxy && systemctl restart haproxy
cle_admin
echo "lb prêt"
