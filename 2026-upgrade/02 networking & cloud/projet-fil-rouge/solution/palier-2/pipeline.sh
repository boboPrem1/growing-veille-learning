#!/usr/bin/env bash
# pipeline.sh — déployer une nouvelle version de Marché SANS INTERRUPTION (bleu/vert), région par
# région. Depuis l'hôte ; tout se passe sur la console, avec Terraform — comme le ferait un job de CI.
#
#   ./pipeline.sh deployer <version> [--approuve] [--defaillante] [--regions "europe lome"]
#   ./pipeline.sh retour <region>        remettre l'autre couleur en service (quelques secondes)
#   ./pipeline.sh retirer <region> [--approuve]   supprimer le groupe hors service (après analyse)
#   ./pipeline.sh etat
#
# Étapes, pour chaque région (l'Europe d'abord : moins de trafic, c'est la région « canari ») :
#   1. valider      terraform fmt -check, validate
#   2. planifier    la couleur INACTIVE reçoit la version et la taille de l'active ; plan ENREGISTRÉ
#   3. approuver    une personne relit le plan (--approuve : l'approbation est donnée d'avance)
#   4. appliquer    LE plan relu (terraform apply plan.bin) : les nouvelles instances démarrent
#   5. vérifier     santé + version + tests de fumée, instance par instance, AVANT tout trafic client
#   6. basculer     la découverte DNS publie la nouvelle couleur : le répartiteur change de groupe
#   7. observer     30 s de trafic réel depuis Lomé : erreurs et latence (l'objectif de service).
#                   Régression → RETOUR automatique à l'ancienne couleur, encore debout.
#   8. retirer      l'ancienne couleur passe à 0 instance
# --defaillante : la nouvelle version est « fonctionnelle mais lente » (+800 ms) — elle passe les
# tests de fumée, pas l'observation. C'est tout l'intérêt de garder l'ancienne couleur jusqu'au bout.
set -euo pipefail
export MSYS_NO_PATHCONV=1
# shellcheck source=lib-flotte.sh
. "$(dirname "$0")/lib-flotte.sh"
SLO_P95_MS=${SLO_P95_MS:-500}          # l'objectif : 95 % des requêtes en moins de 500 ms, 0 erreur

# observer <region> : 30 s de requêtes réelles vers le site de la région (depuis Lomé) ; vrai si l'objectif tient
observer() {
    local ip; ip=$([ "$1" = europe ] && echo 203.0.113.10 || echo 192.0.2.100)
    docker exec client bash -c "for i in \$(seq 60); do
            curl -s -o /dev/null -m 5 --resolve www.marche.test:443:$ip -w '%{http_code} %{time_total}\n' https://www.marche.test/api/products
            sleep 0.5; done" > /tmp/observation.txt
    local n err p95
    n=$(wc -l < /tmp/observation.txt)
    err=$(awk '$1 != 200' /tmp/observation.txt | wc -l)
    p95=$(awk '{print int($2 * 1000)}' /tmp/observation.txt | sort -n | awk '{v[NR] = $1} END {print v[int(NR * 0.95)]}')
    etape "   observation : $n requêtes, $err erreur(s), p95 = ${p95} ms (objectif : 0 erreur, < ${SLO_P95_MS} ms)"
    [ "$err" = 0 ] && [ "$p95" -lt "$SLO_P95_MS" ]
}

