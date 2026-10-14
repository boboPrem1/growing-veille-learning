#!/bin/bash
# verifier.sh — correcteur automatique du projet fil rouge Linux, à lancer EN ROOT sur la machine.
#
#   sudo ./verifier.sh 1 [--reponses /chemin/REPONSES.txt]     Palier 1 (web1)
#   sudo ./verifier.sh 2 [--reponses /chemin/REPONSES.txt]     Palier 2 (web1) — revérifie aussi le Palier 1
#
# Chaque ligne est un critère vérifiable. Un palier est validé quand tout est vert.
# Au Palier 2, les critères du Palier 1 sont adaptés à la nouvelle organisation (code dans
# /opt/marche/current, unités marche@…, HTTPS, nftables et timers à la place d'ufw et cron).
# Pour le Palier 3 (plusieurs machines), voir verifier-infra.sh, lancé depuis le poste de contrôle.
#
# Attention : certains critères AGISSENT pour vérifier (tuer un service, lancer une sauvegarde,
# tenter un déploiement cassé…). Lancez le correcteur sur votre lab, pas sur une production.
set -uo pipefail

PALIER=${1:?usage : $0 1|2 [--reponses FICHIER]}
REPONSES=""
[[ "${2:-}" == --reponses ]] && REPONSES=${3:-}
[ "$(id -u)" -eq 0 ] || { echo "À lancer en root (sudo)." >&2; exit 2; }

OK=0; KO=0
vert()  { printf '  \033[32m✔\033[0m %s\n' "$1"; OK=$((OK + 1)); }
rouge() { printf '  \033[31m✘\033[0m %s\033[2m%s\033[0m\n' "$1" "${2:+  → $2}"; KO=$((KO + 1)); }
info()  { printf '  \033[33m•\033[0m %s\n' "$1"; }         # non compté
critere() {   # critere "libellé" "indice si échec" commande...
    local libelle=$1 indice=$2; shift 2
    if "$@" >/dev/null 2>&1; then vert "$libelle"; else rouge "$libelle" "$indice"; fi
}
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
mode()   { stat -c '%U:%G %a' "$1" 2>/dev/null; }
admin_perso() {   # le premier membre du groupe sudo autre que « ubuntu »
    local u; for u in $(getent group sudo | cut -d: -f4 | tr ',' ' '); do
        [[ $u == ubuntu ]] || { echo "$u"; return; }
    done
}

# Ce qui change légitimement d'un palier à l'autre
if [ "$PALIER" -ge 2 ]; then
    CODE=/opt/marche/current
    UNITES=(marche@gateway marche@orders marche@payments marche-loadgen)
    U_ORDERS=marche@orders; U_PAYMENTS=marche@payments
    WEB=https://127.0.0.1; CURL=(curl --cacert /etc/ssl/certs/marche.crt)
else
    CODE=/opt/marche/app
    UNITES=(marche-gateway marche-orders marche-payments marche-loadgen)
    U_ORDERS=marche-orders; U_PAYMENTS=marche-payments
    WEB=http://127.0.0.1; CURL=(curl)
fi
code_http() { "${CURL[@]}" -s -o /dev/null -w '%{http_code}' -m 10 "$1"; }

