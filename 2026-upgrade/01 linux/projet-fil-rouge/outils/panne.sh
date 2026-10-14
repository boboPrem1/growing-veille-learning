#!/bin/bash
# panne.sh — injecteur de pannes du projet fil rouge Linux. À lancer EN ROOT sur la machine visée.
#
#   sudo ./panne.sh liste [1|2]            catalogue des pannes d'un palier
#   sudo ./panne.sh <nom>                  injecter une panne connue (entraînement)
#   sudo ./panne.sh aveugle <palier> [n]   n pannes tirées au sort (défaut 2), sans dire lesquelles
#   sudo ./panne.sh revele                 révéler les pannes du tirage à l'aveugle
#   sudo ./panne.sh annuler <nom>          dernier recours : annuler une panne (= manche perdue)
#
# Règle du jeu : après une injection, on diagnostique avec les commandes du cours, on corrige
# À LA MAIN, et on note la cause racine. « annuler » ne sert qu'à débloquer une situation.
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer en root." >&2; exit 2; }

TICKET=/root/.panne-aveugle
ADMIN=$(getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -vx ubuntu | head -1)

# nom|palier|description (révélée après coup)|dernier palier où elle a un sens (vide = tous)
CATALOGUE=(
  "service-arrete|1|Le service payments a été arrêté ET désactivé (au Palier 2 : l'instance marche@payments est masquée)."
  "code-illisible|1|/opt/marche/app est passé en 700 : le compte marche ne peut plus lire le code."
  "nginx-casse|1|Un point-virgule manque dans le site nginx, et nginx a été redémarré."
  "port-vole|1|Un intrus (unité « intrus-8000 ») occupe 127.0.0.1:8000 : le gateway ne peut plus démarrer."
  "secret-casse|1|Le mot de passe de DATABASE_URL dans /etc/marche/marche.env est faux."
  "cle-ssh|1|~/.ssh de l'administrateur est passé en 777 : sshd refuse la clé sans rien dire au client."
  "cron-casse|1|La colonne utilisateur a disparu des lignes de /etc/cron.d/marche.|1"
  "pare-feu-80|1|Une règle ufw « deny » depuis 10.10.10.1 (la passerelle : tout ce qui vient de l'hôte) a été insérée en tête.|1"
  "hosts-empoisonne|1|/etc/hosts envoie archive.ubuntu.com et security.ubuntu.com vers 192.0.2.1."
  "cpu-fou|2|Un thread du service orders brûle un cœur CPU en boucle (endpoint de chaos)."
  "fuite-memoire|2|Le gateway garde 128 Ko de mémoire à chaque requête (endpoint de chaos)."
  "base-lente|2|Chaque commande attend 800 ms dans PostgreSQL (pg_sleep, endpoint de chaos)."
  "fichier-fantome|2|Un export bloqué (unité « marche-export ») garde ouvert un gros fichier supprimé sur le volume des sauvegardes."
  "inodes|2|Des dizaines de milliers de fichiers vides ont épuisé les inodes du volume des sauvegardes."
  "descripteurs|2|Un override systemd limite le gateway à 32 descripteurs de fichiers (LimitNOFILE)."
  "sudoers-casse|2|Une erreur de syntaxe dans /etc/sudoers.d/marche-deploy : sudo ignore la ligne, deploy ne peut plus déployer (et sudo affiche l'erreur à chaque appel)."
  "timer-arrete|2|Le timer de sauvegarde a été désactivé : plus aucune sauvegarde."
  "nft-drop-web|2|Une règle nftables jette le trafic entrant sur 80 et 443."
)

champ() { cut -d'|' -f"$2" <<< "$1"; }
existe() { local l; for l in "${CATALOGUE[@]}"; do [[ $(champ "$l" 1) == "$1" ]] && return 0; done; return 1; }
chaos() { curl -fsS -m 5 -X POST -H 'Content-Type: application/json' -d "$2" "http://127.0.0.1:$1/admin/chaos" >/dev/null; }

# ------------------------------------------------------------------ injections
p_service-arrete()  { if systemctl cat marche@.service >/dev/null 2>&1; then systemctl mask --now marche@payments 2>/dev/null
                      else systemctl disable --now marche-payments 2>/dev/null; fi; }
p_code-illisible()  { d=/opt/marche/current; [ -e "$d" ] || d=/opt/marche/app
                      chmod 700 "$(readlink -f "$d")"; systemctl restart 'marche*' 2>/dev/null || true; }
