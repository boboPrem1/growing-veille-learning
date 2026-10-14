#!/bin/bash
# commun.sh — fonctions partagées par les rôles (sourcé par chacun d'eux).
# Les paramètres de la machine sont dans /lab/parametres.sh, écrit par Terraform.
set -euo pipefail
# shellcheck source=/dev/null
. /lab/parametres.sh

# lien <interface> <adresse IPv4/masque ou ""> <passerelle IPv4 ou ""> <adresse IPv6/64 ou "">
#   configure une interface fournie par le « fournisseur » (adresse Docker conservée)
lien() {
    local i=$1 a4=$2 gw=$3 a6=$4
    {
        printf '[Match]\nName=%s\n[Network]\nKeepConfiguration=yes\n' "$i"
        [ -z "$a4" ] || printf 'Address=%s\n' "$a4"
        [ -z "$gw" ] || printf 'Gateway=%s\n' "$gw"
        [ -z "$a6" ] || printf 'Address=%s\nIPv6AcceptRA=yes\n' "$a6"
        [ -n "$a6" ] || printf 'LinkLocalAddressing=no\n'
    } > "/etc/systemd/network/10-$i.network"
}

# vlan <id> <adresse IPv4/masque> <passerelle IPv4> <adresse IPv6/64>   (sur le trunk « baie »)
vlan() {
    local v=$1 a4=$2 gw=$3 a6=$4
    printf '[Match]\nName=baie\n[Network]\nKeepConfiguration=yes\nLinkLocalAddressing=no\nVLAN=baie.%s\n' "$v" > /etc/systemd/network/10-baie.network
    printf '[NetDev]\nName=baie.%s\nKind=vlan\n[VLAN]\nId=%s\n' "$v" "$v" > "/etc/systemd/network/20-baie.$v.netdev"
    printf '[Match]\nName=baie.%s\n[Network]\nAddress=%s\nAddress=%s\nGateway=%s\nIPv6AcceptRA=yes\n' \
        "$v" "$a4" "$a6" "$gw" > "/etc/systemd/network/20-baie.$v.network"
}

reseau_pret() {   # reseau_pret <interface> <adresse> : appliquer, puis attendre l'adresse
    systemctl enable -q systemd-networkd && systemctl restart systemd-networkd
    for _ in $(seq 40); do ip -br addr show "$1" 2>/dev/null | grep -q "${2%/*}" && { annoncer; return 0; }; sleep 0.5; done
    echo "adresse ${2} absente de $1" >&2; return 1
}

# annoncer : ARP gratuit pour chaque adresse IPv4. Une instance REMPLACÉE garde son IP mais pas sa MAC
# (aléatoire) : ses voisins (le routeur, les clients…) ont l'ancienne en cache et envoient DANS LE VIDE
# jusqu'à ce que l'entrée expire — jusqu'à ~50 s (vécu : chaque bascule de région coupait tout ce
# temps-là). L'annonce met les caches à jour tout de suite — ce que font VRRP/keepalived en bascule.
annoncer() {
    ip -4 -o addr show scope global | while read -r _ i _ a _; do
        arping -q -U -c 2 -w 3 -I "${i%%@*}" "${a%/*}" &
    done
    wait || true
}

resolveur() { printf 'nameserver %s\n' "$1" > /etc/resolv.conf; }

# pare_feu <règles> : un security group (avec état) — ce qui est accepté en entrée, rien d'autre
pare_feu() {
    cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet sg {
    chain entree {
        type filter hook input priority filter; policy drop;
        ct state invalid drop
        ct state established,related accept
        iif lo accept
        icmp type { echo-request, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
$1
    }
}
EOF
    nft -c -f /etc/nftables.conf
    systemctl enable -q nftables
    systemctl reload nftables 2>/dev/null || systemctl start nftables
}

# cle_admin : la clé SSH de l'administrateur (déposée par Terraform), comme à la création chez un hébergeur
cle_admin() {
    [ -s /lab/admin.pub ] || return 0
    install -d -m 700 -o ubuntu -g ubuntu ~ubuntu/.ssh
    install -m 600 -o ubuntu -g ubuntu /lab/admin.pub ~ubuntu/.ssh/authorized_keys
}