# ------------------------------------------------------------------------------------ Palier 1
palier1() {
    section "Palier 1 — Identité et accès"
    critere "Nom de machine : web1" "hostnamectl set-hostname" test "$(hostname)" = web1
    critere "Fuseau horaire : Africa/Lome" "timedatectl set-timezone" \
        test "$(timedatectl show -p Timezone --value)" = Africa/Lome

    local u; u=$(admin_perso)
    if [ -z "$u" ]; then
        rouge "Un compte d'administration personnel dans le groupe sudo" "useradd + usermod -aG sudo"
    else
        vert "Compte d'administration personnel : $u"
        local h; h=$(getent passwd "$u" | cut -d: -f6)
        critere "$u : clé SSH dans authorized_keys" "ssh-copy-id, ou install -m 600" test -s "$h/.ssh/authorized_keys"
        critere "$u : ~/.ssh en 700 et authorized_keys en 600, à lui" "SSH ignore silencieusement des permissions trop larges" \
            bash -c "[[ \$(stat -c '%U %a' '$h/.ssh') == '$u 700' && \$(stat -c '%U %a' '$h/.ssh/authorized_keys') == '$u 600' ]]"
        critere "$u : un mot de passe est défini (nécessaire pour sudo)" "passwd $u" \
            bash -c "[[ \$(passwd -S '$u' | awk '{print \$2}') == P ]]"
    fi
    critere "SSH : connexion root interdite (config effective)" "fichier dans /etc/ssh/sshd_config.d/ + sshd -t" \
        bash -c "sshd -T | grep -qx 'permitrootlogin no'"
    critere "SSH : mot de passe refusé (config effective)" "PasswordAuthentication ET KbdInteractiveAuthentication" \
        bash -c "sshd -T | grep -qx 'passwordauthentication no' && sshd -T | grep -qx 'kbdinteractiveauthentication no'"

    critere "La machine joint les dépôts Ubuntu (DNS, /etc/hosts, réseau)" "getent hosts archive.ubuntu.com ; cat /etc/hosts" \
        curl -fsS -m 10 -o /dev/null http://archive.ubuntu.com/ubuntu/dists/noble/Release

    section "Palier 1 — Comptes et permissions"
    critere "Groupe devs avec awa et koffi" "groupadd, usermod -aG" \
        bash -c "id -nG awa | grep -qw devs && id -nG koffi | grep -qw devs"
    critere "Compte de service « marche » : système, sans shell, home /opt/marche" "useradd --system --shell /usr/sbin/nologin" \
        bash -c "[[ \$(id -u marche) -lt 1000 && \$(getent passwd marche | cut -d: -f6,7) == /opt/marche:/usr/sbin/nologin ]]"
    critere "/opt/marche : root:marche 750" "" test "$(mode /opt/marche)" = "root:marche 750"
    critere "$CODE : le code appartient à root" "" test "$(stat -L -c %U "$CODE" 2>/dev/null)" = root
    critere "Le service ne peut PAS modifier son propre code" "chmod -R go-w, chown root" \
        bash -c "[ -f $CODE/gateway.py ] && id marche && ! runuser -u marche -- test -w $CODE/ && ! runuser -u marche -- test -w $CODE/gateway.py"
    critere "/var/lib/marche : marche:marche 750" "" test "$(mode /var/lib/marche)" = "marche:marche 750"
    critere "/var/log/marche : root:devs 750" "" test "$(mode /var/log/marche)" = "root:devs 750"
    critere "Les membres de devs (awa, koffi) peuvent lire /var/log/marche" "groupe propriétaire devs + r-x" \
        bash -c "runuser -u awa -- ls /var/log/marche && runuser -u koffi -- ls /var/log/marche"
    critere "/etc/marche/marche.env : root:marche 640, contient DATABASE_URL" "le secret ne doit être lisible que par root et le service" \
        bash -c "[[ \$(stat -c '%U:%G %a' /etc/marche/marche.env) == 'root:marche 640' ]] && grep -q '^DATABASE_URL=' /etc/marche/marche.env"
    critere "Un autre utilisateur ne peut pas lire le secret" "" \
        bash -c "[ -f /etc/marche/marche.env ] && id awa && ! runuser -u awa -- cat /etc/marche/marche.env"

    section "Palier $PALIER — Services"
    local s
    for s in "${UNITES[@]}"; do
        if [ "$PALIER" -ge 2 ]; then
            critere "$s : actif, démarré au boot par marche.target" "systemctl enable --now marche.target" \
                bash -c "systemctl is-active -q $s && systemctl is-enabled -q marche.target && systemctl list-dependencies --plain marche.target | grep -qw '$s.service'"
        else
            critere "$s : actif et activé au démarrage" "systemctl enable --now $s" \
                bash -c "systemctl is-active -q $s && systemctl is-enabled -q $s"
        fi
        critere "$s : tourne en tant que « marche », redémarre en cas d'échec" "User=marche, Restart=on-failure" \
            bash -c "[[ \$(systemctl show -p User --value $s) == marche && \$(systemctl show -p Restart --value $s) =~ on-failure|always ]]"
    done
    critere "PostgreSQL : base « marche » détenue par le rôle « marche »" "createdb -O marche marche" \
        bash -c "runuser -u postgres -- psql -tAc \"select pg_get_userbyid(datdba) from pg_database where datname='marche'\" | grep -qx marche"
    critere "orders joint bien sa base (/healthz)" "journalctl -u $U_ORDERS" \
        bash -c "curl -fsS -m 5 http://127.0.0.1:8001/healthz | grep -q '\"database\":\"up\"'"
    critere "Les services n'écoutent que sur 127.0.0.1" "LISTEN_HOST par défaut" \
        bash -c "[ \$(ss -Htln | awk '{print \$4}' | grep -cE '^127\.0\.0\.1:(8000|8001|8002)$') -eq 3 ] && ! ss -Htln | awk '{print \$4}' | grep -E ':(8000|8001|8002)$' | grep -qv '^127.0.0.1:'"
    critere "Redémarrage automatique : orders revient après un SIGKILL" "Restart=on-failure" \
        bash -c "systemctl kill -s SIGKILL $U_ORDERS && sleep 6 && systemctl is-active -q $U_ORDERS"

    section "Palier $PALIER — nginx"
    critere "nginx : configuration valide" "nginx -t" nginx -t
    critere "Site par défaut désactivé, site « marche » activé" "" \
        bash -c "[ ! -e /etc/nginx/sites-enabled/default ] && [ -e /etc/nginx/sites-enabled/marche ]"
    critere "$WEB/api/products répond 200" "proxy_pass http://127.0.0.1:8000" test "$(code_http "$WEB/api/products")" = 200
    critere "/admin/ est bloqué par nginx (403)" "location /admin/ { deny all; }" test "$(code_http "$WEB/admin/chaos")" = 403
    critere "Journal d'accès dédié /var/log/nginx/marche.access.log alimenté" "access_log dans le server" \
        test -s /var/log/nginx/marche.access.log

    if [ "$PALIER" -eq 1 ]; then
        section "Palier 1 — Pare-feu"
        critere "ufw actif" "ufw allow 22/tcp AVANT ufw enable" bash -c "ufw status | grep -q 'Status: active'"
        critere "Seuls 22/tcp et 80/tcp sont ouverts" "ufw status numbered, ufw delete" \
            bash -c "[[ \$(ufw status | awk '/ALLOW/ {print \$1}' | sort -u | tr '\n' ' ') == '22/tcp 80/tcp ' ]]"
        critere "Aucune règle ne bloque 22 ou 80 (ufw lit les règles dans l'ordre)" "ufw status numbered : un DENY placé avant l'ALLOW gagne" \
            bash -c "ufw status | grep -q 'Status: active' && ! ufw status | grep -E '^(22|80)/tcp' | grep -qE 'DENY|REJECT'"
    fi

    section "Palier $PALIER — Automatisation"
    critere "marche-healthcheck : exécutable, code 0 quand tout va bien" "exit 0/1 selon l'état" /usr/local/bin/marche-healthcheck
    critere "marche-healthcheck : code non nul si un service est arrêté" "tester TOUS les services, pas seulement le premier" \
        bash -c "[ -x /usr/local/bin/marche-healthcheck ] && systemctl is-active -q $U_PAYMENTS || exit 1; systemctl stop $U_PAYMENTS; /usr/local/bin/marche-healthcheck; rc=\$?; systemctl start $U_PAYMENTS; sleep 3; [ \$rc -ne 0 ]"
    if [ "$PALIER" -eq 1 ]; then
        critere "/etc/cron.d/marche : healthcheck toutes les 5 min, backup quotidien, colonne utilisateur" \
            "dans /etc/cron.d il y a une colonne utilisateur" \
            bash -c "grep -Eq '^\*/5 +\* +\* +\* +\* +root +/usr/local/bin/marche-healthcheck' /etc/cron.d/marche && grep -Eq '^[0-9]+ +[0-9]+ +\* +\* +\* +root +/usr/local/bin/marche-backup' /etc/cron.d/marche"
        critere "La sortie des tâches cron est conservée (pas de >/dev/null)" "" \
            bash -c "[ -f /etc/cron.d/marche ] && ! grep -Ev '^[[:space:]]*#' /etc/cron.d/marche | grep -q '/dev/null'"
        critere "cron a réellement lancé le healthcheck ces 11 dernières minutes (journal de cron)" \
            "attendre 10 min ; sinon : colonne utilisateur, PATH, droits d'exécution" \
            bash -c "journalctl -u cron --since '-11min' --no-pager | grep -F 'CMD (' | grep -q 'marche-healthcheck'"
    fi
    critere "marche-backup produit une sauvegarde valide" "pipefail, fichier temporaire, gzip" \
        bash -c "/usr/local/bin/marche-backup && f=\$(ls -1t /var/backups/marche/marche-*.sql.gz | head -1) && gzip -t \"\$f\" && zcat \"\$f\" | grep -q 'CREATE TABLE public.orders'"
    critere "Sauvegardes non lisibles par tout le monde" "chmod 640 sur les fichiers, 750 sur le dossier" \
        bash -c "ls /var/backups/marche/marche-*.sql.gz && ! find /var/backups/marche -maxdepth 1 -perm -o+r | grep -q ."
    critere "Rotation : 7 sauvegardes au plus" "ls -1t | tail -n +8 | xargs -r rm" \
        bash -c "[ -x /usr/local/bin/marche-backup ] || exit 1; for i in 1 2 3 4 5 6 7 8; do /usr/local/bin/marche-backup || exit 1; sleep 1.1; done; n=\$(ls /var/backups/marche/marche-*.sql.gz | wc -l); [ \$n -ge 1 ] && [ \$n -le 7 ]"
    critere "logrotate : configuration de /var/log/marche valide" "logrotate -d /etc/logrotate.d/marche" \
        bash -c "[ -f /etc/logrotate.d/marche ] && ! logrotate -d /etc/logrotate.d/marche 2>&1 | grep -qi error"

    section "Palier 1 — Enquête sur les logs"
    if [ -n "$REPONSES" ]; then
        verifier_reponses "$REPONSES"
    else
        rouge "Réponses de l'enquête non fournies" "relancez avec --reponses /chemin/REPONSES.txt"
    fi
}