p_nginx-casse()     { f=/etc/nginx/sites-available/marche; cp -a "$f" /root/.panne-nginx.bak
                      sed -i -E '0,/proxy_pass[^;]*;/s/(proxy_pass[^;]*);/\1/' "$f"
                      systemctl restart nginx 2>/dev/null || true; }
p_port-vole()       { systemctl stop marche-gateway 'marche@gateway' 2>/dev/null
                      systemd-run --unit=intrus-8000 --quiet python3 -m http.server 8000 --bind 127.0.0.1
                      sleep 1; systemctl start marche-gateway 'marche@gateway' 2>/dev/null || true; }
p_secret-casse()    { f=/etc/marche/marche.env; cp -a "$f" /root/.panne-env.bak
                      sed -i -E 's#(postgresql://[^:]+:)[^@]+@#\1mauvais-mot-de-passe@#' "$f"
                      systemctl restart marche-orders 'marche@orders' 2>/dev/null || true; }
p_cle-ssh()         { [ -n "$ADMIN" ] && chmod 777 "$(getent passwd "$ADMIN" | cut -d: -f6)/.ssh"; }
p_cron-casse()      { f=/etc/cron.d/marche; [ -f "$f" ] && cp -a "$f" /root/.panne-cron.bak && sed -i -E 's/^([^#A-Z][^ ]* +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+) +root +/\1  /' "$f"; }
p_pare-feu-80()     { ufw insert 1 deny proto tcp from 10.10.10.1 to any port 80 >/dev/null; }
p_hosts-empoisonne() { printf '192.0.2.1 archive.ubuntu.com security.ubuntu.com  # ajouté\n' >> /etc/hosts; }
p_cpu-fou()         { chaos 8001 '{"cpu_burn": true}'; }
p_fuite-memoire()   { chaos 8000 '{"leak_kb_per_request": 128}'; }
p_base-lente()      { chaos 8001 '{"db_slow_ms": 800}'; }
# Le volume des sauvegardes, et lui seulement : remplir le disque racine remplirait aussi celui de
# l'hôte (pool LXD du VPS, VM de Docker Desktop) et les autres conteneurs qui y vivent.
p_fichier-fantome() { d=/var/backups/marche; mountpoint -q "$d" || { echo "Panne réservée à un volume dédié (Palier 2)" >&2; return 1; }
                      taille=$(( $(df --output=avail -k "$d" | tail -1) * 90 / 100 / 1024 ))
                      systemd-run --unit=marche-export --quiet bash -c                         "exec 3>$d/.export.tmp; fallocate -l ${taille}M $d/.export.tmp || dd if=/dev/zero bs=1M count=$taille >&3 2>/dev/null; rm $d/.export.tmp; exec sleep infinity"; }
p_inodes()          { d=/var/backups/marche; mountpoint -q "$d" || { echo "Panne réservée à un volume dédié (Palier 2)" >&2; return 1; }
                      mkdir -p "$d/.tmp-inodes"; i=0
                      while touch "$d/.tmp-inodes/f$i" 2>/dev/null; do i=$((i + 1)); [ $i -gt 2000000 ] && break; done; }
p_descripteurs()    { u=marche-gateway; systemctl cat marche@gateway >/dev/null 2>&1 && u=marche@gateway
                      mkdir -p "/etc/systemd/system/$u.service.d"
                      printf '[Service]\nLimitNOFILE=32\n' > "/etc/systemd/system/$u.service.d/limites.conf"
                      systemctl daemon-reload; systemctl restart "$u"; }
p_sudoers-casse()   { f=/etc/sudoers.d/marche-deploy
                      if [ -f "$f" ]; then cp -a "$f" /root/.panne-sudoers; sed -i 's/NOPASSWD:/NOPASSWD/' "$f"
                      else printf 'Defaults  env_keep += "PANNE\n' > /etc/sudoers.d/zz-panne; chmod 440 /etc/sudoers.d/zz-panne; fi; }
p_timer-arrete()    { systemctl disable --now marche-backup.timer 2>/dev/null; }
p_nft-drop-web()    { nft add table inet panne; nft 'add chain inet panne entree { type filter hook input priority -10 ; }'
                      nft add rule inet panne entree tcp dport '{ 80, 443 }' drop; }

# ------------------------------------------------------------------ annulations (dernier recours)
a_service-arrete()  { if systemctl cat marche@.service >/dev/null 2>&1; then systemctl unmask marche@payments && systemctl start marche@payments
                      else systemctl enable --now marche-payments; fi; }
