#!/bin/bash
# OuestNet — AS 65020 : un second opérateur de transit (Palier 3), moins cher… et moins bon : son câble
# fait un détour (≈ 90 ms dans chaque sens), et il PERD des paquets (0,5 %). De quoi choisir ses
# transitaires en connaissance de cause, et comparer les contrôles de congestion TCP (CUBIC, BBR).
#   europe-b 198.18.2.0/24 : ses clients en Europe ; lome-b 198.18.3.0/24 : ses clients à Lomé ;
#   interco  198.18.0.0/29 : le lien de peering avec TransAtlantique (AS 65010), en Europe.
set -e
sysctl -qw net.ipv4.ip_forward=1
nft -f - <<'NFT'
flush ruleset
table inet ouestnet {
    set clients { type ipv4_addr; flags interval; elements = { 198.18.2.0/24, 198.18.3.0/24, 198.51.100.0/24 } }
    chain marquage {
        type filter hook prerouting priority mangle;
        iifname "lome-b" meta mark set 0x1
        iifname { "europe-b", "interco" } meta mark set 0x2
    }
    chain transit {
        type filter hook forward priority 0; policy accept;
        iifname { "europe-b", "lome-b" } ip saddr != @clients counter drop       # BCP 38
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter drop     # RFC 1918
    }
}
NFT
cable() {   # cable <interface de sortie> <marque de ce qui vient d'en face>
    tc qdisc replace dev "$1" root handle 1: prio bands 4 priomap 1 2 2 2 1 2 0 0 1 1 1 1 1 1 1 1
    tc qdisc replace dev "$1" parent 1:4 handle 40: netem delay 90ms loss 0.5% rate 50mbit limit 1000
    tc filter replace dev "$1" parent 1: protocol ip prio 1 handle "$2" fw flowid 1:4
}
cable lome-b   2
cable europe-b 1
cable interco  1
install -m 640 -o frr -g frr /lab/frr.conf /etc/frr/frr.conf
sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
systemctl enable -q frr && systemctl restart frr

# annonce ARP gratuite de chaque adresse : une machine recréée change de MAC, ses voisins l'apprennent
# tout de suite au lieu d'écrire à l'ancienne jusqu'à expiration de leur cache (jusqu'à ~50 s)
ip -4 -o addr show scope global | while read -r _ i _ a _; do arping -q -U -c 2 -w 3 -I "${i%%@*}" "${a%/*}" & done; wait || true
