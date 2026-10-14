#!/bin/bash
# client — les clients de Marché, à Lomé : ils font confiance à VOTRE racine (comme une entreprise
# déploie son AC sur ses postes) et commandent en continu sur https://www.marche.test.
# usage : client.sh   (avec /root/racine.crt déposé à côté)
set -euo pipefail
install -m 644 /root/racine.crt /usr/local/share/ca-certificates/marche-racine.crt
update-ca-certificates >/dev/null 2>&1
cat > /etc/marche/loadgen.env <<'EOT'
GATEWAY_URL=https://www.marche.test
RPS=2
# httpx n'utilise pas le magasin du système : on lui désigne la racine explicitement
SSL_CA_FILE=/usr/local/share/ca-certificates/marche-racine.crt
EOT
chmod 644 /etc/marche/loadgen.env
systemctl enable -q marche-loadgen && systemctl restart marche-loadgen
echo "client prêt"