# Réponses attendues : empreintes SHA-256 des réponses normalisées (pas de spoiler ici)
declare -A ATTENDU=(
    [1]=48b149ba67946efc5af8f42f268bee9ee86b6ce8ec4a4b56906df4d7f4a61adf
    [2]=aee4848a8580f31102073d34012cb3700fee3e61f9fcfd725fcfe5fa4a220ec3
    [3]=a178eef01d341f161e146d98f58f3901a97ebd30d48701a7f46cd24197434f38
    [4]=8527a891e224136950ff32ca212b45bc93f69fbb801c3b1ebedac52775f99e61
    [5]=97543384bedb2d7ddf632a06245f377f61b3b143d5626bc018f5a5da7aa41357
    [6]=e91ef0955e1cb9507000209fd68e8b495e79b55a51db28fcbc48f608519cf10e
    [7]=a0b5322afbb030d7c3c8d9c63bc05fb133843d319efaab413da4180d2b4a9c3d
    [8]=6b51d431df5d7f141cbececcf79edf3dd861c3b4069f0b11661a3eefacbba918
    [9]=a3c241dba9a9f09508af765651c3c65633370c1e4a491afd2fb7fab24ee4dac4
    [10]=f491e65f8d4b8dbec7621fcedaf1b7a4b21bf6cfe8070f407548a6334dc55ccd
)
normaliser() {   # normaliser <n° de question> <réponse brute>
    local r; r=$(tr 'A-Z,' 'a-z.' <<< "$2")
    case $1 in
        1|2|4|7|8|10) r=$(tr -cd '0-9.' <<< "$r") ;;
        3|6)          r=$(tr -cd '0-9.;' <<< "$r") ;;
        5)            r=$(tr -cd '0-9:-' <<< "$r") ;;
        9)            r=$(tr -cd 'a-z0-9' <<< "$r") ;;
    esac
    printf '%s' "$r"
}
verifier_reponses() {
    local fichier=$1 q brut
    [ -r "$fichier" ] || { rouge "Fichier de réponses lisible : $fichier"; return; }
    for q in 1 2 3 4 5 6 7 8 9 10; do
        brut=$(grep -E "^Q$q *=" "$fichier" | head -1 | cut -d= -f2-)
        if [ -z "$brut" ]; then rouge "Q$q : réponse absente" "format : Q$q=…"; continue; fi
        if [[ $(normaliser "$q" "$brut" | sha256sum | cut -d' ' -f1) == "${ATTENDU[$q]}" ]]; then
            vert "Q$q : exacte"
        else
            rouge "Q$q : inexacte ($brut)" "relisez la question et le format attendu dans palier-1.md"
        fi
    done
}

