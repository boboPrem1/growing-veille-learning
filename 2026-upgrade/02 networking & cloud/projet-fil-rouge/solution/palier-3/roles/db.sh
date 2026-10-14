#!/bin/bash
# db — PostgreSQL. MODE=primaire : la base de production (Europe). MODE=replique : une copie en
# lecture seule, alimentée en continu par la réplication en flux (asynchrone) depuis la primaire.
# Aucun mot de passe d'application ici : OpenBao crée des identifiants TEMPORAIRES, avec le rôle
# « bao » (qui n'a le droit que de créer des rôles membres de « marche »).
# shellcheck source=commun.sh
. /lab/roles/commun.sh
vlan "$VLAN" "$ADRESSE4" "$GW" "$ADRESSE6"; reseau_pret "baie.$VLAN" "$ADRESSE4"; resolveur "$GW"

v=$(ls /etc/postgresql); d=/var/lib/postgresql/$v/main; c=/etc/postgresql/$v/main
cat > "$c/conf.d/marche.conf" <<'EOF'
# '*' : pg_hba et le pare-feu filtrent (une adresse IPv6 explicite est « tentative » au démarrage)
listen_addresses = '*'
password_encryption = 'scram-sha-256'
wal_level = replica
max_wal_senders = 10
hot_standby = on
# un pair qui DISPARAÎT (région perdue, passerelle remplacée) ne dit rien : sans ces bornes, une
# connexion morte reste « établie » pendant des minutes (côté serveur : les walsenders)
tcp_keepalives_idle = 5
tcp_keepalives_interval = 2
tcp_keepalives_count = 3
tcp_user_timeout = 10000
EOF
{
    sed '/# --- marche ---/,$d' "$c/pg_hba.conf"
    echo "# --- marche ---"
    # Palier 3 : TLS pour tous, et un certificat pour les applications ; sans TLS, refusé
    for r in $CLIENTS_HBA; do echo "hostssl  marche       all          $r  scram-sha-256  clientcert=verify-ca"; done
    for r in ${COFFRE_HBA:-}; do echo "hostssl  marche       all          $r  scram-sha-256"; done
    for r in ${REPLIQUES:-}; do echo "hostssl  replication  replicateur  $r/32  scram-sha-256"; done
    echo "hostnossl  all  all  0.0.0.0/0  reject"
    echo "hostnossl  all  all  ::/0       reject"
} > "$c/pg_hba.conf.nouveau" && mv "$c/pg_hba.conf.nouveau" "$c/pg_hba.conf"

# archivage CONTINU des WAL vers les sauvegardes : on peut restaurer à n'importe quelle seconde (PITR).
# Écrit AVANT le démarrage (archive_mode exige un redémarrage : en le changeant après, la base
# redémarrait une 2de fois — et une réplique en pleine copie échouait). Une réplique ne l'applique
# pas ; promue primaire, elle se met à archiver sans redémarrer.
if [ "$MODE" = primaire ]; then
    cat > "$c/conf.d/archivage.conf" <<'EOF'
archive_mode = on
archive_command = 'pgbackrest --stanza=marche archive-push %p'
# au moins un segment WAL par minute, même sans trafic : on perd au pire 1 min de données (RPO)
archive_timeout = 60
EOF
else
    rm -f "$c/conf.d/archivage.conf"
fi

if [ "$MODE" = replique ] && [ ! -f "$d/standby.signal" ]; then
    # première fois : copie complète de la primaire, puis réplication en flux (-R : standby.signal
    # et primary_conninfo ; -S : un slot, pour que la primaire garde les WAL tant qu'on ne les a pas)
    systemctl stop postgresql
    # primaire injoignable : on NE TOUCHE PAS aux données (ce sont peut-être les seules qui restent)
    prete=non
    for _ in $(seq 300); do pg_isready -q -h "$PRIMAIRE" && { prete=oui; break; }; sleep 2; done
    [ "$prete" = oui ] || { echo "primaire $PRIMAIRE injoignable : données conservées, rien n'est fait" >&2; exit 1; }
    rm -rf "$d"
    # -c fast : sans lui, pg_basebackup attend un checkpoint « étalé » de la primaire (des minutes)
    # -d : les mêmes bornes TCP côté client — pour la copie (sinon, bloquée pour toujours sur une
    # connexion morte : vécu) ET pour la réplication ensuite (-R les recopie dans primary_conninfo)
    # plusieurs essais : la primaire peut redémarrer pendant la copie (elle aussi vient d'être
    # remplacée) ; un échec laisse un répertoire vide (pg_basebackup nettoie), on recommence
    for essai in 1 2 3 4 5; do
        PGPASSWORD=$REPL_MDP runuser -u postgres -- pg_basebackup -D "$d" -R -X stream -S "$SLOT" -c fast \
            -d "host=$PRIMAIRE user=replicateur connect_timeout=5 keepalives_idle=5 keepalives_interval=2 keepalives_count=3 tcp_user_timeout=10000" \
            && break
        [ "$essai" = 5 ] && exit 1
        sleep 10
    done
