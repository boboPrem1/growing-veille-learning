#!/bin/bash
# lb — répartiteur de charge L7 (HAProxy) dans le sous-réseau public : il termine TLS, route selon
# le CHEMIN (/static → stockage objet, le reste → applications) et retire un serveur malade.
# usage : lb.sh    (avec /root/www.pem déposé à côté : clé + certificat + intermédiaire)
set -euo pipefail

cat > /etc/systemd/network/10-pub.network <<'EOF'
[Match]
Name=pub
[Network]
Gateway=10.0.1.1
KeepConfiguration=yes
Address=fd00:4d41:5243:1::10/64
IPv6AcceptRA=yes
EOF
systemctl enable -q systemd-networkd && systemctl restart systemd-networkd
printf 'nameserver 10.0.1.1\n' > /etc/resolv.conf

install -d -m 750 -o root -g haproxy /etc/haproxy/certs
install -m 640 -o root -g haproxy /root/www.pem /etc/haproxy/certs/www.pem

cat > /etc/haproxy/haproxy.cfg <<'EOF'
global
    log /dev/log local0
    user haproxy
    group haproxy
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin
    # TLS 1.2 minimum ; TLS 1.3 négocié quand le client le propose
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305

defaults
    log global
    mode http
    option httplog
    option forwardfor                   # l'adresse du client, pour les applications (X-Forwarded-For)
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend http
    bind :80
    http-request redirect scheme https code 301

frontend https
    bind :443 ssl crt /etc/haproxy/certs/www.pem alpn h2,http/1.1
    http-response set-header Strict-Transport-Security "max-age=31536000"
    http-request deny if { path_beg /admin }
    use_backend statique if { path_beg /static/ }
    default_backend applications

backend applications
    balance leastconn
    option httpchk GET /healthz
    http-check expect status 200
    default-server inter 2s fall 2 rise 2
    server app1 10.0.2.11:8000 check
    server app2 10.0.2.12:8000 check

# /static/logo.svg → GET /marche-statique/logo.svg sur l'API S3 (bucket en lecture publique)
backend statique
    http-request set-path /marche-statique%[path,regsub(^/static,)]
    option httpchk GET /marche-statique/logo.svg
    server stockage 10.0.3.20:8333 check inter 5s

frontend stats
    bind 127.0.0.1:8404
    stats enable
    stats uri /
EOF
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null

cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet sg {
    chain entree {
        type filter hook input priority filter; policy drop;
        ct state invalid drop
        ct state established,related accept
        iif lo accept
        icmp type { echo-request, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
        tcp dport { 80, 443 } accept                      # le site, pour tout le monde
        ip saddr 10.99.0.0/24 tcp dport 22 accept
    }
}
EOF
nft -c -f /etc/nftables.conf && systemctl enable -q nftables && { systemctl reload nftables 2>/dev/null || systemctl start nftables; }
systemctl enable -q haproxy && systemctl restart haproxy
echo "lb prêt"
