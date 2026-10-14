#!/bin/bash
# panne-infra.sh — pannes du Palier 3 (plusieurs machines), à lancer SUR ctl.
#
#   ./panne-infra.sh liste                 le catalogue
#   ./panne-infra.sh <nom>                 injecter une panne connue (entraînement)
#   ./panne-infra.sh aveugle [n]           n pannes au hasard (défaut 2), sans dire lesquelles
#   ./panne-infra.sh revele                révéler le tirage
#   ./panne-infra.sh annuler <nom>         dernier recours (= manche perdue)
#
# Règle du jeu : diagnostiquer, corriger — de préférence en relançant Ansible, qui doit
# ramener l'état décrit — et noter la cause racine dans INCIDENTS.md.
set -uo pipefail

declare -A IP=([lb1]=10.10.10.11 [lb2]=10.10.10.12 [web1]=10.10.10.21 [web2]=10.10.10.22 [db1]=10.10.10.31 [bak1]=10.10.10.41)
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
sur() { local m=$1; shift; "${SSH[@]}" "ubuntu@${IP[$m]}" "sudo -n bash -c $(printf '%q' "$*")"; }
TICKET=$HOME/.panne-infra-aveugle
LIVRAISON=${LIVRAISON:-/srv/projet/livraison}

CATALOGUE=(
  "vrrp-bloque|lb2 jette les annonces VRRP de lb1 : chacun se croit seul, l'IP virtuelle est portée DEUX fois (split-brain)."
  "serveur-draine|web2 a été mis en maintenance dans HAProxy (commande « disable server ») sur les deux répartiteurs."
  "base-refuse-web2|La ligne de web2 a disparu du pg_hba.conf de db1 : web2 ne joint plus la base."
  "derive-nginx|Quelqu'un a modifié à la main le site nginx de web2 (proxy_read_timeout 1s) : la configuration a dérivé."
  "cle-wg|La clé privée WireGuard de db1 a été régénérée : le tunnel est mort, les sauvegardes échouent."
  "version-divergente|web2 a été redéployé à la main en 1.0.0 : les deux serveurs ne servent plus la même version."
  "keepalived-arrete|keepalived a été arrêté et désactivé sur lb1 : tout marche… sans aucune redondance."
  "sauvegarde-arretee|Le timer de sauvegarde de db1 a été désactivé : plus aucune sauvegarde depuis."
)
champ() { cut -d'|' -f"$2" <<< "$1"; }
existe() { local l; for l in "${CATALOGUE[@]}"; do [[ $(champ "$l" 1) == "$1" ]] && return 0; done; return 1; }

# ------------------------------------------------------------------ injections
p_vrrp-bloque()      { sur lb2 "nft add table inet panne; nft 'add chain inet panne entree { type filter hook input priority -10 ; }'; nft add rule inet panne entree ip protocol vrrp drop"; }
p_serveur-draine()   { local lb; for lb in lb1 lb2; do sur "$lb" "echo 'disable server marche_web/web2' | socat stdio /run/haproxy/admin.sock"; done; }
p_base-refuse-web2() { sur db1 "f=\$(ls /etc/postgresql/*/main/pg_hba.conf); cp -a \$f /root/.panne-pg_hba; sed -i '/10\.10\.10\.22/d' \$f; systemctl reload 'postgresql@*'"; }
p_derive-nginx()     { sur web2 "cp -a /etc/nginx/sites-available/marche /root/.panne-nginx; sed -i 's/proxy_read_timeout [0-9]*s/proxy_read_timeout 1s/' /etc/nginx/sites-available/marche; nginx -t && systemctl reload nginx"; }
p_cle-wg()           { sur db1 "cp -a /etc/wireguard/prive.key /root/.panne-wg; umask 077; wg genkey > /etc/wireguard/prive.key; sed -i \"s#^PrivateKey = .*#PrivateKey = \$(cat /etc/wireguard/prive.key)#\" /etc/wireguard/wg0.conf; systemctl restart wg-quick@wg0"; }
p_version-divergente() {
    scp -q -o BatchMode=yes "$LIVRAISON/marche-1.0.0.tar.gz" "$LIVRAISON/marche-1.0.0.tar.gz.sha256" "ubuntu@${IP[web2]}:/tmp/" \
      && sur web2 "mv /tmp/marche-1.0.0.tar.gz* /opt/marche/livraison/ && /usr/local/sbin/marchectl deploy /opt/marche/livraison/marche-1.0.0.tar.gz >/dev/null"
}
p_keepalived-arrete()  { sur lb1 "systemctl disable --now keepalived"; }
p_sauvegarde-arretee() { sur db1 "systemctl disable --now marche-sauvegarde.timer"; }

