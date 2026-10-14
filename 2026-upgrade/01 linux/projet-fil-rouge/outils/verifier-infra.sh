#!/bin/bash
# verifier-infra.sh — correcteur du Palier 3, à lancer SUR ctl (le poste de contrôle Ansible),
# par l'utilisateur qui lance Ansible (clé SSH acceptée par « ubuntu » sur toutes les machines).
#
#   ./verifier-infra.sh [--ansible DOSSIER] [--sinistre]
#
#   --ansible DOSSIER   dossier de VOTRE projet Ansible (site.yml) : vérifie l'idempotence et le coffre
#   --sinistre          après « outils/sinistre.sh » : vérifie la reprise (données, RTO)
#
# Il AGIT pour vérifier : il coupe HAProxy sur le répartiteur actif, arrête un serveur web,
# lance une sauvegarde et une restauration de test. Lancez-le sur le lab, pas en production.
set -uo pipefail

ANSIBLE_DIR=""; SINISTRE=0
while [ $# -gt 0 ]; do
    case $1 in
        --ansible)  ANSIBLE_DIR=${2:?dossier ?}; shift 2 ;;
        --sinistre) SINISTRE=1; shift ;;
        *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
    esac
done

declare -A IP=([lb1]=10.10.10.11 [lb2]=10.10.10.12 [web1]=10.10.10.21 [web2]=10.10.10.22 [db1]=10.10.10.31 [bak1]=10.10.10.41)
MACHINES=(lb1 lb2 web1 web2 db1 bak1)
VIP=10.10.10.100
WG_BAK=10.20.0.1
CA=$(mktemp); trap 'rm -f "$CA"' EXIT

OK=0; KO=0
vert()    { printf '  \033[32m✔\033[0m %s\n' "$1"; OK=$((OK + 1)); }
rouge()   { printf '  \033[31m✘\033[0m %s\033[2m%s\033[0m\n' "$1" "${2:+  → $2}"; KO=$((KO + 1)); }
info()    { printf '  \033[33m•\033[0m %s\n' "$1"; }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
critere() { local l=$1 i=$2; shift 2; if "$@" >/dev/null 2>&1; then vert "$l"; else rouge "$l" "$i"; fi; }

SSH=(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new
     -o ControlMaster=auto -o "ControlPath=/tmp/verif-infra-%h" -o ControlPersist=300)
# sur <machine> <commande> : la commande, en root, sur la machine
sur() { local m=$1; shift; "${SSH[@]}" "ubuntu@${IP[$m]}" "sudo -n bash -c $(printf '%q' "$*")"; }
# joint <depuis> <ip> <port> : connexion TCP possible ?
joint() { sur "$1" "nc -z -w 3 $2 $3"; }
web()   { curl -s -o /dev/null -w '%{http_code}' -m 5 --cacert "$CA" "$@"; }
porteurs_vip() { local lb n=""; for lb in lb1 lb2; do sur "$lb" "ip -4 -o addr show | grep -q ' $VIP/'" && n+="$lb "; done; echo "${n% }"; }
# boucle <n> : n requêtes espacées de 0,25 s vers le site ; affiche le nombre d'échecs
boucle() { local ko=0; for _ in $(seq "$1"); do curl -fsS -m 2 -o /dev/null --cacert "$CA" "https://$VIP/api/products" 2>/dev/null || ko=$((ko + 1)); sleep 0.25; done; echo "$ko"; }
etat_serveur() {   # etat_serveur <lb> <web> : UP / DOWN / MAINT vu par HAProxy
    sur "$1" "echo 'show stat' | socat stdio /run/haproxy/admin.sock" | awk -F, -v s="$2" '$1=="marche_web" && $2==s {print $18}'
}

# ------------------------------------------------------------------------------------------
section "Palier 3 — Accès aux machines"
for m in "${MACHINES[@]}"; do
    critere "$m : SSH par clé (ubuntu) et sudo sans mot de passe" "./lab.sh autoriser ~/.ssh/id_ed25519.pub ; ssh-keygen -R ${IP[$m]} après une recréation" \
        sur "$m" true
done