fi
systemctl enable -q postgresql && systemctl restart postgresql
for _ in $(seq 30); do runuser -u postgres -- pg_isready -q && break; sleep 1; done

# BASCULE DE RÉGION : une réplique dont le mode devient « primaire » est PROMUE (elle cesse de suivre
# l'ancienne primaire et accepte les écritures, sur une nouvelle timeline). Ses données sont celles
# qu'elle avait reçues : ce qui n'était pas encore arrivé est perdu (le RPO de la réplication asynchrone).
if [ "$MODE" = primaire ] && [ -f "$d/standby.signal" ]; then
    runuser -u postgres -- psql -qtAc "select pg_promote(wait => true)" >/dev/null
    for p in primary_conninfo primary_slot_name; do runuser -u postgres -- psql -qtAc "alter system reset $p"; done
    echo "réplique promue primaire"
fi

if [ "$MODE" = primaire ]; then
    q() { runuser -u postgres -- psql -qtAc "$1"; }
    [ "$(q "select 1 from pg_roles where rolname='marche'")" = 1 ] || q "create role marche nologin"
    [ "$(q "select 1 from pg_database where datname='marche'")" = 1 ] || runuser -u postgres -- createdb -O marche marche
    [ "$(q "select 1 from pg_roles where rolname='bao'")" = 1 ] || q "create role bao login createrole"
    q "alter role bao password '$BAO_MDP'"
    q "grant marche to bao with admin option"
    [ "$(q "select 1 from pg_roles where rolname='replicateur'")" = 1 ] || q "create role replicateur login replication"
    q "alter role replicateur password '$REPL_MDP'"
    for s in ${SLOTS:-}; do
        [ "$(q "select 1 from pg_replication_slots where slot_name='$s'")" = 1 ] || q "select pg_create_physical_replication_slot('$s')" >/dev/null
    done
fi

if [ "$MODE" = primaire ]; then
    # ---------------------------------------------------------------- sauvegardes (pgBackRest → S3)
    # (l'archivage est configuré plus haut, avant le démarrage — voir archivage.conf)
    # (l'agent lui-même est configuré plus bas, dans les deux modes : ici, seulement SES modèles)
    install -d -m 700 /etc/bao-agent
    cat > /etc/bao-agent/sauvegardes.hcl <<'EOF'
template {
  destination = "/etc/pgbackrest.conf"
  perms       = "0640"
  # --no-block : la première sauvegarde complète dure ; l'agent, lui, n'attend pas une commande plus de 30 s
  command     = "chgrp postgres /etc/pgbackrest.conf && systemctl start --no-block pgbackrest-init"
  contents    = <<TPL
{{ with secret "kv/data/marche/pgbackrest" -}}
[global]
repo1-type=s3
repo1-s3-endpoint=s3.fournisseur.test
repo1-s3-bucket=marche-sauvegardes
repo1-s3-region=us-east-1
repo1-s3-uri-style=path
repo1-s3-key={{ .Data.data.access_key }}
repo1-s3-key-secret={{ .Data.data.secret_key }}
repo1-path=/marche
# chiffrées AVANT de partir : le fournisseur ne stocke que du bruit
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass={{ .Data.data.chiffrement }}
repo1-retention-full=2
start-fast=y
log-level-console=warn
{{- end }}

[marche]
pg1-path=/var/lib/postgresql/16/main
TPL
}
EOF
    # Une sauvegarde COMPLÈTE sur la timeline courante. Après une promotion (bascule de région) ou une
    # restauration, la base change de timeline : sans nouvelle complète, restaurer « maintenant »
    # repartirait de la dernière complète de l'ANCIENNE timeline et rejouerait des heures de WAL à
    # travers chaque bascule (vécu : une restauration d'essai qui ne finissait pas).
    cat > /usr/local/sbin/sauvegarde-timeline <<'EOF'
#!/bin/sh
set -e
tl=$(psql -tAc "select lpad(upper(to_hex(timeline_id)), 8, '0') from pg_control_checkpoint()")
if pgbackrest --stanza=marche info --output=json \
   | jq -e --arg tl "$tl" '[.[0].backup[] | select(.type == "full") | .archive.start[0:8]] | index($tl) != null' >/dev/null; then
    echo "une sauvegarde complète existe déjà sur la timeline $tl"
else
    echo "timeline $tl sans sauvegarde complète : on en fait une"
    pgbackrest --stanza=marche --type=full backup
fi
EOF
    chmod 755 /usr/local/sbin/sauvegarde-timeline
    # une fois la configuration écrite : créer le « stanza » (idempotent), vérifier, sauvegarder si besoin
    cat > /etc/systemd/system/pgbackrest-init.service <<'EOF'
[Unit]
Description=pgBackRest — initialisation du dépôt et sauvegarde complète de la timeline
[Service]
Type=oneshot
User=postgres
ExecStart=/usr/bin/pgbackrest --stanza=marche stanza-create
ExecStart=/usr/bin/pgbackrest --stanza=marche check
ExecStart=/usr/local/sbin/sauvegarde-timeline
EOF
    for t in full:daily diff:hourly; do
        cat > "/etc/systemd/system/pgbackrest-${t%%:*}.service" <<EOF