# ------------------------------------------------------------------ annulations (dernier recours)
a_vrrp-bloque()      { sur lb2 "nft delete table inet panne"; }
a_serveur-draine()   { local lb; for lb in lb1 lb2; do sur "$lb" "echo 'enable server marche_web/web2' | socat stdio /run/haproxy/admin.sock"; done; }
a_base-refuse-web2() { sur db1 "cp -a /root/.panne-pg_hba \$(ls /etc/postgresql/*/main/pg_hba.conf) && systemctl reload 'postgresql@*'"; }
a_derive-nginx()     { sur web2 "cp -a /root/.panne-nginx /etc/nginx/sites-available/marche && systemctl reload nginx"; }
a_cle-wg()           { sur db1 "cp -a /root/.panne-wg /etc/wireguard/prive.key; sed -i \"s#^PrivateKey = .*#PrivateKey = \$(cat /etc/wireguard/prive.key)#\" /etc/wireguard/wg0.conf; systemctl restart wg-quick@wg0"; }
a_version-divergente() { sur web2 "/usr/local/sbin/marchectl rollback >/dev/null && rm -rf /opt/marche/releases/1.0.0"; }
a_keepalived-arrete()  { sur lb1 "systemctl enable --now keepalived"; }
a_sauvegarde-arretee() { sur db1 "systemctl enable --now marche-sauvegarde.timer"; }

# ------------------------------------------------------------------ commandes
case "${1:-}" in
    liste) for l in "${CATALOGUE[@]}"; do printf 'P3  %-20s %s\n' "$(champ "$l" 1)" "$(champ "$l" 2)"; done ;;
    aveugle)
        n=${2:-2}
        [ -e "$TICKET" ] && { echo "Un tirage est déjà en cours : « $0 revele » d'abord." >&2; exit 1; }
        mapfile -t tirage < <(for l in "${CATALOGUE[@]}"; do champ "$l" 1; done | shuf -n "$n")
        for p in "${tirage[@]}"; do "p_$p" >/dev/null 2>&1 || true; done
        printf '%s|%s\n' "$(date '+%F %T')" "${tirage[*]}" | base64 > "$TICKET"
        echo "🔥 $n panne(s) injectée(s) à $(date +%T), quelque part dans l'infrastructure. À vous." ;;
    revele)
        [ -e "$TICKET" ] || { echo "Aucun tirage en cours."; exit 0; }
        IFS='|' read -r quand pannes < <(base64 -d "$TICKET")
        echo "Tirage du $quand :"
        for p in $pannes; do for l in "${CATALOGUE[@]}"; do [[ $(champ "$l" 1) == "$p" ]] && echo "  • $p — $(champ "$l" 2)"; done; done
        rm -f "$TICKET" ;;
    annuler)
        p=${2:?panne ?}; existe "$p" || { echo "Panne inconnue : $p" >&2; exit 1; }
        "a_$p" && echo "↩ $p annulée." ;;
    ""|-h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
        existe "$1" || { echo "Panne inconnue : $1 (voir : $0 liste)" >&2; exit 1; }
        "p_$1" && echo "🔥 Panne « $1 » injectée à $(date +%T)." ;;
esac
