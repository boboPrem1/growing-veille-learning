#!/bin/bash
# edge — le nœud CDN de Lomé (cache nginx devant https://www.marche.test/static/).
# shellcheck source=commun.sh
. /lab/roles/commun.sh
lien internet "" "$GW" ""; reseau_pret internet "$ADRESSE4"; resolveur "$RESOLVEUR"
install -d -m 750 -o root -g www-data /etc/nginx/tls
install -m 640 -o root -g www-data /lab/tls/static.pem /etc/nginx/tls/static.pem
install -m 644 /lab/tls/racine.crt /etc/nginx/tls/racine.crt
install -d -o www-data -g www-data /var/cache/nginx/cdn
cat > /etc/nginx/sites-available/cdn <<'EOF2'
proxy_cache_path /var/cache/nginx/cdn levels=1:2 keys_zone=cdn:10m max_size=1g inactive=7d use_temp_path=off;
server {
    listen 80;
    server_name static.marche.test;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    server_name static.marche.test;
    ssl_certificate     /etc/nginx/tls/static.pem;
    ssl_certificate_key /etc/nginx/tls/static.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    server_tokens off;
    # L'origine est résolue À L'EXÉCUTION (resolver + variable), pas au démarrage : sinon nginx
    # refuse de démarrer si le DNS n'est pas prêt, et garde la même adresse pour toujours — une
    # bascule de région (le DNS de www change) lui échapperait. Revérifiée toutes les 30 s.
    resolver RESOLVEUR_ICI valid=30s ipv6=off;
    set $origine www.marche.test;
    location / {
        proxy_pass https://$origine/static$request_uri;
        proxy_http_version 1.1;
        proxy_ssl_server_name on;
        proxy_ssl_name www.marche.test;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/tls/racine.crt;
        proxy_cache cdn;
        proxy_cache_lock on;
        proxy_cache_use_stale error timeout updating;
        add_header X-Cache $upstream_cache_status always;
    }
}
EOF2
sed -i "s/RESOLVEUR_ICI/$RESOLVEUR/" /etc/nginx/sites-available/cdn
ln -sf /etc/nginx/sites-available/cdn /etc/nginx/sites-enabled/cdn
rm -f /etc/nginx/sites-enabled/default
nginx -t -q
pare_feu "        tcp dport { 80, 443 } accept
        ip saddr ${CONSOLE} tcp dport 22 accept"
systemctl enable -q nginx && systemctl restart nginx
cle_admin
echo "edge prêt"
