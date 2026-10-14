#!/bin/bash
# vlan.sh <vlan> <adresse IPv4 hôte> <suffixe IPv6>
# Une machine de la « baie » : son lien est un trunk, elle vit dans UN VLAN (sous-interface
# étiquetée). Route par défaut : la passerelle du VLAN. IPv6 : adresse fixe + route apprise
# par les annonces de routeur (SLAAC/RA) de la passerelle.
set -euo pipefail
v=${1:?vlan}; ip4=${2:?ip}; ip6=${3:?suffixe ipv6}
net=$((v / 10))
cat > /etc/systemd/network/10-baie.network <<EOF
[Match]
Name=baie
[Network]
KeepConfiguration=yes
LinkLocalAddressing=no
VLAN=baie.$v
EOF
cat > /etc/systemd/network/20-baie.$v.netdev <<EOF
[NetDev]
Name=baie.$v
Kind=vlan
[VLAN]
Id=$v
EOF
cat > /etc/systemd/network/20-baie.$v.network <<EOF
[Match]
Name=baie.$v
[Network]
Address=10.0.$net.$ip4/24
Address=fd00:4d41:5243:$v::$ip6/64
Gateway=10.0.$net.1
IPv6AcceptRA=yes
EOF
systemctl enable -q systemd-networkd && systemctl restart systemd-networkd
for _ in $(seq 20); do ip -br addr show "baie.$v" 2>/dev/null | grep -q "10.0.$net.$ip4" && break; sleep 0.5; done
printf 'nameserver 10.0.%s.1\n' "$net" > /etc/resolv.conf