section "Palier 3 — Socle commun (rôle commun + parefeu)"
for m in "${MACHINES[@]}"; do
    critere "$m : fuseau Africa/Lome, SSH durci (root, mots de passe, AllowGroups)" "rôle commun" \
        sur "$m" "[ \$(timedatectl show -p Timezone --value) = Africa/Lome ] && sshd -T | grep -qx 'permitrootlogin no' && sshd -T | grep -qx 'passwordauthentication no' && sshd -T | grep -qi '^allowgroups '"
    critere "$m : compte d'administration personnel (sudo, clé, mot de passe)" "rôle commun" \
        sur "$m" "u=\$(getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -vx ubuntu | head -1); [ -n \"\$u\" ] && [ -s /home/\$u/.ssh/authorized_keys ] && [ \$(passwd -S \$u | awk '{print \$2}') = P ]"
    critere "$m : nftables actif, politique drop, ufw arrêté, fail2ban actif" "rôle parefeu" \
        sur "$m" "systemctl is-active -q nftables && nft list ruleset | grep 'hook input' | grep -q 'policy drop' && ! systemctl is-active -q ufw && systemctl is-active -q fail2ban"
done

section "Palier 3 — Cloisonnement réseau (chaque service n'est joignable que par qui en a besoin)"
# Une NOUVELLE connexion authentifiée, pas seulement le port : les connexions déjà ouvertes
# (pool du service orders) survivent à une ligne retirée de pg_hba — jusqu'au prochain redémarrage.
connexion_base='set -a; . /etc/marche/marche.env; /opt/marche/current/venv/bin/python -c "import os, psycopg; psycopg.connect(os.environ[\"DATABASE_URL\"], connect_timeout=5).close()"'
for m in web1 web2; do
    critere "$m : nouvelle connexion à PostgreSQL (db1) acceptée, avec le compte de l'application" "pg_hba + nftables sur db1 ; journal de PostgreSQL" \
        sur "$m" "$connexion_base"
done
critere "PostgreSQL injoignable depuis lb1 et depuis ctl" "nftables db1 : 5432 depuis les web seulement" \
    eval "! joint lb1 10.10.10.31 5432 && ! nc -z -w 3 10.10.10.31 5432"
critere "nginx des web (port 80) joignable depuis les répartiteurs seulement" "nftables web : 80 depuis lb1, lb2" \
    eval "joint lb1 10.10.10.21 80 && joint lb2 10.10.10.22 80 && ! nc -z -w 3 10.10.10.21 80 && ! joint db1 10.10.10.22 80"
critere "SSH des machines refusé depuis une autre machine de production (web1 → db1)" "22 depuis l'administration seulement" \
    eval "! joint web1 10.10.10.31 22"
critere "bak1 : SSH injoignable depuis db1 par le réseau local, joignable par le tunnel" "iifname wg0 tcp dport 22" \
    eval "! joint db1 10.10.10.41 22 && joint db1 $WG_BAK 22"

section "Palier 3 — Le site, à travers l'IP virtuelle"
sur lb1 "openssl x509 -in /etc/haproxy/certs/marche.pem" > "$CA" 2>/dev/null || sur lb2 "openssl x509 -in /etc/haproxy/certs/marche.pem" > "$CA" 2>/dev/null
p=$(porteurs_vip)
critere "IP virtuelle $VIP portée par exactement UN répartiteur (actuellement : ${p:-aucun})" "keepalived ; deux porteurs = split-brain (VRRP bloqué ?)" \
    test "$(wc -w <<< "$p")" -eq 1
critere "keepalived actif et activé sur lb1 ET lb2 (sinon : plus de redondance, sans symptôme)" "systemctl status keepalived ; journalctl -u keepalived" \
    eval "sur lb1 'systemctl is-active -q keepalived && systemctl is-enabled -q keepalived' && sur lb2 'systemctl is-active -q keepalived && systemctl is-enabled -q keepalived'"
critere "https://$VIP/api/products → 200, certificat vérifié" "HAProxy : bind *:443 ssl crt …" test "$(web "https://$VIP/api/products")" = 200
critere "http://$VIP → 301 vers https" "http-request redirect scheme https" \
    bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -m 5 http://$VIP/api/products) == '301 https://'* ]]"
critere "/admin refusé par le répartiteur" "http-request deny if { path_beg /admin }" \
    bash -c "c=\$(curl -s -o /dev/null -w '%{http_code}' -m 5 --cacert $CA https://$VIP/admin/chaos); [ \"\$c\" = 403 ]"
critere "HSTS présent" "http-response set-header Strict-Transport-Security" \
    bash -c "curl -sI -m 5 --cacert $CA https://$VIP/api/products | grep -qi '^strict-transport-security'"
