#!/bin/bash
# coffre — le gestionnaire de secrets (OpenBao, la branche libre de Vault) du VPC Europe.
# ⚠️ Simplification de lab : une seule part de la clé de descellement, gardée sur la machine et
# réutilisée à chaque démarrage. En production : descellement automatique par un KMS/HSM, ou
# plusieurs parts confiées à des personnes différentes (Shamir).
# shellcheck source=commun.sh
. /lab/roles/commun.sh
vlan "$VLAN" "$ADRESSE4" "$GW" "$ADRESSE6"; reseau_pret "baie.$VLAN" "$ADRESSE4"; resolveur "$GW"
install -d -m 700 -o root /etc/bao /var/lib/bao
install -m 600 /lab/tls/coffre.key /etc/bao/coffre.key
install -m 644 /lab/tls/coffre.crt /etc/bao/coffre.crt
cat > /etc/bao/bao.hcl <<EOF2
# OpenBao n'est pas Vault à l'identique : pas de stockage « file », ni de « disable_mlock » —
# son stockage intégré (Raft) est le choix par défaut, même pour un seul nœud.
storage "raft" {
  path    = "/var/lib/bao"
  node_id = "coffre"
}
cluster_addr  = "https://${ADRESSE4%/*}:8201"
listener "tcp" {
  address       = "${ADRESSE4%/*}:8200"
  tls_cert_file = "/etc/bao/coffre.crt"
  tls_key_file  = "/etc/bao/coffre.key"
}
api_addr      = "https://coffre.marche.test:8200"
ui            = false
EOF2
cat > /etc/systemd/system/bao.service <<'EOF2'
[Unit]
Description=OpenBao — gestionnaire de secrets
After=network-online.target
[Service]
ExecStart=/usr/local/bin/bao server -config=/etc/bao/bao.hcl
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF2
systemctl daemon-reload && systemctl enable -q bao && systemctl restart bao
export BAO_ADDR="https://${ADRESSE4%/*}:8200" BAO_CACERT=/lab/tls/racine.crt BAO_TLS_SERVER_NAME=coffre.marche.test
# « bao status » : 0 = descellé, 2 = scellé (c'est une réponse !), 1 = injoignable. Sous « set -e »,
# un 2 arrêterait le script : on capture le code.
for _ in $(seq 30); do rc=0; bao status >/dev/null 2>&1 || rc=$?; [ "$rc" -ne 1 ] && break; sleep 1; done
if [ ! -s /var/lib/bao/init.json ]; then
    ( umask 077; bao operator init -key-shares=1 -key-threshold=1 -format=json > /var/lib/bao/init.json )
fi
bao operator unseal "$(jq -r '.unseal_keys_b64[0]' /var/lib/bao/init.json)" >/dev/null
pare_feu "        ip saddr { ${COFFRE_CLIENTS} } tcp dport 8200 accept
        ip saddr ${SUPERVISION:-127.0.0.1} tcp dport 8200 accept
        ip saddr ${ADMIN} tcp dport 22 accept"
cle_admin
echo "coffre prêt (descellé)"