deployer() {
    local version=$1 approuve=$2 defaillante=$3 regions=$4 r a n c
    console "cp $FLOTTE $FLOTTE.avant; cp $ACTIVE $ACTIVE.avant"      # (pour annuler une demande refusée)
    etape "1. valider"
    console "cd $TF/regions && terraform fmt -check -recursive .. >/dev/null && terraform validate -no-color >/dev/null && cd ../plateforme && terraform validate -no-color >/dev/null && cd ../trafic && terraform validate -no-color >/dev/null" \
        || { echo "   code invalide ou mal formaté (terraform fmt / validate)"; exit 1; }
    for r in $regions; do
        a=$(active "$r"); n=$(autre "$a")
        etape "== région $r : $r-$a (version $(groupe "$r-$a" version)) → $r-$n (version $version)"
        etape "2-4. planifier, approuver, appliquer : le groupe $r-$n démarre"
        regler "$r-$n" version "\"$version\""; regler "$r-$n" taille "$(groupe "$r-$a" taille)"
        couche regions "$approuve" "\[\"app-$r-$n-[0-9]+\"\]"
        etape "5. vérifier les nouvelles instances (avant tout trafic client)"
        for c in $(instances "$r-$n"); do
            for _ in $(seq 60); do
                docker exec "$c" curl -s -m 2 localhost:8000/healthz 2>/dev/null | grep -q "\"version\":\"$version\"" && break; sleep 2
            done
            [ "$defaillante" = oui ] && docker exec "$c" curl -s -o /dev/null -X POST localhost:8000/admin/chaos \
                -H 'content-type: application/json' -d '{"latency_ms": 800}'
            case $(docker exec "$c" curl -s -o /dev/null -m 10 -w '%{http_code}' -X POST localhost:8000/api/orders \
                   -H 'content-type: application/json' -d '{"product_id":1,"quantity":1,"payment_method":"card"}') in
                201|402) etape "   $c : version $version, commande de test OK" ;;
                *) etape "   $c : ÉCHEC du test de fumée — on s'arrête là (aucun client n'a vu cette version)"
                   regler "$r-$n" taille 0; couche regions approuve "\[\"app-$r-$n-[0-9]+\"\]"; exit 1 ;;
            esac
        done
        etape "6. basculer : le répartiteur de $r passe au groupe $n"
        activer "$r" "$n"; couche trafic approuve "$(motif_publication "$r")"
        sleep 8                                   # TTL 5 s + « hold » du répartiteur
        etape "7. observer"
        if ! observer "$r"; then
            etape "   RÉGRESSION : retour au groupe $a (toujours debout)"
            activer "$r" "$a"; couche trafic approuve "$(motif_publication "$r")"; sleep 8
            observer "$r" || true
            etape "   la version $version reste déployée mais HORS service dans $r-$n : à analyser, puis retirer"
            exit 1
        fi
        etape "8. retirer l'ancien groupe $r-$a"
        regler "$r-$a" taille 0; couche regions approuve "\[\"app-$r-$a-[0-9]+\"\]"
    done
    etape "version $version en service dans : $regions"
}

initialiser
case ${1:-etat} in
    deployer)
        v=${2:?version ?}; shift 2; ap=""; def=non; reg="europe lome"
        while [ $# -gt 0 ]; do case $1 in
            --approuve) ap=approuve ;; --defaillante) def=oui ;; --regions) reg=$2; shift ;;
            *) echo "option inconnue : $1" >&2; exit 2 ;; esac; shift; done
        deployer "$v" "$ap" "$def" "$reg" ;;
    retour)
        r=${2:?région ?}; a=$(active "$r"); n=$(autre "$a")
        [ "$(groupe "$r-$n" taille)" -gt 0 ] || { echo "le groupe $r-$n n'a aucune instance : rien vers quoi revenir" >&2; exit 1; }
        etape "retour : $r-$a → $r-$n"; activer "$r" "$n"; couche trafic approuve "$(motif_publication "$r")" ;;
    retirer)
        r=${2:?région ?}; n=$(autre "$(active "$r")")
        etape "retrait du groupe HORS service $r-$n (version $(groupe "$r-$n" version))"
        regler "$r-$n" taille 0; couche regions "${3:+approuve}" "\[\"app-$r-$n-[0-9]+\"\]" ;;
    etat) ;;
    *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
for r in europe lome; do
    a=$(active "$r")
    printf '  %-6s en service : %-11s version %-8s %s instance(s) | %s-%s : %s instance(s), version %s\n' "$r" "$r-$a" \
        "$(groupe "$r-$a" version)" "$(groupe "$r-$a" taille)" "$r" "$(autre "$a")" "$(groupe "$r-$(autre "$a")" taille)" "$(groupe "$r-$(autre "$a")" version)"
done
