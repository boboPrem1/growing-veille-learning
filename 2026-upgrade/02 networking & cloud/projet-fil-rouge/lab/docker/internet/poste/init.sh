#!/bin/bash
# Un poste à Lomé (client ou console) : son FAI lui donne une route et un résolveur DNS.
# Au Palier 3, le client est abonné à TogoNet (198.18.30.0/24) : « lab.sh up 3 » écrit l'adresse de
# son routeur dans /etc/lab/fai, et c'est par lui que passe tout son trafic.
set -e
ip route replace default via "$(cat /etc/lab/fai 2>/dev/null || echo 192.0.2.1)"
printf 'nameserver 192.0.2.35\n' > /etc/resolv.conf

# annonce ARP gratuite de chaque adresse : une machine recréée change de MAC, ses voisins l'apprennent
# tout de suite au lieu d'écrire à l'ancienne jusqu'à expiration de leur cache (jusqu'à ~50 s)
ip -4 -o addr show scope global | while read -r _ i _ a _; do arping -q -U -c 2 -w 3 -I "${i%%@*}" "${a%/*}" & done; wait || true
