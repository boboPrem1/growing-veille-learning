#!/bin/bash
# stockage — stockage OBJET compatible S3 (SeaweedFS), avec une API IAM : l'équivalent d'S3 + IAM.
# usage : stockage.sh <secret de l'administrateur>
set -euo pipefail
ADMIN_SECRET=${1:?secret administrateur}
bash /root/vlan.sh 30 20 20

install -d -m 700 /var/lib/weed /etc/weed
# L'identité administrateur (« compte racine ») : à ne JAMAIS donner à une application.
cat > /etc/weed/admin.env <<EOF
AWS_ACCESS_KEY_ID=admin-marche
AWS_SECRET_ACCESS_KEY=$ADMIN_SECRET
EOF
chmod 600 /etc/weed/admin.env
cat > /etc/systemd/system/weed.service <<'EOF'
[Unit]
Description=SeaweedFS — stockage objet S3 + IAM
After=network-online.target
[Service]
EnvironmentFile=/etc/weed/admin.env
ExecStart=/usr/local/bin/weed mini -dir=/var/lib/weed -ip=10.0.3.20 -s3.iam.readOnly=false -admin.ui=false
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable -q weed && systemctl restart weed
for _ in $(seq 60); do curl -s -o /dev/null -m 2 http://10.0.3.20:8333/ && break; sleep 1; done

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
        # l'API S3 : applications et répartiteur ; rien d'autre (ni l'admin UI, ni le master…)
        ip saddr { 10.0.2.0/24, 10.0.1.10 } tcp dport 8333 accept
        ip saddr 10.99.0.0/24 tcp dport 22 accept
    }
}
EOF
nft -c -f /etc/nftables.conf && systemctl enable -q nftables && { systemctl reload nftables 2>/dev/null || systemctl start nftables; }

# ---------------------------------------------------------------- buckets et IAM
set -a; . /etc/weed/admin.env; set +a
export AWS_DEFAULT_REGION=us-east-1 AWS_ENDPOINT_URL=http://10.0.3.20:8333
existe() { aws s3api head-bucket --bucket "$1" >/dev/null 2>&1; }
existe marche-statique || aws s3 mb s3://marche-statique >/dev/null
existe marche-factures || aws s3 mb s3://marche-factures >/dev/null

# Les ressources statiques du site sont PUBLIQUES en lecture (et en lecture seulement)
cat > /tmp/statique.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Sid":"LecturePublique","Effect":"Allow","Principal":"*",
  "Action":["s3:GetObject"],"Resource":["arn:aws:s3:::marche-statique/*"]}]}
EOF
aws s3api put-bucket-policy --bucket marche-statique --policy file:///tmp/statique.json

# Un utilisateur PAR usage, chacun avec le strict nécessaire (moindre privilège)
utilisateur() {   # utilisateur <nom> <fichier de politique>
    aws iam get-user --user-name "$1" >/dev/null 2>&1 || aws iam create-user --user-name "$1" >/dev/null
    aws iam put-user-policy --user-name "$1" --policy-name "$1" --policy-document "file://$2"
    if [ ! -s "/root/$1.env" ]; then
        # nouvelle clé : les anciennes (perdues) sont révoquées d'abord
        for k in $(aws iam list-access-keys --user-name "$1" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
            aws iam delete-access-key --user-name "$1" --access-key-id "$k"
        done
        cle=$(aws iam create-access-key --user-name "$1" --output json)
        ( umask 077
          jq -r '.AccessKey | "AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nAWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)"' <<< "$cle" > "/root/$1.env" )
    fi
}
# L'application dépose et relit ses factures — ni suppression, ni liste, ni autre bucket
cat > /tmp/app.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:PutObject","s3:GetObject"],
  "Resource":["arn:aws:s3:::marche-factures/*"]}]}
EOF
utilisateur marche-app /tmp/app.json
# La publication des ressources statiques (déploiement du site)
cat > /tmp/publication.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:PutObject","s3:GetObject","s3:ListBucket"],
  "Resource":["arn:aws:s3:::marche-statique","arn:aws:s3:::marche-statique/*"]}]}
EOF
utilisateur marche-publication /tmp/publication.json

# ---------------------------------------------------------------- les ressources statiques du site
d=$(mktemp -d)
printf 'body { font-family: sans-serif; color: #1d3557; }\n' > "$d/app.v1.css"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="40"><text x="4" y="28" font-size="24">Marché</text></svg>\n' > "$d/logo.svg"
head -c 400000 /dev/urandom > "$d/catalogue.jpg"     # une « grosse » image : 400 Ko
set -a; . /root/marche-publication.env; set +a
for f in app.v1.css logo.svg catalogue.jpg; do
    case $f in *.css) t=text/css ;; *.svg) t=image/svg+xml ;; *) t=image/jpeg ;; esac
    # noms VERSIONNÉS (app.v1.css) + cache long : une nouvelle version = un nouveau nom, pas d'invalidation
    aws s3 cp "$d/$f" "s3://marche-statique/$f" --content-type "$t" --cache-control "public, max-age=86400" >/dev/null
done
rm -rf "$d"
echo "stockage prêt"
