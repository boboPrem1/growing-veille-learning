#!/bin/bash
# bootstrap.sh — SUR LA CONSOLE, une fois, avant tout Terraform : ce que Terraform ne peut pas
# créer lui-même.
#   1. le bucket de l'ÉTAT Terraform (chez le fournisseur), versionné : on ne range pas son état
#      dans un stockage que ce même Terraform crée (et détruirait) ;
#   2. les clés WireGuard (Terraform ne sait pas en fabriquer) et le VPN de la console ;
#   3. la configuration du backend (etat.hcl), partagée par les couches.
# Prérequis : /root/.aws/credentials, profil « fournisseur » (./lab/docker/lab.sh identifiants).
set -euo pipefail
cd "$(dirname "$0")"
export AWS_PROFILE=fournisseur AWS_DEFAULT_REGION=us-east-1
# la CLI AWS a son propre magasin de certificats : on lui désigne celui du système
export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
S3=https://s3.fournisseur.test
SEAU=marche-etat-terraform

# ------------------------------------------------------------------ 1. bucket d'état, versionné
aws --endpoint-url $S3 s3api head-bucket --bucket $SEAU 2>/dev/null || aws --endpoint-url $S3 s3 mb s3://$SEAU
aws --endpoint-url $S3 s3api put-bucket-versioning --bucket $SEAU --versioning-configuration Status=Enabled
cat > terraform/etat.hcl <<EOF
bucket                      = "$SEAU"
region                      = "us-east-1"
profile                     = "fournisseur"
endpoints                   = { s3 = "$S3" }
use_path_style              = true
use_lockfile                = true   # verrou : un fichier .tflock à côté de l'état (Terraform ≥ 1.10)
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
skip_region_validation      = true
EOF

# ------------------------------------------------------------------ 2. clés WireGuard, clé SSH
install -d -m 700 /root/cles/wg
for n in europe lome console; do
    [ -s /root/cles/wg/$n.key ] || (umask 077; wg genkey > /root/cles/wg/$n.key)
    wg pubkey < /root/cles/wg/$n.key > /root/cles/wg/$n.pub
done
[ -s /root/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C admin@console -f /root/.ssh/id_ed25519

# le VPN de la console : un seul pair (l'Europe), qui transite vers Lomé (hub-and-spoke)
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.99.0.2/24
PrivateKey = $(cat /root/cles/wg/console.key)

[Peer]  # la passerelle d'Europe
PublicKey = $(cat /root/cles/wg/europe.pub)
Endpoint = 203.0.113.10:51820
AllowedIPs = 10.0.0.0/16, 10.1.0.0/16, 10.99.0.0/24
PersistentKeepalive = 25
EOF
chmod 600 /etc/wireguard/wg0.conf
systemctl enable -q wg-quick@wg0 && systemctl restart wg-quick@wg0

# ------------------------------------------------------------------ l'état VOULU de la flotte
# Taille, version et couleur active de chaque groupe : des variables Terraform, modifiées par le pipeline
# et l'autoscaler. Créées ICI (une fois), jamais écrasées par une nouvelle copie du code : ce sont
# des décisions d'exploitation, pas du code (en équipe : un dépôt à part, ou des commits du pipeline).
f=terraform/regions/flotte.auto.tfvars.json
[ -s $f ] || echo '{"groupes":{"europe-bleu":{"taille":2,"version":"1.0.0"},"europe-vert":{"taille":0,"version":"1.0.0"},"lome-bleu":{"taille":2,"version":"1.0.0"},"lome-vert":{"taille":0,"version":"1.0.0"}}}' > $f
f=terraform/trafic/flotte.auto.tfvars.json
[ -s $f ] || echo '{"couleur_active":{"europe":"bleu","lome":"bleu"},"retrait":[]}' > $f

# ------------------------------------------------------------------ 3. init des couches
for c in fondations regions plateforme trafic; do
    ( cd terraform/$c && terraform init -input=false -no-color -reconfigure \
        -backend-config=../etat.hcl -backend-config="key=$c/terraform.tfstate" >/dev/null )
done
echo "bootstrap terminé : état dans s3://$SEAU (versionné, verrouillé)."
