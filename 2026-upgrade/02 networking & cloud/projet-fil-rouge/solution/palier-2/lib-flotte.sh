#!/usr/bin/env bash
# lib-flotte.sh — ce que partagent pipeline.sh (déploiements) et autoscaler.sh (charge) : l'état
# VOULU de la flotte (deux fichiers de variables Terraform sur la console) et la façon de l'appliquer
# (plan enregistré → politique → approbation → apply de ce plan). Sourcé, pas exécuté.
TF=/root/p2/terraform
FLOTTE=$TF/regions/flotte.auto.tfvars.json
ACTIVE=$TF/trafic/flotte.auto.tfvars.json
debut=$(date +%s)
etape() { printf '[%3ss] %s\n' "$(( $(date +%s) - debut ))" "$*"; }
console() { docker exec console bash -c "$*"; }

# l'état voulu est dans deux fichiers de variables (créés avec les valeurs par défaut au premier usage)
initialiser() {
    console "[ -s $FLOTTE ] || echo '{\"groupes\":{\"europe-bleu\":{\"taille\":2,\"version\":\"1.0.0\"},\"europe-vert\":{\"taille\":0,\"version\":\"1.0.0\"},\"lome-bleu\":{\"taille\":2,\"version\":\"1.0.0\"},\"lome-vert\":{\"taille\":0,\"version\":\"1.0.0\"}}}' > $FLOTTE
             [ -s $ACTIVE ] || echo '{\"couleur_active\":{\"europe\":\"bleu\",\"lome\":\"bleu\"}}' > $ACTIVE"
}
active()  { console "jq -r '.couleur_active.$1' $ACTIVE"; }
autre()   { [ "$1" = bleu ] && echo vert || echo bleu; }
groupe()  { console "jq -r '.groupes[\"$1\"].$2' $FLOTTE"; }                  # groupe <nom> taille|version
regler()  { console "jq '.groupes[\"$1\"].$2 = $3' $FLOTTE > $FLOTTE.n && mv $FLOTTE.n $FLOTTE"; }
activer() { console "jq '.couleur_active.$1 = \"$2\"' $ACTIVE > $ACTIVE.n && mv $ACTIVE.n $ACTIVE"; }
instances() { docker ps --filter label=projet=marche --filter label=role=app --filter "label=groupe=$1" --format '{{.Names}}' | sort; }

# couche <nom> [approuve] [<motif>] : plan enregistré → politique → (approbation) → apply DE CE PLAN.
# La politique : chaque ressource touchée par le plan doit correspondre au <motif> de l'étape. Un
# déploiement ne crée que les instances de SON groupe ; s'il veut remplacer une base ou une passerelle,
# c'est qu'autre chose a changé (du code non relu, une dérive) — refus, même approuvé d'avance.
# (Vécu : un retrait « de 8 ressources » a remplacé les 23 machines, parce que le code avait changé.)
couche() {
    console "cd $TF/$1 && terraform plan -input=false -no-color -out=pipeline.bin > /tmp/pipeline-$1.log 2>&1" \
        || { console "tail -20 /tmp/pipeline-$1.log"; exit 1; }
    console "grep -E '^  # .* (will be|must be)|^Plan:|No changes' /tmp/pipeline-$1.log" | sed 's/^/        /'
    if [ -n "${3:-}" ]; then
        hors=$(console "grep -E '^  # .* (will be|must be)' /tmp/pipeline-$1.log | awk '{print \$2}'" | grep -vE "$3" || true)
        if [ -n "$hors" ]; then
            echo "        ✘ POLITIQUE : ce plan touche des ressources hors du périmètre de l'étape — refusé :"
            echo "$hors" | sed 's/^/            /'
            # l'état voulu revient à ce qu'il était : la demande refusée n'est pas « fusionnée »
            console "for f in $FLOTTE $ACTIVE; do [ -f \$f.avant ] && cp \$f.avant \$f; done"
            exit 4
        fi
    fi
    if [ "${2:-}" != approuve ]; then
        echo "        → plan enregistré, NON appliqué. Relisez-le (console : $TF/$1, /tmp/pipeline-$1.log), puis relancez avec --approuve."
        exit 3
    fi
    # (trafic : une écriture à la fois — PowerDNS/SQLite n'accepte qu'un écrivain ; pipefail : un apply
    #  en échec doit arrêter le pipeline, pas être masqué par le grep)
    console "set -o pipefail; cd $TF/$1 && terraform apply -input=false -no-color $([ "$1" = trafic ] && echo -parallelism=1) pipeline.bin | grep -E '^Apply'" | sed 's/^/        /'
}

# redimensionner <groupe> <taille> : retirer du DNS ce qui va disparaître, attendre, éteindre, oublier
redimensionner() {
    local g=$1 t=$2 r=${1%%-*} actuel victimes i
    actuel=$(groupe "$g" taille)
    victimes=$(for i in $(seq $((t + 1)) "$actuel"); do printf '"app-%s-%s",' "$g" "$i"; done); victimes=${victimes%,}
    if [ -n "$victimes" ]; then
        console "jq '.retrait = [$victimes]' $ACTIVE > $ACTIVE.n && mv $ACTIVE.n $ACTIVE"
        couche trafic approuve "$(motif_publication "$r")"
        sleep 15                                  # TTL 5 s + « hold » 5 s + requêtes en cours
    fi
    regler "$g" taille "$t"
    couche regions approuve "\[\"app-$g-[0-9]+\"\]"
    console "jq '.retrait = []' $ACTIVE > $ACTIVE.n && mv $ACTIVE.n $ACTIVE"
    couche trafic approuve "$(motif_publication "$r")"
}

# motif_publication <région> : ce qu'un changement de publication a le droit de toucher — le nom de la
# région, sur les DEUX serveurs DNS (les deux font autorité pour la zone : même contenu)
motif_publication() { printf '^powerdns_record\.apps_(europe|lome)\["%s"\]$' "$1"; }
