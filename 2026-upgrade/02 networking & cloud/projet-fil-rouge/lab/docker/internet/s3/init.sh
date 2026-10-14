#!/bin/bash
# « s3.fournisseur.test » : le service S3 MANAGÉ du fournisseur (région Europe), comme Amazon S3.
# Il existe en dehors de vos VPC : on y range ce qui doit survivre à vos machines (l'état
# Terraform, les sauvegardes hors région). HTTPS, certificat de l'« AC publique du lab ».
set -e
ip route replace default via 203.0.113.1
printf 'nameserver 192.0.2.35\n' > /etc/resolv.conf
install -d -m 700 /var/lib/s3 /etc/s3
# L'identité racine du « compte » : générée au premier démarrage, gardée ici (et affichée par
# « lab.sh identifiants »). Le lab ne la connaît pas d'avance.
if [ ! -s /etc/s3/compte.env ]; then
    ( umask 077; printf 'AWS_ACCESS_KEY_ID=MARCHE%s\nAWS_SECRET_ACCESS_KEY=%s\n' \
        "$(openssl rand -hex 6 | tr a-f A-F)" "$(openssl rand -base64 30 | tr -d '/+=')" > /etc/s3/compte.env )
fi
cat > /etc/systemd/system/s3.service <<'UNIT'
[Unit]
Description=Service S3 du fournisseur
After=network-online.target
[Service]
EnvironmentFile=/etc/s3/compte.env
ExecStart=/usr/local/bin/weed mini -dir=/var/lib/s3 -ip=203.0.113.30 -s3.iam.readOnly=false -admin.ui=false \
    -s3.port.https=443 -s3.cert.file=/lab/s3.crt -s3.key.file=/lab/s3.key
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
nft -f - <<'NFT'
flush ruleset
table inet s3 {
    chain entree {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        iif lo accept
        icmp type { echo-request, destination-unreachable, time-exceeded } accept
        tcp dport 443 accept          # l'API S3 publique, en HTTPS seulement
    }
}
NFT
systemctl daemon-reload
systemctl enable --now s3
