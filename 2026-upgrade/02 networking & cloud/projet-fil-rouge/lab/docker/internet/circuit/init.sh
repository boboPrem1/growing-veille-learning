#!/bin/bash
# Le circuit dédié Lomé ↔ Europe (Palier 3) : l'équivalent d'un Direct Connect / Interconnect /
# ExpressRoute, loué à un opérateur. Il ne passe PAS par Internet : pas de transitaire, pas de
# congestion des autres, une capacité réservée (100 Mbit/s) et un délai stable — mais la physique
# reste la physique : ≈ 55 ms dans chaque sens (câble plus direct que celui de TransAtlantique).
# C'est un routeur de l'opérateur, pas un câble : votre passerelle d'Europe le joint en
# 198.18.9.1 (réseau fibre-europe, 198.18.9.0/29), celle de Lomé en 198.18.9.9 (fibre-lome,
# 198.18.9.8/29). Il route tout ce qu'on lui confie entre les deux — adresses privées comprises :
# c'est VOTRE circuit.
set -e
sysctl -qw net.ipv4.ip_forward=1
sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0
for i in fibre-europe fibre-lome; do
    sysctl -qw "net.ipv4.conf.$i.rp_filter=0"
    tc qdisc replace dev "$i" root netem delay 55ms rate 100mbit limit 300
done
# Un circuit POINT À POINT : tout ce qui entre d'un côté ressort de l'autre, quelle que soit la
# destination (vos adresses privées, vos VPC : le circuit n'a pas à les connaître). L'extrémité
# d'Europe est 198.18.9.2, celle de Lomé 198.18.9.10 (les adresses que vos passerelles y reçoivent).
# (Première version : le circuit routait selon SA table — il ne connaissait que ses deux réseaux, et
#  jetait tout le trafic entre VPC ; seules les sessions BGP, d'une extrémité à l'autre, passaient.)
ip rule show | grep -q 'iif fibre-europe lookup 101' || ip rule add iif fibre-europe lookup 101 priority 101
ip rule show | grep -q 'iif fibre-lome lookup 102' || ip rule add iif fibre-lome lookup 102 priority 102
# Une interface qui tombe emporte ses routes, et ne les rend pas en revenant. Un vrai circuit, rétabli,
# refait passer le trafic : une petite boucle remet les deux routes dès que les interfaces sont là.
# (Vécu : après une coupure « ip link set down / up », BFD et BGP remontaient — ils se parlent sur
#  les réseaux directement connectés — mais plus un paquet des VPC ne passait d'Europe vers Lomé :
#  une panne grise, due au lab lui-même.)
cat > /usr/local/sbin/circuit-routes <<'EOF'
#!/bin/bash
while :; do
    ip route show table 101 | grep -q default || ip route replace default via 198.18.9.10 dev fibre-lome table 101 2>/dev/null
    ip route show table 102 | grep -q default || ip route replace default via 198.18.9.2 dev fibre-europe table 102 2>/dev/null
    sleep 1
done
EOF
chmod 755 /usr/local/sbin/circuit-routes
printf '[Unit]\nDescription=Le circuit rétabli refait passer le trafic\n[Service]\nExecStart=/usr/local/sbin/circuit-routes\nRestart=always\n' \
    > /etc/systemd/system/circuit-routes.service
systemctl daemon-reload && systemctl restart circuit-routes

# annonce ARP gratuite de chaque adresse : une machine recréée change de MAC, ses voisins l'apprennent
# tout de suite au lieu d'écrire à l'ancienne jusqu'à expiration de leur cache (jusqu'à ~50 s)
ip -4 -o addr show scope global | while read -r _ i _ a _; do arping -q -U -c 2 -w 3 -I "${i%%@*}" "${a%/*}" & done; wait || true
