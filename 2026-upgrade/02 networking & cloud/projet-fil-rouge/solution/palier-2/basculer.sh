#!/usr/bin/env bash
# basculer.sh — perdre une région, et survivre. Depuis l'hôte.
#   sinistre   la région Europe « disparaît » : toutes ses machines sont gelées (docker pause) — plus
#              un paquet, plus une écriture ; exactement ce que voit le reste du monde
#   basculer   la base de Lomé est promue primaire, les résolveurs pointent db.marche.test vers elle
#   retablir   l'Europe revient : son ancienne primaire est d'abord ÉCARTÉE (reconstruite en réplique
#              de Lomé) — SEULEMENT ENSUITE la région est dégelée. Dans l'autre ordre : deux primaires.
#   revenir    retour planifié de la primaire en Europe (arrêt propre à Lomé : aucune perte)
#   etat       qui est primaire, qui suit qui
# Le choix de la région primaire est du CODE (variable Terraform region_primaire), rangé dans
# terraform/regions/bascule.auto.tfvars sur la console : un « deployer.sh » ultérieur ne rebascule
# pas en douce. (En équipe : ce fichier est commité — la bascule est une revue de code express.)
set -euo pipefail
export MSYS_NO_PATHCONV=1
debut=$(date +%s)
etape() { printf '[%3ss] %s\n' "$(( $(date +%s) - debut ))" "$*"; }
pg() { docker exec "$1" runuser -u postgres -- psql -d marche -tAc "$2"; }
europe() { docker ps -a --filter label=projet=marche --filter label=region=europe --format '{{.Names}}'; }
tf() {   # plan enregistré puis appliqué, comme d'habitude — y compris en pleine crise
    docker exec console sh -c "printf 'region_primaire = \"%s\"\n' $1 > /root/p2/terraform/regions/bascule.auto.tfvars"
    shift
    docker exec -w /root/p2/terraform/regions console terraform plan -no-color -input=false -out=bascule.bin "$@" \
        | grep -E 'must be replaced|Plan:|Error' || true
    docker exec -w /root/p2/terraform/regions console terraform apply -no-color -input=false bascule.bin | grep -E 'Apply|Error'
}
etat() {
    for b in db db-lome; do
        printf '  %-8s ' "$b"
        if [ "$(docker inspect -f '{{.State.Paused}}' "$b")" = true ]; then echo "gelée"; continue; fi
        case $(pg "$b" 'select pg_is_in_recovery()' 2>/dev/null) in
            f) echo "PRIMAIRE — réplique(s) : $(pg "$b" 'select client_addr||'"' '"'||state from pg_stat_replication' | tr '\n' ' ')" ;;
            t) echo "réplique — reçoit de : $(pg "$b" 'select sender_host||'"' '"'||status from pg_stat_wal_receiver')" ;;
            *) echo "injoignable" ;;
        esac
    done
    printf '  db.marche.test : Europe → %s, Lomé → %s\n' \
        "$(docker exec passerelle dig +short +time=2 +tries=1 @127.0.0.1 db.marche.test 2>/dev/null || echo '?')" \
        "$(docker exec passerelle-lome dig +short +time=2 +tries=1 @127.0.0.1 db.marche.test 2>/dev/null || echo '?')"
}

case ${1:-etat} in
sinistre)
    etape "la région Europe disparaît ($(europe | wc -l) machines gelées)"
    europe | xargs docker pause >/dev/null ;;
basculer)
    etape "promotion de db-lome (seules les machines de Lomé concernées : l'Europe est injoignable)"
    # -target : réservé aux urgences — ici, planifier les machines d'Europe n'a aucun sens
    tf lome -target='module.machine["db-lome"]' -target='module.machine["passerelle-lome"]'
    for _ in $(seq 60); do [ "$(pg db-lome 'select pg_is_in_recovery()' 2>/dev/null)" = f ] && break; sleep 1; done
    etape "db-lome : primaire=$( [ "$(pg db-lome 'select pg_is_in_recovery()')" = f ] && echo oui || echo NON)" ;;
retablir)
    etape "écarter l'ancienne primaire AVANT de dégeler (elle se croit toujours primaire)"
    tf lome                                    # remplace db et passerelle d'Europe, encore gelées
    etape "dégel du reste de la région"
    europe | while read -r m; do [ "$(docker inspect -f '{{.State.Paused}}' "$m")" = true ] && docker unpause "$m" >/dev/null; done
    # « streaming », pas seulement « connectée » : pendant la copie initiale, l'état est « backup »
    for _ in $(seq 180); do [ "$(pg db-lome "select count(*) from pg_stat_replication where state='streaming'" 2>/dev/null)" = 1 ] && break; sleep 1; done
    etape "l'Europe suit Lomé : $(pg db-lome "select coalesce(max(state),'AUCUNE RÉPLIQUE'), max(replay_lag) from pg_stat_replication" | tr '|' ' ')" ;;
revenir)
    # Une bascule PLANIFIÉE ne doit rien perdre. On le PROUVE avant de promouvoir : la réplique doit
    # avoir reçu jusqu'au point de contrôle d'arrêt de la primaire — sinon on annule (vécu : une
    # réplique silencieusement bloquée depuis 60 s, promue quand même → 129 commandes perdues).
    [ "$(pg db-lome "select count(*) from pg_stat_replication where state='streaming'")" = 1 ] \
        || { etape "ANNULÉ : l'Europe ne reçoit pas le flux de Lomé"; etat; exit 1; }
    etape "arrêt propre de la primaire de Lomé : elle envoie ses derniers WAL à la réplique avant de s'arrêter"
    docker exec db-lome systemctl stop postgresql@16-main
    arret=$(docker exec db-lome /usr/lib/postgresql/16/bin/pg_controldata -D /var/lib/postgresql/16/main \
            | awk -F': *' '/^Latest checkpoint location/ {print $2}')
    for _ in $(seq 20); do
        recu=$(pg db "select pg_wal_lsn_diff(pg_last_wal_receive_lsn(), '$arret') > 0")
        [ "$recu" = t ] && break; sleep 1
    done
    if [ "$recu" != t ]; then
        etape "ANNULÉ : la réplique n'a pas reçu le point d'arrêt $arret — la primaire de Lomé redémarre"
        docker exec db-lome systemctl start postgresql@16-main; etat; exit 1
    fi
    etape "la réplique a tout reçu (au-delà de $arret) : promotion en Europe"
    tf europe
    for _ in $(seq 180); do [ "$(pg db "select count(*) from pg_stat_replication where state='streaming'" 2>/dev/null)" = 1 ] && break; sleep 1; done
    etape "primaire de retour en Europe" ;;
etat) ;;
*) echo "usage : $0 sinistre|basculer|retablir|revenir|etat" >&2; exit 2 ;;
esac
etat
