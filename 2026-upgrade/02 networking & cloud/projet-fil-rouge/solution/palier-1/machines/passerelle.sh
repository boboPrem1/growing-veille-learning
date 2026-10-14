#!/bin/bash
# passerelle — le routeur du VPC : ce que le cloud appelle « Internet Gateway » + « NAT Gateway »
# + tables de routage + Network ACL + résolveur du VPC (le « .2 » d'AWS) + VPN d'administration.
# Relançable : chaque fichier est réécrit, chaque service rechargé.
set -euo pipefail

# ---------------------------------------------------------------- 1. Interfaces (systemd-networkd)
# « internet », « pub » et « baie » existent déjà (adresses attribuées par le fournisseur) :
# networkd les gère SANS toucher à ces adresses (KeepConfiguration), et y ajoute ce qui manque.
install -d /etc/systemd/network
cat > /etc/systemd/network/10-internet.network <<'EOF'
[Match]
Name=internet
[Network]
Gateway=203.0.113.1
KeepConfiguration=yes
LinkLocalAddressing=no
EOF
cat > /etc/systemd/network/10-pub.network <<'EOF'
[Match]
Name=pub
[Network]
KeepConfiguration=yes
Address=fd00:4d41:5243:1::1/64
IPv6SendRA=yes
[IPv6SendRA]
DNS=fd00:4d41:5243:1::1
[IPv6Prefix]
Prefix=fd00:4d41:5243:1::/64
EOF
# La « baie » est un lien TRUNK : deux VLAN (802.1Q) y circulent, étiquetés.
cat > /etc/systemd/network/10-baie.network <<'EOF'
[Match]
Name=baie
[Network]
KeepConfiguration=yes
LinkLocalAddressing=no
VLAN=baie.20
VLAN=baie.30
EOF
for v in 20 30; do
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
Address=10.0.$((v / 10)).1/24
Address=fd00:4d41:5243:$v::1/64
IPv6SendRA=yes
[IPv6SendRA]
DNS=fd00:4d41:5243:$v::1
[IPv6Prefix]
Prefix=fd00:4d41:5243:$v::/64
EOF
done

# ---------------------------------------------------------------- 2. Routage (noyau)
cat > /etc/sysctl.d/90-routeur.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
# anti-usurpation : un paquet n'est accepté que s'il arrive par l'interface qui mène à sa source
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
sysctl -q --system
systemctl enable -q systemd-networkd
systemctl restart systemd-networkd
networkctl reload 2>/dev/null || true
for _ in $(seq 20); do ip -br addr show baie.30 2>/dev/null | grep -q 10.0.3.1 && break; sleep 0.5; done

# ---------------------------------------------------------------- 3. Pare-feu, NAT, ACL
cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

define VPC      = 10.0.0.0/16
define ADMIN    = 10.99.0.0/24
define APP      = 10.0.2.0/24
define APP6     = fd00:4d41:5243:20::/64
define DB6      = fd00:4d41:5243:30::10
define LB       = 10.0.1.10
define NS1      = 10.0.1.53
define DB       = 10.0.3.10
define STOCKAGE = 10.0.3.20
define PUBLIQUE = 203.0.113.10

# ------------------------------------------------ NAT (Internet Gateway + NAT Gateway)
table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;
        # DNAT : l'adresse publique porte le site (80, 443) et le DNS faisant autorité (53)
        iifname "internet" ip daddr $PUBLIQUE tcp dport { 80, 443 } dnat to $LB
        iifname "internet" ip daddr $PUBLIQUE meta l4proto { tcp, udp } th dport 53 dnat to $NS1
    }
    chain postrouting {
        type nat hook postrouting priority srcnat;
        # SNAT : le VPC sort sur Internet avec l'adresse publique (ses adresses 10.x n'y sont pas routées)
        oifname "internet" ip saddr $VPC masquerade
    }
}