for lb in lb1 lb2; do
    critere "$lb : HAProxy voit web1 et web2 UP" "option httpchk GET /sante ; voir « show stat »" \
        eval "[ \"\$(etat_serveur $lb web1)\" = UP ] && [ \"\$(etat_serveur $lb web2)\" = UP ]"
done
critere "web1 et web2 servent la MÊME version" "marchectl status ; l'inventaire fixe marche_version" \
    eval "a=\$(sur web1 readlink -f /opt/marche/current); b=\$(sur web2 readlink -f /opt/marche/current); [ -n \"\$a\" ] && [ \"\$a\" = \"\$b\" ]"
avant=$(sur db1 "runuser -u postgres -- psql -tAc 'select count(*) from orders' marche" 2>/dev/null || echo 0)
sleep 8
apres=$(sur db1 "runuser -u postgres -- psql -tAc 'select count(*) from orders' marche" 2>/dev/null || echo 0)
critere "Des commandes arrivent dans db1 à travers toute la chaîne (+$((apres - avant)) en 8 s)" "marche-loadgen sur web1, vers https://$VIP" \
    test "$apres" -gt "$avant"

section "Palier 3 — Haute disponibilité (tests actifs)"
actif=$(porteurs_vip); actif=${actif%% *}
if [ -n "$actif" ]; then
    autre=lb1; [ "$actif" = lb1 ] && autre=lb2
    boucle 60 > /tmp/verif-bascule.txt &
    sleep 2; sur "$actif" "systemctl stop haproxy"; sleep 8
    apres_bascule=$(porteurs_vip)
    wait
    ko=$(cat /tmp/verif-bascule.txt)
    critere "HAProxy arrêté sur $actif → l'IP virtuelle passe sur $autre (porteur : ${apres_bascule:-aucun})" "vrrp_script + track_script" \
        test "$apres_bascule" = "$autre"
    critere "Pendant la bascule, 5 requêtes perdues au plus sur 60 (perdues : $ko)" "vrrp_script : interval 1, fall 1 ; advert_int 1" \
        test "$ko" -le 5
    sur "$actif" "systemctl start haproxy"; sleep 6
    critere "HAProxy relancé sur $actif : l'IP virtuelle revient, un seul porteur" "priorités 150/100, préemption" \
        test "$(porteurs_vip)" = "$actif"
else
    rouge "Tests de bascule impossibles : personne ne porte l'IP virtuelle"
fi
sur web1 "systemctl stop marche.target"; sleep 5
ko=$(boucle 20)
critere "web1 arrêté : le site répond toujours (échecs : $ko/20)" "HAProxy retire un serveur malade (httpchk)" test "$ko" -le 1
critere "web1 arrêté : HAProxy le voit DOWN" "" eval "[ \"\$(etat_serveur ${actif:-lb1} web1)\" = DOWN ]"
sur web1 "systemctl start marche.target"; sleep 6
sur web2 "systemctl stop marche@orders"; sleep 6
critere "orders arrêté sur web2 (gateway vivant) : HAProxy retire quand même web2" "/sante doit traverser orders jusqu'à la base" \
    eval "[ \"\$(etat_serveur ${actif:-lb1} web2)\" = DOWN ]"
sur web2 "systemctl start marche@orders"; sleep 6

section "Palier 3 — Sauvegardes chiffrées hors site (WireGuard + restic)"
critere "Tunnel WireGuard db1 ↔ bak1 : poignée de main de moins de 3 minutes" "wg show ; PersistentKeepalive" \
    sur db1 "t=\$(wg show wg0 latest-handshakes | awk 'NR==1 {print \$2}'); [ -n \"\$t\" ] && [ \$(( \$(date +%s) - t )) -lt 180 ]"
critere "Timer de sauvegarde activé (RPO : une heure)" "marche-sauvegarde.timer" \
    sur db1 "systemctl is-enabled -q marche-sauvegarde.timer && systemctl is-active -q marche-sauvegarde.timer"
critere "Une sauvegarde lancée maintenant réussit" "journalctl -u marche-sauvegarde" \
    sur db1 "systemctl start marche-sauvegarde.service && [ \$(systemctl show -p Result --value marche-sauvegarde.service) = success ]"