# ------------------------------------------------------------------------------------ Palier 2
MARCHECTL=/usr/local/sbin/marchectl

# Le volume logique $1 est-il bien le périphérique monté sur $2 ? (comparaison majeur:mineur,
# fiable même sans udev, là où les noms /dev/mapper/… et /dev/dm-N varient)
lv_monte_sur() {
    local lv=$1 point=$2
    mountpoint -q "$point" || return 1
    [ "$(mountpoint -d "$point")" = "$(dmsetup info -c --noheadings -o major,minor --separator : "vg_marche-$lv" | tr -d ' ')" ]
}
fstab_par_uuid() {   # une ligne UUID=… pour ce point de montage, et l'UUID est bien celui du LV
    local lv=$1 point=$2 uuid
    uuid=$(blkid -o value -s UUID "/dev/vg_marche/$lv") || return 1
    grep -Ev '^[[:space:]]*#' /etc/fstab | awk -v p="$point" '$2 == p {print $1}' | grep -qx "UUID=$uuid"
}
exposition() {   # score systemd-analyze security d'une unité (0 = parfait, 10 = rien de fait)
    systemd-analyze security "$1" --no-pager 2>/dev/null | grep -oP 'Overall exposure level for \S+: \K[0-9.]+'
}
# Déploie une copie VOLONTAIREMENT cassée de la version en service : marchectl doit la refuser
# après le contrôle de santé, revenir tout seul à la version d'avant, et sortir avec le code 4.
test_retour_arriere_auto() {
    local t avant apres rc
    t=$(mktemp -d)
    rsync -a --exclude venv/ "$CODE"/ "$t/marche-9.9.9/"
    echo 9.9.9 > "$t/marche-9.9.9/VERSION"
    sed -i '0,/^import /s//import module_absent_du_correcteur\nimport /' "$t/marche-9.9.9/gateway.py"
    tar -C "$t" -czf "$t/marche-9.9.9.tar.gz" marche-9.9.9
    avant=$(readlink -f "$CODE")
    "$MARCHECTL" deploy "$t/marche-9.9.9.tar.gz"; rc=$?
    apres=$(readlink -f "$CODE")
    rm -rf "$t" /opt/marche/releases/9.9.9
    if [ "$apres" != "$avant" ]; then           # remettre le lab dans l'état où on l'a trouvé
        ln -sfn "$avant" "$CODE" && systemctl restart marche.target
    fi
    [ "$rc" -eq 4 ] && [ "$apres" = "$avant" ] && "$MARCHECTL" status
}
# Pendant qu'une opération tient le verrou, une seconde doit être refusée (code 3) sans rien toucher
test_verrou() {
    local rc
    ( flock 9; sleep 5 ) 9>/run/marchectl.lock &
    sleep 1
    "$MARCHECTL" rollback; rc=$?
    wait
    [ "$rc" -eq 0 ] && "$MARCHECTL" rollback      # pas de verrou : on annule le retour arrière fait
    [ "$rc" -eq 3 ]
}
# Recharger SA configuration ne doit pas effacer les bannissements de fail2ban.
# (reload, pas restart : l'unité Ubuntu fait « nft flush ruleset » à l'arrêt, donc restart
#  efface TOUT, quelle que soit la configuration — voir palier-2.md, pièges)
# Le filtre maison, rejoué sur le journal du 14 septembre : exactement les 42 sondes du scanner
test_filtre_sondes() {
    local journal=$1 t n_total n_scanner
    [ -r "$journal" ] && [ -f /etc/fail2ban/filter.d/marche-sondes.conf ] || return 1
    t=$(mktemp)
    zcat "$journal" > "$t.log"
    fail2ban-regex --print-all-matched "$t.log" /etc/fail2ban/filter.d/marche-sondes.conf > "$t"
    n_total=$(grep -cE '^\|  [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ' "$t")
    n_scanner=$(grep -c '^|  185\.220\.101\.42 ' "$t")
    rm -f "$t" "$t.log"
    [ "$n_total" -eq 42 ] && [ "$n_scanner" -eq 42 ]
}
test_ban_survit_pare_feu() {
    local ip=203.0.113.77 ok=1
    # (pas de « nft list ruleset | grep -q » ici : avec pipefail, grep -q qui s'arrête tôt
    #  tue nft par SIGPIPE et le pipeline échoue alors que l'adresse est bien là)
    fail2ban-client set sshd banip "$ip" || return 1
    [[ $(nft list ruleset 2>/dev/null) == *"$ip"* ]] || ok=0
    systemctl reload nftables
    [[ $(nft list ruleset 2>/dev/null) == *"$ip"* ]] || ok=0
    fail2ban-client set sshd unbanip "$ip"
    [ "$ok" -eq 1 ]
}
test_partage() {   # un fichier créé par awa appartient au groupe devs et reste lisible par audit
    local f=/srv/partage/.verif-$$ ok=1
    runuser -u awa -- sh -c "umask 007; echo test > $f" || return 1
    [ "$(stat -c %G "$f")" = devs ] || ok=0
    runuser -u koffi -- cat "$f" || ok=0
    runuser -u audit -- cat "$f" || ok=0
    rm -f "$f"
    [ "$ok" -eq 1 ]
}

