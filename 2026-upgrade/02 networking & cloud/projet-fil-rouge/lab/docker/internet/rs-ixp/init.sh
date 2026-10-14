#!/bin/bash
# Le serveur de routes de TGIX, le point d'échange Internet de Lomé (Palier 3) — AS 65100.
# Au lieu d'ouvrir une session avec CHAQUE autre membre, chaque membre en ouvre UNE avec le serveur
# de routes, qui redistribue les annonces de chacun à tous… sans se mettre sur le chemin : il ne
# s'ajoute pas au chemin d'AS, et garde le « next-hop » du membre d'origine. Le TRAFIC va donc
# directement d'un membre à l'autre sur le réseau de l'IXP ; seul le routage passe par lui.
#   ixp 198.18.1.0/24 : le réseau d'échange (un commutateur partagé par les membres)
set -e
install -m 640 -o frr -g frr /lab/frr.conf /etc/frr/frr.conf
sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
systemctl enable -q frr && systemctl restart frr

# annonce ARP gratuite de chaque adresse : une machine recréée change de MAC, ses voisins l'apprennent
# tout de suite au lieu d'écrire à l'ancienne jusqu'à expiration de leur cache (jusqu'à ~50 s)
ip -4 -o addr show scope global | while read -r _ i _ a _; do arping -q -U -c 2 -w 3 -I "${i%%@*}" "${a%/*}" & done; wait || true
