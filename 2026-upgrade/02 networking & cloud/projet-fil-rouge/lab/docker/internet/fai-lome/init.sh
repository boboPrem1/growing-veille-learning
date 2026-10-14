#!/bin/bash
# TogoNet — AS 65030 : le fournisseur d'accès des clients de Lomé (Palier 3). Ses clients sont dans
# 198.18.30.0/24 (le client du lab y est en .50). Il achète du transit à TransAtlantique (AS 65010,
# sur le réseau de Lomé) et se raccorde au point d'échange TGIX (réseau 198.18.1.0/24) : tout ce qu'il
# y apprend est local, gratuit et direct — il le PRÉFÈRE au transit (local-preference).
set -e
sysctl -qw net.ipv4.ip_forward=1
nft -f - <<'NFT'
flush ruleset
table inet togonet {
    chain transit {
        type filter hook forward priority 0; policy accept;
        iifname "togonet" ip saddr != 198.18.30.0/24 counter drop                     # BCP 38
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter drop          # RFC 1918
    }
}
NFT
install -m 640 -o frr -g frr /lab/frr.conf /etc/frr/frr.conf
sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
systemctl enable -q frr && systemctl restart frr

# annonce ARP gratuite de chaque adresse : une machine recréée change de MAC, ses voisins l'apprennent
# tout de suite au lieu d'écrire à l'ancienne jusqu'à expiration de leur cache (jusqu'à ~50 s)
ip -4 -o addr show scope global | while read -r _ i _ a _; do arping -q -U -c 2 -w 3 -I "${i%%@*}" "${a%/*}" & done; wait || true