# Consommation CPU d'une unité sur 3 secondes, en % d'un cœur (comptabilité cgroup de systemd)
cpu_unite() {
    local a b
    a=$(systemctl show -p CPUUsageNSec --value "$1"); sleep 3
    b=$(systemctl show -p CPUUsageNSec --value "$1")
    [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]] || { echo 999; return; }
    echo $(( (b - a) / 30000000 ))
}
occupation_max() {   # plus fort pourcentage (pcent : espace, ipcent : inodes) des volumes de Marché
    df --output="$1" / /var/lib/postgresql /var/backups/marche | tail -n +2 | tr -dc '0-9\n' | sort -n | tail -1
}
latence_commande() {   # médiane de 5 commandes passées à travers nginx, en millisecondes
    local _
    for _ in 1 2 3 4 5; do
        "${CURL[@]}" -s -o /dev/null -m 10 -w '%{time_total}\n' -H 'Content-Type: application/json' \
            -d '{"product_id":1,"quantity":1,"payment_method":"card"}' "$WEB/api/orders"
    done | sort -n | sed -n 3p | awk '{printf "%d", $1 * 1000}'
}

# Mesurée EN PREMIER, avant tout critère qui redémarre un service : on observe avant de toucher
# (un redémarrage efface les symptômes — et c'est aussi vrai en production).
sante_production() {
    section "Palier 2 — Santé de production (mesurée avant toute intervention)"
    local s c m1 m2
    m1=$(systemctl show -p MemoryCurrent --value marche@gateway)
    for s in marche@gateway marche@orders marche@payments; do
        c=$(cpu_unite $s)
        critere "$s : CPU au repos sous 50 % d'un cœur (mesuré : $c %)" "top -H, ps -eLf : quel THREAD tourne ?" test "$c" -lt 50
    done
    # À 2 requêtes/s, le générateur seul ne rend pas toujours une fuite visible en quelques secondes :
    # le correcteur ajoute son propre trafic entre les deux mesures.
    for s in $(seq 40); do code_http "$WEB/api/products" >/dev/null; done
    m2=$(systemctl show -p MemoryCurrent --value marche@gateway)
    local mesure hausse
    if [[ $m1 =~ ^[0-9]+$ && $m2 =~ ^[0-9]+$ ]]; then mesure="$((m2 / 1048576)) Mo"; hausse="+$(((m2 - m1) / 1048576)) Mo"
    else m1=0; m2=999999999; mesure="illisible, service arrêté ?"; hausse=$mesure; fi
    critere "marche@gateway : mémoire sous 150 Mo (mesuré : $mesure)" "une mémoire qui monte sans redescendre = une fuite" \
        test "$m2" -lt 157286400
    critere "marche@gateway : mémoire stable ($hausse en 9 s et 40 requêtes)" "systemctl show -p MemoryCurrent, plusieurs fois : ça monte ?" \
        test $((m2 - m1)) -lt 4194304
    critere "Aucun service tué pour manque de mémoire ces 15 dernières minutes" "journalctl -u 'marche@*' | grep -i oom" \
        bash -c "! journalctl -u 'marche@*' --since '-15min' --no-pager | grep -qi 'oom-kill'"
    local l; l=$(latence_commande)
    critere "Passer une commande prend moins de 500 ms (médiane mesurée : ${l:-?} ms)" "où passe le temps ? nginx → gateway → orders → PostgreSQL (pg_stat_activity)" \
        test "${l:-99999}" -lt 500
    local d; d=$(occupation_max pcent)
    critere "Disques : moins de 85 % d'espace utilisé (maximum mesuré : $d %)" "df -h ; du ne voit pas les fichiers supprimés mais ouverts : lsof +L1" \
        test "${d:-100}" -lt 85
    d=$(occupation_max ipcent)
    critere "Disques : moins de 90 % des inodes utilisés (maximum mesuré : $d %)" "df -i ; trouver le dossier aux milliers de fichiers" \
        test "${d:-100}" -lt 90
    critere "marche@gateway : au moins 1024 descripteurs de fichiers autorisés" "systemctl show -p LimitNOFILE,DropInPaths ; systemctl cat" \
        test "$(systemctl show -p LimitNOFILE --value marche@gateway)" -ge 1024
    # (systemd-delta ne voit PAS les drop-in d'une instance d'unité modèle : marche@gateway.service.d/)
    critere "Aucune surcharge (drop-in) sur les services de Marché" "systemctl cat ; systemctl show -p DropInPaths" \
        test -z "$(systemctl show -p DropInPaths --value marche@gateway marche@orders marche@payments marche-loadgen | tr -d '[:space:]')"
}

