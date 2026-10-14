#!/bin/bash
# edge — le nœud CDN de Lomé : static.marche.test est servi ICI, à quelques mètres des clients,
# au lieu de traverser l'océan (≈ 120 ms) à chaque fois. Il ne va chercher à l'origine
# (https://www.marche.test/static/) que ce qu'il n'a pas encore, et garde le reste selon
# l'en-tête Cache-Control de l'origine.
# usage : edge.sh   (avec /root/static.pem : clé + chaîne, et /root/racine.crt)
set -euo pipefail

cat > /etc/systemd/network/10-internet.network <<'EOF'
[Match]
Name=internet
[Network]
Gateway=192.0.2.1
KeepConfiguration=yes
LinkLocalAddressing=no
EOF
systemctl enable -q systemd-networkd && systemctl restart systemd-networkd
printf 'nameserver 192.0.2.35\n' > /etc/resolv.conf     # le résolveur du FAI local

install -d -m 750 -o root -g www-data /etc/nginx/tls
install -m 640 -o root -g www-data /root/static.pem /etc/nginx/tls/static.pem
install -m 644 /root/racine.crt /etc/nginx/tls/racine.crt

cat > /etc/nginx/sites-available/cdn <<'EOF'
proxy_cache_path /var/cache/nginx/cdn levels=1:2 keys_zone=cdn:10m max_size=1g inactive=7d use_temp_path=off;

server {
    listen 80;
    server_name static.marche.test;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;             # (nginx 1.24 d'Ubuntu 24.04 : pas encore « http2 on; », apparu en 1.25.1)
    server_name static.marche.test;
    ssl_certificate     /etc/nginx/tls/static.pem;
    ssl_certificate_key /etc/nginx/tls/static.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    server_tokens off;

    location / {
        proxy_pass https://www.marche.test/static/;
        proxy_http_version 1.1;
        # l'origine est authentifiée : même un CDN vérifie à qui il parle
        proxy_ssl_server_name on;
        proxy_ssl_name www.marche.test;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/tls/racine.crt;

        proxy_cache cdn;
        proxy_cache_lock on;                          # 100 clients, 1 seule requête vers l'origine
        proxy_cache_use_stale error timeout updating; # l'origine tombe : on sert ce qu'on a
        add_header X-Cache $upstream_cache_status always;
    }
}
EOF
# le paquet nginx d'Ubuntu ne crée pas /var/cache/nginx (celui de nginx.org, si)
install -d -o www-data -g www-data /var/cache/nginx/cdn
ln -sf /etc/nginx/sites-available/cdn /etc/nginx/sites-enabled/cdn
rm -f /etc/nginx/sites-enabled/default
nginx -t -q

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
        tcp dport { 80, 443 } accept
        ip saddr 192.0.2.60 tcp dport 22 accept          # la console (même ville)
    }
}
EOF
nft -c -f /etc/nftables.conf && systemctl enable -q nftables && { systemctl reload nftables 2>/dev/null || systemctl start nftables; }
systemctl enable -q nginx && systemctl restart nginx
echo "edge prêt"
