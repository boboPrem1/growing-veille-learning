#!/usr/bin/env bash
# sinistre.sh — l'épreuve finale du Palier 3 : un incendie emporte db1 et web2.
# À lancer SUR L'HÔTE du lab (votre PC pour le lab Docker, le VPS pour le lab LXD) :
#
#   ./outils/sinistre.sh docker|lxd
#
# 1. relève, sur db1, ce qu'une bonne reprise doit retrouver : les commandes antérieures au
#    dernier instantané restic (la perte tolérée est ce qui a suivi : le RPO) ;
# 2. DÉTRUIT db1 et web2, puis les recrée vierges (comme un hébergeur livre des machines neuves) ;
# 3. démarre le chronomètre (RTO : 30 minutes).
# Ensuite, sur ctl : reconstruire (Ansible), restaurer, puis  ./verifier-infra.sh --sinistre
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

mode=${1:?usage : $0 docker|lxd}
case $mode in
    docker) ex() { docker exec -i "$1" bash -c "$2"; }; LAB=lab/docker/lab.sh ;;
    lxd)    CLI=lxc; command -v incus >/dev/null && CLI=incus
            ex() { $CLI exec "$1" -- bash -c "$2"; }; LAB=lab/lxd/lab.sh ;;
    *) echo "docker ou lxd" >&2; exit 2 ;;
esac

echo "▶ Relevé sur db1 avant le sinistre"
releve=$(ex db1 'set -a; . /etc/restic/marche.env; set +a
  t=$(restic snapshots --tag marche --latest 1 --json | python3 -c "import sys,json,datetime; print(int(datetime.datetime.fromisoformat(json.load(sys.stdin)[-1][\"time\"]).timestamp()))")
  q() { runuser -u postgres -- psql -tAc "$1" marche; }
  echo "instantane=$t"
  echo "minimum_attendu=$(q "select count(*) from orders where created_at <= to_timestamp($t)")"
  echo "avant=$(q "select count(*) from orders")"')
instantane=""; minimum_attendu=""; avant=""
eval "$releve"
[ -n "$instantane" ] && [ -n "$minimum_attendu" ] || { echo "Relevé impossible (dépôt restic, base ?) : pas de sinistre." >&2; exit 1; }
# L'heure de ctl, pas celle de l'hôte : c'est sur ctl que le correcteur calcule la durée
# (même horloge au départ et à l'arrivée, quel que soit l'hôte).
debut=$(ex ctl 'date +%s')
printf '  dernier instantané : %s\n  commandes avant le sinistre : %s (dont %s couvertes par le dernier instantané)\n' \
    "$(date -d "@$instantane" '+%F %T' 2>/dev/null || echo "$instantane")" "$avant" "$minimum_attendu"

echo "▶ Enregistrement sur ctl (pour verifier-infra.sh --sinistre)"
ex ctl "mkdir -p /var/lib/fil-rouge && printf 'debut=%s\nminimum_attendu=%s\navant=%s\n' $debut $minimum_attendu $avant > /var/lib/fil-rouge/sinistre && chmod 644 /var/lib/fil-rouge/sinistre"

echo "▶ 🔥 Destruction de db1 et web2"
# (printf et non « yes oui | … » : yes écrirait encore après la fin de lab.sh, mourrait de
#  SIGPIPE, et pipefail + set -e arrêteraient ce script au milieu du sinistre)
for m in db1 web2; do printf 'oui\n' | "$LAB" detruire "$m" >/dev/null; done
echo "▶ Livraison de machines neuves (vierges)"
for m in db1 web2; do "$LAB" recreer "$m"; done

cat <<EOF

⏱  Chronomètre lancé à $(date '+%T'). Objectif : service rétabli ET données restaurées avant $(date -d "@$((debut + 1800))" '+%T' 2>/dev/null || echo "+30 min").
   Sur ctl : ssh-keygen -R (les machines ont de nouvelles clés d'hôte), Ansible, restauration,
   puis : ./verifier-infra.sh --sinistre
EOF
