#!/usr/bin/env bash
# capacite.sh — trouver le COUDE : la charge au-delà de laquelle Marché ne sert plus davantage, il fait
# seulement attendre. Des paliers de commandes/s, lancés depuis le client de Lomé (TogoNet) vers
# https://www.marche.test, chacun pendant DUREE secondes : pour chacun, ce qui a été servi, le p50, le
# p95 et les échecs.
#   ./capacite.sh [paliers…]        (défaut : 5 10 15 20 25 30 ; DUREE=30 par défaut)
# La loi de Little dit où chercher : débit max = connexions disponibles ÷ durée d'une commande.
set -euo pipefail
export MSYS_NO_PATHCONV=1
DUREE=${DUREE:-30}
paliers=${*:-5 10 15 20 25 30}
printf '%-12s %-10s %-8s %-8s %s\n' "demandées/s" "servies/s" "p50 (s)" "p95 (s)" "échecs"
for r in $paliers; do
    # (le script de mesure part sur l'entrée standard : aucun guillemet à échapper)
    docker exec -i -e R="$r" -e D="$DUREE" client bash -s <<'EOF'
rm -f /tmp/cap.txt
for s in $(seq "$D"); do
    for i in $(seq "$R"); do
        curl -s -o /dev/null -m 15 -w '%{http_code} %{time_total}\n' -H 'content-type: application/json' \
             -d '{"product_id":1,"quantity":1,"payment_method":"card"}' https://www.marche.test/api/orders >> /tmp/cap.txt &
        sleep "$(awk -v r="$R" 'BEGIN {print 1 / r}')"
    done
done
wait
# 201 (commande) ou 402 (paiement refusé : une réponse métier) : servies ; tout le reste : échecs
ok=$(grep -cE '^(201|402) ' /tmp/cap.txt || true); ko=$(grep -vcE '^(201|402) ' /tmp/cap.txt || true)
grep -E '^(201|402) ' /tmp/cap.txt | cut -d' ' -f2 | sort -n > /tmp/cap-t.txt
p() { awk -v q="$1" '{v[NR] = $1} END {i = int(NR * q); if (i < 1) i = 1; printf "%.2f", v[i]}' /tmp/cap-t.txt; }
printf '%-12s %-10s %-8s %-8s %s\n' "$R" "$(awk -v o="$ok" -v d="$D" 'BEGIN {printf "%.1f", o / d}')" "$(p 0.5)" "$(p 0.95)" "$ko"
EOF
    sleep 10   # (laisser la file se vider entre deux paliers)
done
