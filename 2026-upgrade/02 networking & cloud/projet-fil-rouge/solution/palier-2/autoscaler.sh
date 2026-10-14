#!/usr/bin/env bash
# autoscaler.sh — la boucle de contrôle d'un groupe d'auto-scaling, en « suivi de cible » (target
# tracking) : garder environ CIBLE requêtes/s par instance, dans chaque région. Depuis l'hôte.
#
#   ./autoscaler.sh evaluer        une évaluation (et une action si besoin), puis s'arrête
#   ./autoscaler.sh boucle         évaluer toutes les 30 s, jusqu'à Ctrl-C
#
# La mesure vient de la supervision (Prometheus, par le VPN) : le débit que le répartiteur de la
# région envoie à ses applications. Décision, par région :
#   voulu = ⌈ débit / CIBLE ⌉, borné à [MIN, MAX]
#   voulu > actuel → on AGRANDIT tout de suite (la charge n'attend pas)
#   voulu < actuel → on RÉDUIT d'UNE instance, et seulement après 3 évaluations d'affilée qui le
#                    demandent (fenêtre de stabilisation : sinon le groupe « pompe » au rythme du bruit)
# L'action passe par le même chemin que tout le reste : variable Terraform → plan → politique (ne
# toucher QUE les instances du groupe) → apply. Agrandir : instances d'abord, publication ensuite
# (on n'envoie pas de trafic à une instance qui démarre). Réduire : on retire du DNS AVANT d'éteindre.
set -euo pipefail
export MSYS_NO_PATHCONV=1
# shellcheck source=lib-flotte.sh
. "$(dirname "$0")/lib-flotte.sh"
CIBLE=${CIBLE:-4}          # requêtes/s par instance
MIN=${MIN:-2}
MAX=${MAX:-6}
STABILISATION=3            # évaluations d'affilée avant de réduire
PROM=http://10.1.0.85:9090
MEMOIRE=/root/p2/autoscaler.etat     # (sur la console) le compteur de la fenêtre de stabilisation

debit() {    # debit <region> : requêtes/s vers les applications, moyenne sur 1 min (entier arrondi au-dessus)
    console "curl -s --data-urlencode 'query=sum(rate(haproxy_backend_http_requests_total{proxy=\"applications\",region=\"$1\"}[1m]))' $PROM/api/v1/query" \
        | grep -oE '"value":\[[0-9.]+,"[0-9.eE+-]+"' | cut -d'"' -f4 | awk '{printf "%d", ($1 == int($1)) ? $1 : int($1) + 1}' || true
}

evaluer() {
    local r a g actuel d voulu n
    for r in europe lome; do
        a=$(active "$r"); g="$r-$a"; actuel=$(groupe "$g" taille)
        d=$(debit "$r")
        # pas de mesure (supervision injoignable) : AUCUNE décision — surtout pas « 0 req/s, on réduit »
        [ -n "$d" ] || { etape "$g : mesure indisponible — aucune décision"; continue; }
        voulu=$(( (d + CIBLE - 1) / CIBLE )); [ "$voulu" -lt "$MIN" ] && voulu=$MIN; [ "$voulu" -gt "$MAX" ] && voulu=$MAX
        n=$(console "jq -r '.\"$g\" // 0' $MEMOIRE 2>/dev/null || echo 0")
        if [ "$voulu" -gt "$actuel" ]; then
            etape "$g : $d req/s pour $actuel instance(s) (cible $CIBLE/instance) → AGRANDIR à $voulu"
            memoriser "$g" 0
            regler "$g" taille "$voulu"
            couche regions approuve "\[\"app-$g-[0-9]+\"\]"
            for c in $(instances "$g"); do          # prêtes avant de recevoir du trafic
                for _ in $(seq 60); do docker exec "$c" curl -sf -m 2 -o /dev/null localhost:8000/healthz && break; sleep 2; done
            done
            couche trafic approuve "$(motif_publication "$r")"
        elif [ "$voulu" -lt "$actuel" ]; then
            n=$((n + 1)); memoriser "$g" "$n"
            if [ "$n" -lt "$STABILISATION" ]; then
                etape "$g : $d req/s pour $actuel instance(s) → réduire à $voulu ? ($n/$STABILISATION : on attend)"
            else
                etape "$g : $d req/s pour $actuel instance(s) → RÉDUIRE d'une instance ($((actuel - 1)))"
                memoriser "$g" 0
                redimensionner "$g" "$((actuel - 1))"     # hors du DNS d'abord, éteinte ensuite
            fi
        else
            memoriser "$g" 0
            etape "$g : $d req/s pour $actuel instance(s) — rien à faire"
        fi
    done
}
memoriser() { console "f=$MEMOIRE; [ -s \$f ] || echo '{}' > \$f; jq '.\"$1\" = $2' \$f > \$f.n && mv \$f.n \$f"; }

initialiser
case ${1:-evaluer} in
    evaluer) evaluer ;;
    boucle)  while :; do evaluer; sleep 30; done ;;
    *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