[Unit]
Description=pgBackRest — sauvegarde ${t%%:*}
[Service]
Type=oneshot
User=postgres
ExecStart=/usr/bin/pgbackrest --stanza=marche --type=${t%%:*} backup
EOF
        cat > "/etc/systemd/system/pgbackrest-${t%%:*}.timer" <<EOF
[Unit]
Description=pgBackRest — sauvegarde ${t%%:*} (${t#*:})
[Timer]
OnCalendar=${t#*:}
Persistent=true
[Install]
WantedBy=timers.target
EOF
    done
    systemctl daemon-reload
    systemctl enable -q --now pgbackrest-full.timer pgbackrest-diff.timer
fi

# ---------------------------------------------------------------- Zero Trust (Palier 3) : TLS obligatoire
# La base présente SON identité (db.marche.test, signée par l'AC des services) ; elle EXIGE TLS de tout
# le monde (hostnossl … reject), et des applications un certificat (clientcert=verify-ca), EN PLUS de
# leur identifiant temporaire : deux preuves, l'une de l'instance, l'autre de son droit du moment.
cat > /usr/local/sbin/db-identite <<'EOF'
#!/bin/sh
# lancé à chaque identité reçue (ou renouvelée) : la base la présente, et recharge sans couper
c=$(ls -d /etc/postgresql/*/main)
printf "ssl = on\nssl_cert_file = '/etc/identite/service.crt'\nssl_key_file = '/etc/identite/service.key'\nssl_ca_file = '/etc/identite/ca.pem'\nssl_min_protocol_version = 'TLSv1.2'\n" > "$c/conf.d/identite.conf"
systemctl reload postgresql@16-main
EOF
chmod 755 /usr/local/sbin/db-identite
[ "$MODE" = primaire ] || rm -f /etc/bao-agent/sauvegardes.hcl
identite db db.marche.test postgres /usr/local/sbin/db-identite
agent_openbao db

# ---------------------------------------------------------------- métriques pour la supervision
# Pas d'exporteur PostgreSQL dans l'image : le node exporter publie ce qu'un script écrit dans son
# répertoire « textfile » — la technique pour exposer n'importe quelle mesure maison.
install -d -o postgres /var/lib/prometheus/node-exporter
cat > /usr/local/sbin/metriques-pg <<'EOF'
#!/bin/sh
# une ligne SQL → des métriques Prometheus (écrites dans un fichier temporaire, puis renommées :
# le node exporter ne lit jamais un fichier à moitié écrit)
f=/var/lib/prometheus/node-exporter/marche.prom
psql -XqtA -F' ' -c "
  select 'marche_pg_primaire', case when pg_is_in_recovery() then 0 else 1 end
  union all select 'marche_replication_repliques', (select count(*) from pg_stat_replication where state = 'streaming')
  union all select 'marche_replication_retard_secondes', coalesce((select extract(epoch from max(replay_lag)) from pg_stat_replication), 0)
  union all select 'marche_archivage_age_secondes', coalesce((select extract(epoch from now() - last_archived_time) from pg_stat_archiver), 0)
  union all select 'marche_archivage_en_attente', (select count(*) from pg_ls_archive_statusdir() where name like '%.ready')
  union all select 'marche_archivage_echec', (select case when last_failed_time > coalesce(last_archived_time, 'epoch') then 1 else 0 end from pg_stat_archiver)
  union all select 'marche_slot_wal_retenu_octets', coalesce((select max(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_receive_lsn() else pg_current_wal_lsn() end, restart_lsn)) from pg_replication_slots), 0)
" > "$f.tmp" && mv "$f.tmp" "$f"
EOF
chmod 755 /usr/local/sbin/metriques-pg
printf '[Unit]\nDescription=Métriques PostgreSQL pour la supervision\n[Service]\nType=oneshot\nUser=postgres\nExecStart=/usr/local/sbin/metriques-pg\n' > /etc/systemd/system/metriques-pg.service
printf '[Unit]\nDescription=Métriques PostgreSQL toutes les 15 s\n[Timer]\nOnBootSec=10\nOnUnitActiveSec=15\nAccuracySec=1\n[Install]\nWantedBy=timers.target\n' > /etc/systemd/system/metriques-pg.timer
systemctl daemon-reload
systemctl enable -q --now prometheus-node-exporter metriques-pg.timer

regles="        ip saddr ${ADMIN} tcp dport 22 accept
        ip saddr ${SUPERVISION:-127.0.0.1} tcp dport 9100 accept"
for r in $CLIENTS_HBA ${COFFRE_HBA:-} ${REPLIQUES:-}; do          # (le coffre aussi : il crée les comptes)
    case $r in *:*) regles+=$'\n'"        ip6 saddr $r tcp dport 5432 accept" ;;
               *)   regles+=$'\n'"        ip saddr $r tcp dport 5432 accept" ;; esac
done
pare_feu "$regles"
cle_admin
echo "db ($MODE) prête"