critere "Le dernier instantané restic a moins de 5 minutes" "restic snapshots" \
    sur db1 "set -a; . /etc/restic/marche.env; t=\$(restic snapshots --tag marche --latest 1 --json | python3 -c 'import sys,json,datetime; print(int(datetime.datetime.fromisoformat(json.load(sys.stdin)[-1][\"time\"]).timestamp()))'); [ \$(( \$(date +%s) - t )) -lt 300 ]"
critere "Restauration de test depuis bak1 : des commandes sont bien là" "marche-restauration -t" \
    sur db1 "marche-restauration -t | grep -Eq ': [1-9][0-9]* commandes'"
critere "bak1 ne peut pas lire les sauvegardes (pas de mot de passe restic sur bak1)" "le chiffrement se fait sur db1" \
    sur bak1 "[ ! -e /etc/restic/mdp ] && ! grep -rqs RESTIC_PASSWORD /etc /root"
critere "Le compte de dépôt n'ouvre pas de shell (sftp seulement)" "restrict,command=\"internal-sftp\"" \
    sur db1 "! ssh -o BatchMode=yes -o ConnectTimeout=5 $WG_BAK id 2>/dev/null | grep -q uid="

# ------------------------------------------------------------------------------------------
if [ -n "$ANSIBLE_DIR" ]; then
    section "Palier 3 — Ansible"
    critere "Coffre chiffré (group_vars/all/vault.yml commence par \$ANSIBLE_VAULT)" "ansible-vault encrypt" \
        bash -c "head -c 14 '$ANSIBLE_DIR/group_vars/all/vault.yml' | grep -q '^\\\$ANSIBLE_VAULT'"
    critere "Aucun secret en clair dans le projet (mdp/password/secret)" "tout secret dans le coffre, référencé par {{ vault_… }}" \
        bash -c "! grep -rEn --exclude=.vault-pass --exclude-dir=.git '^[[:space:]]*[a-z_]*(mdp|password|passwd|secret)[a-z_]*:[[:space:]]*[\"'\\'']?[A-Za-z0-9]{6,}' '$ANSIBLE_DIR' | grep -v '{{'"
    info "Idempotence : ansible-playbook site.yml (quelques minutes)…"
    recap=$(cd "$ANSIBLE_DIR" && ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" ansible-playbook site.yml 2>&1 | sed -n '/PLAY RECAP/,$p')
    critere "Idempotence : une seconde exécution ne change RIEN (changed=0, failed=0 partout)" "command/shell : creates:, changed_when: ; mots de passe hachés avec un sel fixe" \
        eval 'grep -q "ok=" <<< "$recap" && ! grep -Eq "changed=[1-9]|failed=[1-9]|unreachable=[1-9]" <<< "$recap"'
    grep -E 'changed=[1-9]|failed=[1-9]' <<< "$recap" | sed 's/^/      /'
fi

if [ "$SINISTRE" -eq 1 ]; then
    section "Palier 3 — Reprise après sinistre"
    f=/var/lib/fil-rouge/sinistre
    if [ ! -r "$f" ]; then
        rouge "Aucun sinistre enregistré" "lancer outils/sinistre.sh depuis l'hôte du lab"
    else
        debut=0; minimum_attendu=0; avant=0
        # shellcheck source=/dev/null
        . "$f"      # debut, minimum_attendu, avant
        n=$(sur db1 "runuser -u postgres -- psql -tAc 'select count(*) from orders where created_at <= to_timestamp($debut)' marche" 2>/dev/null || echo 0)
        duree=$(( ($(date +%s) - debut) / 60 ))
        critere "Données restaurées : $n commandes antérieures au sinistre (au moins $minimum_attendu, sur $avant avant le sinistre)" \
            "restaurer le DERNIER instantané d'avant le sinistre" test "${n:-0}" -ge "$minimum_attendu"
        critere "Perte de données dans l'objectif (RPO ≤ 1 h) : $((avant - n)) commandes perdues" "timer horaire" \
            test "${n:-0}" -ge "$minimum_attendu"
        critere "Service rétabli en $duree min (RTO ≤ 30 min)" "runbook, Ansible, restauration" test "$duree" -le 30
    fi
fi

printf '\n  Score : %d/%d\n' "$OK" $((OK + KO))
if [ "$KO" -eq 0 ]; then printf '  \033[32m🎉 Palier 3 validé.\033[0m\n'; exit 0; fi
exit 1
