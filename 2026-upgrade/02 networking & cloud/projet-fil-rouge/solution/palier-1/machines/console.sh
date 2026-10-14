#!/bin/bash
# console — votre poste d'administration, à Lomé. Il rejoint le VPC par un VPN WireGuard
# « d'accès distant » en SPLIT TUNNEL : seul le trafic vers 10.0.0.0/16 (et le VPN lui-même)
# emprunte le tunnel ; le reste sort normalement par le FAI.
# usage : console.sh <clé publique WireGuard de la passerelle>
set -euo pipefail
PAIR=${1:?clé publique de la passerelle}

install -d -m 700 /etc/wireguard
[ -f /etc/wireguard/prive.key ] || (umask 077; wg genkey > /etc/wireguard/prive.key)
wg pubkey < /etc/wireguard/prive.key > /etc/wireguard/public.key
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.99.0.2/24
PrivateKey = $(cat /etc/wireguard/prive.key)
# DNS du VPC pour les noms internes (app1.marche.test…) : voir le README (split DNS)

[Peer]  # la passerelle du VPC
PublicKey = $PAIR
Endpoint = 203.0.113.10:51820
AllowedIPs = 10.0.0.0/16, 10.99.0.0/24
PersistentKeepalive = 25
EOF
chmod 600 /etc/wireguard/wg0.conf
systemctl enable -q wg-quick@wg0 && systemctl restart wg-quick@wg0

# Clé SSH de l'administrateur (déposée sur chaque machine du VPC, comme à leur création)
[ -f /root/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C "admin@console" -f /root/.ssh/id_ed25519
echo "console prête — clé publique WireGuard : $(cat /etc/wireguard/public.key)"
