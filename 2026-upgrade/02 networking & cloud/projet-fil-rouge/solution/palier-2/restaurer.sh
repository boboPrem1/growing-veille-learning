#!/usr/bin/env bash
# restaurer.sh — la procédure de restauration À UN INSTANT (PITR) de la base « marche », depuis l'hôte.
#   ./solution/palier-2/restaurer.sh '2026-09-30 11:00:43+00'
# L'ordre compte ; chaque étape répare une conséquence de la précédente :
#   1. arrêter les applications (sinon elles écrivent pendant la restauration)
#   2. restaurer la primaire : sauvegarde complète + WAL rejoués JUSQU'À l'instant, puis promotion
#      (nouvelle « timeline » : l'historique d'après l'accident est abandonné)
#   3. recréer le slot de réplication (une restauration ne ramène pas les slots)
#   4. reconstruire la réplique : elle a suivi l'accident en direct (une réplique n'est PAS une sauvegarde)
#      et ne peut pas rejoindre la nouvelle timeline par elle-même
#   5. révoquer TOUS les identifiants dynamiques : la base restaurée et le coffre ne sont plus
#      d'accord (comptes créés après l'instant : disparus ; comptes supprimés après : revenus !)
#   6. relancer les agents : ils redemandent des identifiants, et redémarrent les applications
set -euo pipefail
export MSYS_NO_PATHCONV=1
INSTANT=${1:?usage : $0 'AAAA-MM-JJ HH:MM:SS+00'}
# les instances d'application du moment (leur nombre varie : groupes, bleu/vert, autoscaler)
APPS=$(docker ps --filter label=projet=marche --filter label=role=app --format '{{.Names}}' | sort | paste -sd' ')
debut=$(date +%s)
etape() { printf '[%3ss] %s\n' "$(( $(date +%s) - debut ))" "$*"; }
pg() { docker exec "$1" runuser -u postgres -- psql -d marche -tAc "$2"; }

etape "1. arrêt des applications"
for a in $APPS; do docker exec "$a" systemctl stop marche.target bao-agent; done

etape "2. restauration de db à « $INSTANT »"
docker exec db systemctl stop postgresql@16-main        # « postgresql » n'est qu'une coquille : l'arrêter n'arrête rien
docker exec db runuser -u postgres -- pgbackrest --stanza=marche --delta \
    --type=time "--target=$INSTANT" --target-action=promote restore
docker exec db systemctl start postgresql@16-main
for _ in $(seq 120); do [ "$(pg db 'select pg_is_in_recovery()' 2>/dev/null)" = f ] && break; sleep 1; done
[ "$(pg db 'select pg_is_in_recovery()')" = f ] || { echo "db n'a pas été promue" >&2; exit 1; }
etape "   promue — timeline $(pg db 'select timeline_id from pg_control_checkpoint()'), $(pg db 'select count(*) from orders') commandes"
# pgBackRest a écrit la cible dans postgresql.auto.conf, et elle y RESTE. pg_basebackup la recopierait
# sur la réplique… qui « atteindrait la cible » à son tour et se promouvrait : deux primaires (vécu).
for p in recovery_target_time recovery_target_action restore_command; do pg db "alter system reset $p" >/dev/null; done

etape "3. slots de réplication (le rôle db les recrée)"
docker exec db bash /lab/init.sh

etape "4. reconstruction de la réplique db-lome"
docker exec db-lome systemctl stop postgresql@16-main
docker exec db-lome rm -f /var/lib/postgresql/16/main/standby.signal   # → le rôle refait un pg_basebackup
docker exec db-lome bash /lab/init.sh

etape "5. révocation de tous les identifiants dynamiques"
docker exec console bash -c 'export BAO_ADDR=https://10.0.3.30:8200 BAO_CACERT=/root/pki/racine.crt \
    BAO_TLS_SERVER_NAME=coffre.marche.test BAO_TOKEN=$(jq -r .root_token /root/cles/bao-init.json)
    bao lease revoke -prefix base/creds/app'

etape "6. redémarrage des agents (nouveaux identifiants → applications)"
for a in $APPS; do docker exec "$a" systemctl start bao-agent; done
for _ in $(seq 60); do
    ok=0
    n_apps=$(echo $APPS | wc -w)
    for a in $APPS; do       # une vraie commande (201, ou 402 : paiement refusé — la base a répondu)
        case $(docker exec "$a" curl -s -o /dev/null -w '%{http_code}' -m 5 -X POST localhost:8000/api/orders \
               -H 'content-type: application/json' -d '{"product_id":1,"quantity":1,"payment_method":"card"}') in
            201|402) ok=$((ok+1)) ;;
        esac
    done
    [ "$ok" = "$n_apps" ] && break; sleep 1
done
for _ in $(seq 30); do [ -n "$(pg db "select state from pg_stat_replication")" ] && break; sleep 1; done
etape "terminé — applications prêtes : $ok/$(echo $APPS | wc -w) ; réplication : $(pg db "select state from pg_stat_replication" | tr '\n' ' ')"
