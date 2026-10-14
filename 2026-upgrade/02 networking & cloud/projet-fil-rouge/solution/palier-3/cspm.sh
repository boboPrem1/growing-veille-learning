#!/bin/bash
# cspm.sh — la surveillance CONTINUE de la conformité (Cloud Security Posture Management), Palier 3.
# Tourne sur la console (le poste de la sécurité), toutes les 5 minutes (cspm.timer), avec l'identité
# d'AUDIT de la landing zone : elle peut tout lire, rien changer. Chaque règle donne une métrique
# (1 conforme, 0 non conforme), lue par la supervision — une dérive de configuration devient une alerte.
# Les détails de chaque écart : /var/log/cspm.log.
set -uo pipefail
M=/var/lib/prometheus/node-exporter/cspm.prom
LOG=/var/log/cspm.log
aws_audit() { AWS_PROFILE=audit AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt AWS_DEFAULT_REGION=us-east-1 aws --endpoint-url https://s3.fournisseur.test "$@"; }
: > "$M.tmp"
regle() {   # regle <nom> <1|0> <détail>
    printf 'marche_cspm_conforme{regle="%s"} %s\n' "$1" "$2" >> "$M.tmp"
    [ "$2" = 1 ] || printf '%s NON CONFORME %s : %s\n' "$(date -Is)" "$1" "$3" >> "$LOG"
}

# 1. aucun bucket public chez le fournisseur (une politique qui ouvre à « * »)
publics=""
for b in $(aws_audit s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null); do
    aws_audit s3api get-bucket-policy --bucket "$b" --output text 2>/dev/null | grep -q '"Principal": *"\*"\|"AWS": *"\*"' && publics+="$b "
done
regle bucket_public "$([ -z "$publics" ] && echo 1 || echo 0)" "ouverts à tous : $publics"

# 2. l'état Terraform est versionné (on peut revenir en arrière après une corruption)
v=$(aws_audit s3api get-bucket-versioning --bucket marche-etat-terraform --query Status --output text 2>/dev/null)
regle etat_versionne "$([ "$v" = Enabled ] && echo 1 || echo 0)" "versionnage : ${v:-absent}"

# 3. les sauvegardes sont chiffrées côté client (le fournisseur ne voit que du bruit)
k=$(aws_audit s3 ls s3://marche-sauvegardes/ --recursive 2>/dev/null | awk '/\.gz$/ {print $4}' | tail -1)
entete=$([ -n "$k" ] && aws_audit s3 cp "s3://marche-sauvegardes/$k" - 2>/dev/null | head -c 8)
regle sauvegardes_chiffrees "$([ "$entete" = Salted__ ] && echo 1 || echo 0)" "en-tête de $k : ${entete:-illisible}"

# 4. aucune identité n'a de droits sans limite (s3:* sur tout)
# Une EXCEPTION se documente (qui, pourquoi, jusqu'à quand) — elle ne s'ignore pas en silence :
#   admin-* : les clés RACINE du compte, avec lesquelles tourne Terraform. Risque accepté pour le lab ;
#   en production : un rôle de déploiement dédié, aux droits bornés, et des clés racine au coffre.
EXCEPTIONS='^admin-'
larges=""
for u in $(aws_audit iam list-users --query 'Users[].UserName' --output text 2>/dev/null); do
    if [[ $u =~ $EXCEPTIONS ]]; then printf '%s exception acceptée droits_illimites : %s (clés racine, Terraform)\n' "$(date -Is)" "$u" >> "$LOG"; continue; fi
    for p in $(aws_audit iam list-user-policies --user-name "$u" --query 'PolicyNames' --output text 2>/dev/null); do
        aws_audit iam get-user-policy --user-name "$u" --policy-name "$p" --output json 2>/dev/null \
          | jq -e '[.PolicyDocument.Statement[] | select(.Effect == "Allow")
                    | select([.Action] | flatten | any(. == "*" or . == "s3:*"))
                    | select([.Resource] | flatten | any(. == "*" or . == "arn:aws:s3:::*"))] | length > 0' >/dev/null 2>&1 \
          && larges+="$u/$p "
    done
done
regle droits_illimites "$([ -z "$larges" ] && echo 1 || echo 0)" "politiques sans limite : $larges"

# 5. chaque machine du projet est étiquetée (qui paie, quel environnement, quelle région)
sans=$(docker ps --filter label=projet=marche --format '{{.Names}} {{.Label "equipe"}} {{.Label "env"}} {{.Label "region"}}' | awk 'NF < 4 {print $1}' | paste -sd' ')
regle etiquettes "$([ -z "$sans" ] && echo 1 || echo 0)" "sans étiquettes complètes : $sans"

# 6. rien ne tourne hors du code (une machine lancée à la main n'est dans aucun état Terraform)
reel=$(docker ps --filter label=projet=marche --format '{{.Names}}' | sort)
code=$(cd /root/p2/terraform/regions && terraform state list 2>/dev/null | grep -o 'module.machine\["[^"]*"\]' | cut -d'"' -f2 | sort)
fantomes=$(comm -23 <(echo "$reel") <(echo "$code") | paste -sd' ')
regle hors_code "$([ -z "$fantomes" ] && [ -n "$code" ] && echo 1 || echo 0)" "hors de tout état Terraform : $fantomes"

# 7. SSH n'est ouvert à Internet nulle part (on administre par le VPN)
ouverts=""
for a in 198.51.100.10 198.51.100.100 198.51.100.200 203.0.113.10 192.0.2.100; do
    timeout 3 bash -c "</dev/tcp/$a/22" 2>/dev/null && ouverts+="$a "
done
regle ssh_expose "$([ -z "$ouverts" ] && echo 1 || echo 0)" "SSH ouvert sur Internet : $ouverts"

# 8. le certificat du site n'expire pas dans les 14 jours
fin=$(echo | timeout 5 openssl s_client -connect 198.51.100.200:443 -servername www.marche.test 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
reste=$(( ( $(date -d "${fin:-now}" +%s) - $(date +%s) ) / 86400 ))
regle certificat_site "$([ "$reste" -gt 14 ] && echo 1 || echo 0)" "le certificat de www expire dans $reste jour(s)"

printf 'marche_cspm_derniere_execution %s\n' "$(date +%s)" >> "$M.tmp"
mv "$M.tmp" "$M"
