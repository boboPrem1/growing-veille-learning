#!/bin/bash
# La dorsale de l'Internet du lab : relie Lomé (192.0.2.0/24) et l'Europe (203.0.113.0/24),
# et sort vers le vrai Internet (NAT). Comme un vrai opérateur :
#  - elle ne route QUE des adresses publiques : une adresse privée (10.x) n'a rien à faire ici ;
#  - elle jette les paquets dont l'adresse source est usurpée (BCP 38) ;
#  - la traversée Lomé ↔ Europe prend du temps : ~60 ms dans chaque sens.
# Au Palier 3, elle devient ce qu'elle est vraiment : un OPÉRATEUR DE TRANSIT, « TransAtlantique »,
# AS 65010, qui parle BGP avec ses clients (Marché, AS 64500 ; TogoNet, AS 65030) et avec un autre
# transitaire (OuestNet, AS 65020) — voir frr.conf. Aux Paliers 1 et 2, aucune session ne s'établit.
set -e
sysctl -qw net.ipv4.ip_forward=1
nft -f - <<'NFT'
flush ruleset
table inet dorsale {
    counter usurpees {}
    # BCP 38 : chaque client ne peut émettre qu'avec SES adresses — celles qu'il a le droit d'annoncer
    # (Marché, au Palier 3 : son préfixe 198.51.100.0/24 ; TogoNet : ses clients, 198.18.30.0/24)
    set lome_legitimes   { type ipv4_addr; flags interval; elements = { 192.0.2.0/24, 198.51.100.0/24, 198.18.30.0/24 } }
    set europe_legitimes { type ipv4_addr; flags interval; elements = { 203.0.113.0/24, 198.51.100.0/24 } }
    chain marquage {
        # ce qui TRAVERSE l'océan : marqué selon le côté d'où il arrive (1 : vient de Lomé)
        type filter hook prerouting priority mangle;
        iifname "lome" meta mark set 0x1
        iifname { "europe", "interco" } meta mark set 0x2
    }
    chain transit {
        type filter hook forward priority 0; policy accept;
        iifname "lome"   ip saddr != @lome_legitimes   counter name usurpees drop
        iifname "europe" ip saddr != @europe_legitimes counter name usurpees drop
        # les adresses privées ne se routent pas sur Internet (RFC 1918)
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter drop
    }
}
table ip sortie {
    chain postrouting {
        type nat hook postrouting priority 100;
        oifname "sortie" masquerade
    }
}
NFT
# Le câble sous-marin : 60 ms dans chaque sens, pour ce qui TRAVERSE l'océan seulement, et une
# CAPACITÉ limitée (20 Mbit/s par sens) avec, comme souvent chez un opérateur, un GROS tampon (1 200
# paquets ≈ 0,7 s quand il est plein) : de quoi observer la file d'attente gonfler (« bufferbloat »).
# (≈ 120 ms aller-retour Lomé ↔ Europe ; le routeur du FAI, lui, répond sans délai : ses propres
#  réponses ne sont pas marquées.) Le tri se fait sur la marque (le côté d'arrivée), pas sur
# l'adresse source : au Palier 3, des préfixes annoncés en BGP traversent aussi.
ocean() {   # ocean <interface de sortie> <marque de ce qui vient d'en face>
    ip link show "$1" >/dev/null 2>&1 || return 0
    tc qdisc replace dev "$1" root handle 1: prio bands 4 priomap 1 2 2 2 1 2 0 0 1 1 1 1 1 1 1 1
    tc qdisc replace dev "$1" parent 1:4 handle 40: netem delay 60ms rate "${CAPACITE:-20mbit}" limit 1200
    tc filter replace dev "$1" parent 1: protocol ip prio 1 handle "$2" fw flowid 1:4
}
ocean lome    2
ocean europe  1
ocean interco 1

# l'interface de rejet du RTBH (voir frr.conf) : une interface factice, qui jette tout ce qu'on lui confie
ip link show trou-noir >/dev/null 2>&1 || ip link add trou-noir type dummy
ip addr replace 198.18.254.1/30 dev trou-noir && ip link set trou-noir up

# BGP (FRR) : la configuration de l'opérateur ; les sessions ne s'établissent qu'au Palier 3
install -m 640 -o frr -g frr /lab/frr.conf /etc/frr/frr.conf
sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
systemctl enable -q frr && systemctl restart frr

# annonce ARP gratuite de chaque adresse : une machine recréée change de MAC, ses voisins l'apprennent
# tout de suite au lieu d'écrire à l'ancienne jusqu'à expiration de leur cache (jusqu'à ~50 s)
ip -4 -o addr show scope global | while read -r _ i _ a _; do arping -q -U -c 2 -w 3 -I "${i%%@*}" "${a%/*}" & done; wait || true
