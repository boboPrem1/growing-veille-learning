#!/bin/bash
# stockage — stockage objet S3 + IAM (SeaweedFS) dans le VLAN des données, comme au Palier 1.
# shellcheck source=commun.sh
. /lab/roles/commun.sh
vlan "$VLAN" "$ADRESSE4" "$GW" "$ADRESSE6"; reseau_pret "baie.$VLAN" "$ADRESSE4"; resolveur "$GW"
install -d -m 700 /var/lib/weed /etc/weed
( umask 077; printf 'AWS_ACCESS_KEY_ID=admin-marche\nAWS_SECRET_ACCESS_KEY=%s\n' "$S3_ADMIN_SECRET" > /etc/weed/admin.env )
cat > /etc/systemd/system/weed.service <<EOF2
[Unit]
Description=SeaweedFS — stockage objet S3 + IAM
After=network-online.target
[Service]
EnvironmentFile=/etc/weed/admin.env
ExecStart=/usr/local/bin/weed mini -dir=/var/lib/weed -ip=${ADRESSE4%/*} -s3.iam.readOnly=false -admin.ui=false
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF2
systemctl daemon-reload && systemctl enable -q weed && systemctl restart weed
for _ in $(seq 60); do curl -s -o /dev/null -m 2 "http://${ADRESSE4%/*}:8333/" && break; sleep 1; done
pare_feu "        ip saddr { ${S3_CLIENTS} } tcp dport 8333 accept
        ip saddr ${ADMIN} tcp dport 22 accept"
# Buckets, politiques, utilisateurs IAM, objets : des ressources Terraform (couche « plateforme »).
cle_admin
echo "stockage prêt"