a_code-illisible()  { d=/opt/marche/current; [ -e "$d" ] || d=/opt/marche/app; chmod 755 "$(readlink -f "$d")"; systemctl restart 'marche*'; }
a_nginx-casse()     { cp -a /root/.panne-nginx.bak /etc/nginx/sites-available/marche && systemctl restart nginx; }
a_port-vole()       { systemctl stop intrus-8000; systemctl restart marche-gateway 'marche@gateway' 2>/dev/null; }
a_secret-casse()    { cp -a /root/.panne-env.bak /etc/marche/marche.env; systemctl restart marche-orders 'marche@orders' 2>/dev/null; }
a_cle-ssh()         { chmod 700 "$(getent passwd "$ADMIN" | cut -d: -f6)/.ssh"; }
a_cron-casse()      { cp -a /root/.panne-cron.bak /etc/cron.d/marche; }
a_pare-feu-80()     { ufw delete deny proto tcp from 10.10.10.1 to any port 80 >/dev/null; }
a_hosts-empoisonne() { contenu=$(grep -v '# ajouté$' /etc/hosts)   # réécriture EN PLACE :
                       printf '%s\n' "$contenu" > /etc/hosts; }          # /etc/hosts peut être un montage
a_cpu-fou()         { chaos 8001 '{"cpu_burn": false}'; }
a_fuite-memoire()   { chaos 8000 '{"leak_kb_per_request": 0}'; }
a_base-lente()      { chaos 8001 '{"db_slow_ms": 0}'; }
a_fichier-fantome() { systemctl stop marche-export; }
a_inodes()          { rm -rf /var/backups/marche/.tmp-inodes; }
a_descripteurs()    { rm -f /etc/systemd/system/marche-gateway.service.d/limites.conf /etc/systemd/system/marche@gateway.service.d/limites.conf
                      systemctl daemon-reload; systemctl restart marche-gateway 'marche@gateway' 2>/dev/null; }
a_sudoers-casse()   { rm -f /etc/sudoers.d/zz-panne; [ ! -f /root/.panne-sudoers ] || cp -a /root/.panne-sudoers /etc/sudoers.d/marche-deploy; }
a_timer-arrete()    { systemctl enable --now marche-backup.timer; }
a_nft-drop-web()    { nft delete table inet panne; }

# ------------------------------------------------------------------ commandes
case "${1:-}" in
    liste)
        for l in "${CATALOGUE[@]}"; do
            [[ -z "${2:-}" || $(champ "$l" 2) == "$2" ]] && printf 'P%s  %-18s %s\n' "$(champ "$l" 2)" "$(champ "$l" 1)" "$(champ "$l" 3)"
        done ;;
    aveugle)
        palier=${2:?palier ?}; n=${3:-2}
        [ -e "$TICKET" ] && { echo "Un tirage est déjà en cours : « $0 revele » d'abord." >&2; exit 1; }
        mapfile -t candidats < <(for l in "${CATALOGUE[@]}"; do
            max=$(champ "$l" 4)
            (( $(champ "$l" 2) <= palier )) && (( palier <= ${max:-99} )) && champ "$l" 1
        done | shuf -n "$n")
        for p in "${candidats[@]}"; do "p_$p" >/dev/null 2>&1 || true; done
        printf '%s|%s\n' "$(date '+%F %T')" "${candidats[*]}" | base64 > "$TICKET"
        echo "🔥 $n panne(s) injectée(s) à $(date +%T). Diagnostiquez, corrigez, notez les causes racines, puis : $0 revele" ;;
    revele)
        [ -e "$TICKET" ] || { echo "Aucun tirage en cours."; exit 0; }
        IFS='|' read -r quand pannes < <(base64 -d "$TICKET")
        echo "Tirage du $quand :"
        for p in $pannes; do
            for l in "${CATALOGUE[@]}"; do [[ $(champ "$l" 1) == "$p" ]] && echo "  • $p — $(champ "$l" 3)"; done
        done
        rm -f "$TICKET" ;;
    annuler)
        p=${2:?panne ?}; existe "$p" || { echo "Panne inconnue : $p" >&2; exit 1; }
        "a_$p" && echo "↩ $p annulée." ;;
    ""|-h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
        existe "$1" || { echo "Panne inconnue : $1 (voir : $0 liste)" >&2; exit 1; }
        "p_$1" && echo "🔥 Panne « $1 » injectée à $(date +%T)." ;;
esac