palier2() {
    local u; u=$(admin_perso)

    section "Palier 2 — Stockage (LVM)"
    critere "Groupe de volumes vg_marche avec lv_pgdata et lv_backups" "pvcreate, vgcreate, lvcreate" \
        bash -c "lvs vg_marche/lv_pgdata && lvs vg_marche/lv_backups"
    critere "lv_pgdata monté sur /var/lib/postgresql" "migrer le contenu PostgreSQL ARRÊTÉ, puis monter" lv_monte_sur lv_pgdata /var/lib/postgresql
    critere "lv_backups monté sur /var/backups/marche" "" lv_monte_sur lv_backups /var/backups/marche
    critere "Les données de PostgreSQL sont bien sur le volume" "show data_directory" \
        bash -c "d=\$(runuser -u postgres -- psql -tAc 'show data_directory') && [ \"\$(findmnt -n -o TARGET -T \"\$d\")\" = /var/lib/postgresql ]"
    critere "/etc/fstab : les deux volumes déclarés par UUID" "blkid ; UUID=… point ext4 options 0 2" \
        bash -c "$(declare -f fstab_par_uuid); fstab_par_uuid lv_pgdata /var/lib/postgresql && fstab_par_uuid lv_backups /var/backups/marche"
    critere "/etc/fstab : le volume des sauvegardes est en nofail (la machine démarre même sans lui)" "" \
        bash -c "grep -Ev '^[[:space:]]*#' /etc/fstab | awk '\$2 == \"/var/backups/marche\" {print \$4}' | grep -qw nofail"
    critere "/etc/fstab valide (findmnt --verify)" "une erreur ici = une machine qui ne redémarre pas" findmnt --verify
    critere "lv_backups agrandi à 600 Mo au moins, système de fichiers compris" "lvextend -r (sans -r, df ne bouge pas)" \
        bash -c "[ \$(lvs --noheadings --units m --nosuffix -o lv_size vg_marche/lv_backups | cut -d. -f1 | tr -d ' ') -ge 600 ] && [ \$(df -BM --output=size /var/backups/marche | tail -1 | tr -dc 0-9) -ge 550 ]"

    section "Palier 2 — Déploiement par versions (marchectl)"
    critere "$MARCHECTL : root:root 700" "install -m 700" test "$(mode "$MARCHECTL")" = "root:root 700"
    critere "/opt/marche/current : lien symbolique vers /opt/marche/releases/X.Y.Z" "ln -sfn + mv -T" \
        bash -c "[ -L /opt/marche/current ] && [[ \$(readlink -f /opt/marche/current) =~ ^/opt/marche/releases/[0-9]+\.[0-9]+\.[0-9]+$ ]]"
    critere "Chaque version a son propre venv" "le venv fait partie de la version" \
        test -x /opt/marche/current/venv/bin/python
    critere "Une version précédente est connue (retour arrière possible)" "déployez au moins deux versions" \
        bash -c "[ -d \"\$(cat /opt/marche/.precedente)\" ] && [ \"\$(cat /opt/marche/.precedente)\" != \"\$(readlink -f /opt/marche/current)\" ]"
    critere "marchectl status : code 0, santé OK" "" "$MARCHECTL" status
    critere "Une archive dont l'empreinte est fausse est refusée" "sha256sum -c" \
        bash -c "t=\$(mktemp -d); mkdir \$t/marche-9.9.8; tar -C \$t -czf \$t/marche-9.9.8.tar.gz marche-9.9.8; printf '%064d  marche-9.9.8.tar.gz\n' 0 > \$t/marche-9.9.8.tar.gz.sha256; $MARCHECTL deploy \$t/marche-9.9.8.tar.gz; rc=\$?; rm -rf \$t; [ \$rc -eq 1 ] && [ ! -e /opt/marche/releases/9.9.8 ]"
    critere "Version malade → retour arrière AUTOMATIQUE, code 4, service rétabli" "contrôle de santé après bascule" test_retour_arriere_auto
    critere "Deux opérations simultanées : la seconde est refusée (code 3)" "flock -n" test_verrou
    critere "Journal des opérations /var/log/marche/marchectl.log (qui, quoi, quand)" "" \
        bash -c "grep -q 'SUCCÈS' /var/log/marche/marchectl.log && grep -q 'ÉCHEC du contrôle de santé' /var/log/marche/marchectl.log"

    section "Palier 2 — systemd"
    critere "Unité modèle marche@.service et cible marche.target" "une unité pour les trois services Python" \
        bash -c "systemctl cat marche@.service && systemctl is-enabled -q marche.target"
    critere "Les unités du Palier 1 ont disparu" "disable --now + rm + daemon-reload" \
        bash -c "for s in marche-gateway marche-orders marche-payments; do [ \"\$(systemctl show -p LoadState --value \$s)\" = not-found ] || exit 1; done"
    local e; e=$(exposition marche@gateway.service)
    critere "Durcissement : exposition de marche@gateway ≤ 4.0 (mesuré : ${e:-?})" "systemd-analyze security marche@gateway" \
        awk -v e="${e:-99}" 'BEGIN { exit !(e <= 4.0) }'
    critere "Limite mémoire (MemoryMax) sur les services" "MemoryMax=300M" \
        bash -c "for s in marche@gateway marche@orders marche@payments; do [ \"\$(systemctl show -p MemoryMax --value \$s)\" != infinity ] || exit 1; done"
    critere "Plus aucune tâche cron pour Marché" "les timers remplacent cron" \
        bash -c "[ ! -e /etc/cron.d/marche ] && ! crontab -l -u root 2>/dev/null | grep -q marche"
    critere "Timers marche-backup et marche-healthcheck activés et programmés" "systemctl enable --now *.timer" \
        bash -c "for t in marche-backup marche-healthcheck; do systemctl is-enabled -q \$t.timer && systemctl is-active -q \$t.timer || exit 1; done"
    critere "marche-backup.timer rattrape une exécution manquée (Persistent=true)" "" \
        test "$(systemctl show -p Persistent --value marche-backup.timer)" = yes
    # (on vérifie le déclenchement, pas le résultat : le correcteur lui-même casse des choses
    #  pendant ses tests, et le healthcheck a alors raison d'échouer)
    critere "Le timer a réellement déclenché le healthcheck ces 11 dernières minutes" "OnBootSec + OnUnitActiveSec ; journalctl -u marche-healthcheck" \
        bash -c "journalctl -u marche-healthcheck.service --since '-11min' --no-pager | grep -q 'Starting marche-healthcheck.service'"
    critere "journald : taille maximale fixée (SystemMaxUse)" "/etc/systemd/journald.conf.d/*.conf" \
        bash -c "systemd-analyze cat-config systemd/journald.conf | grep -Eq '^SystemMaxUse=[0-9]+'"

    section "Palier 2 — Sauvegardes"
    critere "Sauvegarde refusée si le volume n'est pas monté (code non nul)" "mountpoint -q" \
        grep -q 'mountpoint' /usr/local/bin/marche-backup
    critere "Instantanés de configuration dans config/, lien config/latest" "rsync --link-dest" \
        bash -c "[ -L /var/backups/marche/config/latest ] && [ -f /var/backups/marche/config/latest/etc/marche/marche.env ]"
    critere "Fichiers inchangés partagés entre instantanés (liens physiques)" "--link-dest=<instantané précédent>" \
        bash -c "[ \$(stat -c %h /var/backups/marche/config/latest/etc/marche/marche.env) -ge 2 ]"
    critere "Test de restauration de la dernière sauvegarde réussi (marchectl restore -t)" "une sauvegarde jamais restaurée n'est pas une sauvegarde" \
        bash -c "$MARCHECTL restore -t \$(ls -1t /var/backups/marche/marche-*.sql.gz | head -1) | grep -q 'réussi'"

    section "Palier 2 — Accès et délégation"
    critere "Compte deploy : clé SSH, pas dans le groupe sudo" "" \
        bash -c "[ -s /home/deploy/.ssh/authorized_keys ] && ! id -nG deploy | grep -qw sudo"
    critere "deploy peut lancer marchectl via sudo, sans mot de passe" "/etc/sudoers.d/ + visudo -c" \
        runuser -u deploy -- sudo -n "$MARCHECTL" status
    critere "deploy ne peut RIEN lancer d'autre en root" "Cmnd : chemin absolu, pas ALL" \
        bash -c "! runuser -u deploy -- sudo -n /usr/bin/id && ! runuser -u deploy -- sudo -n /bin/bash -c true"
    critere "sudoers valide (visudo -c)" "sudo 1.9 ignore une ligne invalide (la vôtre ?) ; sudo 1.8 se bloque pour tous" visudo -c
    critere "SSH : seul le groupe ssh-autorises peut se connecter" "AllowGroups ssh-autorises" \
        bash -c "sshd -T | grep -qx 'allowgroups ssh-autorises'"
    critere "Votre compte (${u:-?}) et deploy sont dans ssh-autorises — sinon, vous vous enfermez dehors" "usermod -aG ssh-autorises AVANT de recharger sshd" \
        bash -c "[ -n '$u' ] && id -nG '$u' | grep -qw ssh-autorises && id -nG deploy | grep -qw ssh-autorises"
    critere "SSH : 3 tentatives d'authentification au plus" "MaxAuthTries 3" bash -c "sshd -T | grep -qx 'maxauthtries 3'"
    critere "/srv/partage : root:devs, SGID, fermé aux autres (2770)" "chmod 2770" test "$(mode /srv/partage)" = "root:devs 2770"
    critere "/srv/partage : ACL par défaut pour audit (lecture)" "setfacl -d -m u:audit:rx" \
        bash -c "getfacl -p /srv/partage | grep -q '^default:user:audit:r'"
    critere "Fichier créé par awa : groupe devs, lisible par koffi ET par audit" "SGID + ACL par défaut" test_partage
    critere "audit lit /var/log/marche SANS être dans devs" "ACL, pas groupe" \
        bash -c "! id -nG audit | grep -qw devs && runuser -u audit -- cat /var/log/marche/backup.log"

    section "Palier 2 — HTTPS"
    critere "http:// redirige (301) vers https://" "return 301 https://\$host\$request_uri" \
        bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' http://127.0.0.1/api/products) == '301 https://127.0.0.1/api/products' ]]"
    critere "Clé privée : root, 600" "chmod 600" bash -c "[[ \$(stat -c '%U %a' /etc/ssl/private/marche.key) == 'root 600' ]]"
    critere "Certificat valide pour web1 et 10.10.10.21 (subjectAltName)" "openssl req -addext subjectAltName=…" \
        bash -c "openssl x509 -in /etc/ssl/certs/marche.crt -noout -ext subjectAltName | grep -q 'DNS:web1' && openssl x509 -in /etc/ssl/certs/marche.crt -noout -ext subjectAltName | grep -q 'IP Address:10.10.10.21' && openssl x509 -in /etc/ssl/certs/marche.crt -noout -checkend 2592000"
    critere "TLS 1.3 accepté" "" bash -c "timeout 5 openssl s_client -connect 127.0.0.1:443 -tls1_3 </dev/null 2>&1 | grep -q 'TLSv1.3'"
    critere "TLS 1.0 et 1.1 refusés (même par un client qui les accepte)" "ssl_protocols TLSv1.2 TLSv1.3" \
        bash -c "for v in -tls1 -tls1_1; do timeout 5 openssl s_client -connect 127.0.0.1:443 \$v -cipher 'DEFAULT:@SECLEVEL=0' </dev/null 2>&1 | grep -q 'BEGIN CERTIFICATE' && exit 1; done; nginx -T 2>/dev/null | grep -E '^\s*ssl_protocols' | grep -vqE 'TLSv1(\.1)?[ ;]'"
    critere "En-tête HSTS présent" "add_header Strict-Transport-Security … always" \
        bash -c "${CURL[*]} -sI -m 5 https://127.0.0.1/api/products | grep -qi '^strict-transport-security: max-age='"
    critere "nginx ne révèle sa version ni en HTTP ni en HTTPS" "server_tokens off dans CHAQUE server, ou dans http {}" \
        bash -c "h=\$(curl -sI -m 5 http://127.0.0.1/) && s=\$(${CURL[*]} -sI -m 5 https://127.0.0.1/api/products) && grep -qi '^server:' <<< \"\$h\$s\" && ! grep -qiE '^server: nginx/[0-9]' <<< \"\$h\$s\""

    section "Palier 2 — Pare-feu nftables et fail2ban"
    critere "ufw désactivé (un seul outil pilote le pare-feu)" "ufw disable" \
        bash -c "! systemctl is-enabled -q ufw && ! ufw status | grep -q 'Status: active'"
    critere "nftables activé au démarrage, configuration valide" "systemctl enable nftables ; nft -c -f" \
        bash -c "systemctl is-enabled -q nftables && nft -c -f /etc/nftables.conf"
    critere "Chaîne input : politique drop" "type filter hook input priority filter; policy drop;" \
        bash -c "nft list ruleset | grep -E 'hook input' | grep -q 'policy drop'"
    critere "input : lo, connexions établies, 22 et 80/443 acceptés" "" \
        bash -c "r=\$(nft list ruleset); grep -q 'iif \"lo\" accept' <<< \"\$r\" && grep -q 'established,related accept' <<< \"\$r\" && grep -q 'dport 22' <<< \"\$r\" && grep -qE 'dport \{ 80, 443 \}' <<< \"\$r\""
    critere "Pas de « flush ruleset » (il effacerait les tables de fail2ban)" "table X / delete table X" \
        bash -c "! grep -Ev '^[[:space:]]*#' /etc/nftables.conf | grep -q 'flush ruleset'"
    critere "fail2ban : jails sshd, nginx-botsearch, marche-sondes et recidive actives" "/etc/fail2ban/jail.local" \
        bash -c "l=\$(fail2ban-client status | grep 'Jail list'); for j in sshd nginx-botsearch marche-sondes recidive; do grep -qw \$j <<< \"\$l\" || exit 1; done"
    local journal; journal="$(dirname "${REPONSES:-/root/.}")/marche.access.log.gz"
    critere "Filtre marche-sondes : les 42 sondes du 14 septembre, et rien d'autre" "fail2ban-regex <journal décompressé> /etc/fail2ban/filter.d/marche-sondes.conf ($journal)" \
        test_filtre_sondes "$journal"
    critere "fail2ban agit via nftables" "banaction = nftables-multiport" \
        bash -c "fail2ban-client get sshd actions | grep -q nftables"
    critere "fail2ban ne bannit jamais la passerelle du lab (10.10.10.1)" "ignoreip" \
        bash -c "fail2ban-client get sshd ignoreip | grep -qF 10.10.10.1"
    critere "Un bannissement survit au rechargement du pare-feu (systemctl reload nftables)" "pas de flush ruleset dans /etc/nftables.conf" test_ban_survit_pare_feu
    critere "Mises à jour de sécurité automatiques actives" "unattended-upgrades" \
        bash -c "dpkg -s unattended-upgrades | grep -q 'ok installed' && apt-config dump APT::Periodic::Unattended-Upgrade | grep -q '\"1\"'"

    section "Palier 2 — Audit (auditd)"
    if auditctl -s >/dev/null 2>&1; then
        critere "Règles auditd chargées pour /etc/marche et sudoers" "/etc/audit/rules.d/*.rules + augenrules --load" \
            bash -c "auditctl -l | grep -q /etc/marche && auditctl -l | grep -q /etc/sudoers"
    else
        info "auditd indisponible ici (conteneur) : critère à valider sur une VM (voir palier-2.md)"
    fi
}

# ------------------------------------------------------------------------------------ main
case $PALIER in
    1) palier1 ;;
    2) sante_production; palier1; palier2 ;;
    *) echo "Palier inconnu : $PALIER (1 ou 2 ; le Palier 3 se vérifie avec verifier-infra.sh)" >&2; exit 2 ;;
esac

printf '\n  Score : %d/%d\n' "$OK" $((OK + KO))
if [ "$KO" -eq 0 ]; then printf '  \033[32m🎉 Palier %s validé.\033[0m\n' "$PALIER"; exit 0; fi
exit 1