table inet filtre {
    # ------------------------------------------- trafic destiné à la passerelle elle-même
    chain entree {
        type filter hook input priority filter; policy drop;
        ct state invalid drop
        ct state established,related accept
        iif lo accept
        # ICMP : diagnostic (ping) et surtout « Fragmentation needed » (découverte du MTU)
        icmp type { echo-request, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
        udp dport 51820 accept                                   # WireGuard (VPN d'administration)
        iifname "wg0" tcp dport 22 accept                        # SSH : par le VPN seulement
        iifname { "pub", "baie.20", "baie.30", "wg0" } meta l4proto { tcp, udp } th dport 53 accept   # résolveur du VPC
    }

    # ------------------------------------------- trafic qui TRAVERSE la passerelle
    chain transit {
        type filter hook forward priority filter; policy drop;
        ct state invalid drop

        # ACL du sous-réseau « données » : SANS ÉTAT (comme une Network ACL). Évaluée AVANT le
        # suivi de connexion : chaque sens doit être autorisé explicitement, retours compris.
        oifname "baie.30" jump acl_donnees_entree
        iifname "baie.30" jump acl_donnees_sortie

        # Le reste : AVEC ÉTAT (comme un security group) — les retours passent tout seuls.
        ct state established,related accept
        iifname "internet" ct status dnat accept                 # ce que publie le DNAT ci-dessus
        iifname { "pub", "baie.20" } oifname "internet" accept    # sortie vers Internet (via SNAT)
        iifname "pub" oifname "baie.20" ip saddr $LB tcp dport 8000 accept   # lb → applications
        iifname "wg0" tcp dport 22 accept                         # administration
        iifname "wg0" icmp type echo-request accept
        meta l4proto ipv6-icmp accept
        icmp type { echo-request } ip saddr $VPC accept           # diagnostic interne
    }

    chain acl_donnees_entree {
        ip saddr $APP ip daddr $DB tcp dport 5432 accept
        ip6 saddr $APP6 ip6 daddr $DB6 tcp dport 5432 accept      # la base a un AAAA : IPv6 aussi !
        ip saddr { $APP, $LB } ip daddr $STOCKAGE tcp dport 8333 accept
        ip saddr $ADMIN tcp dport 22 accept
        ip saddr { $APP, $ADMIN } icmp type echo-request accept
        # retours des mises à jour (les données sortent vers Internet en 80/443)
        iifname "internet" tcp sport { 80, 443 } tcp dport 1024-65535 accept
        icmp type { echo-reply, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
        counter drop
    }
    chain acl_donnees_sortie {
        ip saddr $DB tcp sport 5432 ip daddr $APP tcp dport 1024-65535 accept
        ip6 saddr $DB6 tcp sport 5432 ip6 daddr $APP6 tcp dport 1024-65535 accept
        ip saddr $STOCKAGE tcp sport 8333 ip daddr { $APP, $LB } tcp dport 1024-65535 accept
        tcp sport 22 ip daddr $ADMIN accept
        oifname "internet" tcp dport { 80, 443 } accept
        icmp type { echo-reply, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
        counter drop
    }
}
EOF
nft -c -f /etc/nftables.conf
systemctl enable -q nftables
systemctl reload nftables 2>/dev/null || systemctl start nftables

# ---------------------------------------------------------------- 4. Résolveur du VPC
rm -f /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf /etc/unbound/unbound.conf.d/remote-control.conf
cat > /etc/unbound/racine.hints <<'EOF'
.                3600000  NS  a.racine.test.
a.racine.test.   3600000  A   192.0.2.53
EOF
cat > /etc/unbound/unbound.conf.d/vpc.conf <<'EOF'
server:
    interface: 127.0.0.1
    interface: 10.0.1.1
    interface: 10.0.2.1
    interface: 10.0.3.1
    interface: 10.99.0.1
    interface-automatic: no
    ip-freebind: yes                       # 10.99.0.1 (wg0) peut ne pas encore exister au démarrage
    access-control: 127.0.0.0/8 allow
    access-control: 10.0.0.0/16 allow
    access-control: 10.99.0.0/24 allow
    root-hints: /etc/unbound/racine.hints
    module-config: "iterator"
    local-zone: "test." nodefault          # RFC 6761 : sinon unbound répond NXDOMAIN tout seul
    # Réponses privées autorisées pour notre propre domaine (vue interne de ns1)
    private-domain: "marche.test"
    # Le VPC interroge ns1 DIRECTEMENT, sur son adresse privée : il obtient la vue interne
    # (split-horizon), là où Internet obtient la vue publique.
stub-zone:
    name: "marche.test"
    stub-addr: 10.0.1.53
remote-control:
    control-enable: yes
    control-interface: 127.0.0.1
    control-use-cert: no
EOF
unbound-checkconf >/dev/null
systemctl enable -q unbound
systemctl restart unbound
printf 'nameserver 127.0.0.1\n' > /etc/resolv.conf

# ---------------------------------------------------------------- 5. VPN d'administration
install -d -m 700 /etc/wireguard
[ -f /etc/wireguard/prive.key ] || (umask 077; wg genkey > /etc/wireguard/prive.key)
wg pubkey < /etc/wireguard/prive.key > /etc/wireguard/public.key
PAIR=$(cat /etc/wireguard/console.pub 2>/dev/null || true)
{
    printf '[Interface]\nAddress = 10.99.0.1/24\nListenPort = 51820\nPrivateKey = %s\n' "$(cat /etc/wireguard/prive.key)"
    [ -z "$PAIR" ] || printf '\n[Peer]  # console (poste d'\''administration)\nPublicKey = %s\nAllowedIPs = 10.99.0.2/32\n' "$PAIR"
} > /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf
systemctl enable -q wg-quick@wg0
systemctl restart wg-quick@wg0
echo "passerelle prête — clé publique WireGuard : $(cat /etc/wireguard/public.key)"
