#!/bin/bash
# ns1 — serveur DNS FAISANT AUTORITÉ pour marche.test, en « split-horizon » (deux vues) :
#   Internet (via le DNAT de la passerelle) reçoit les adresses PUBLIQUES,
#   le VPC reçoit les adresses PRIVÉES — l'équivalent d'une zone Route 53 publique + privée.
set -euo pipefail

cat > /etc/systemd/network/10-pub.network <<'EOF'
[Match]
Name=pub
[Network]
Gateway=10.0.1.1
KeepConfiguration=yes
Address=fd00:4d41:5243:1::53/64
IPv6AcceptRA=yes
EOF
systemctl enable -q systemd-networkd && systemctl restart systemd-networkd
printf 'nameserver 10.0.1.1\n' > /etc/resolv.conf

SERIE=$(date +%Y%m%d%H)
cat > /etc/bind/named.conf <<'EOF'
options {
    directory "/var/cache/bind";
    listen-on { 10.0.1.53; 127.0.0.1; };
    listen-on-v6 { fd00:4d41:5243:1::53; };
    recursion no;                 // un serveur faisant autorité ne résout rien pour les autres
    allow-transfer { none; };
    dnssec-validation no;
    version "non communiquée";
};
include "/etc/bind/rndc.key";
controls { inet 127.0.0.1 allow { localhost; } keys { "rndc-key"; }; };

view "interne" {
    match-clients { 10.0.0.0/16; 10.99.0.0/24; fd00:4d41:5243::/48; 127.0.0.1; };
    zone "marche.test" { type primary; file "/etc/bind/marche.test.interne"; };
};
view "externe" {
    match-clients { any; };
    zone "marche.test" { type primary; file "/etc/bind/marche.test.externe"; };
};
EOF

# Enregistrements publics, communs aux deux vues
commun() {
cat <<EOF
\$TTL 300
@        IN SOA  ns1.marche.test. hostmaster.marche.test. ( $SERIE 3600 600 1209600 300 )
@        IN NS   ns1.marche.test.
; ce domaine n'envoie aucun courriel : le dire (SPF), plutôt que laisser usurper son nom
@        IN TXT  "v=spf1 -all"
_dmarc   IN TXT  "v=DMARC1; p=reject"
; le CDN : les ressources statiques sont servies depuis Lomé, au plus près des clients
static   IN A    192.0.2.80
EOF
}
{ commun; cat <<'EOF'
ns1      IN A    203.0.113.10
@        IN A    203.0.113.10
www      IN A    203.0.113.10
EOF
} > /etc/bind/marche.test.externe
{ commun; cat <<'EOF'
; vue INTERNE : les adresses privées (le VPC ne fait pas le détour par l'adresse publique)
ns1       IN A     10.0.1.53
ns1       IN AAAA  fd00:4d41:5243:1::53
@         IN A     10.0.1.10
www       IN A     10.0.1.10
lb        IN A     10.0.1.10
passerelle IN A    10.0.1.1
app1      IN A     10.0.2.11
app1      IN AAAA  fd00:4d41:5243:20::11
app2      IN A     10.0.2.12
app2      IN AAAA  fd00:4d41:5243:20::12
db        IN A     10.0.3.10
db        IN AAAA  fd00:4d41:5243:30::10
stockage  IN A     10.0.3.20
EOF
} > /etc/bind/marche.test.interne
chown root:bind /etc/bind/marche.test.*
named-checkconf /etc/bind/named.conf
named-checkzone -q marche.test /etc/bind/marche.test.externe
named-checkzone -q marche.test /etc/bind/marche.test.interne

cat > /etc/nftables.conf <<'EOF'
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
        meta l4proto { tcp, udp } th dport 53 accept          # le service publié
        ip saddr 10.99.0.0/24 tcp dport 22 accept              # administration (VPN)
    }
}
EOF
nft -c -f /etc/nftables.conf && systemctl enable -q nftables && { systemctl reload nftables 2>/dev/null || systemctl start nftables; }
systemctl enable -q named && systemctl restart named
echo "ns1 prête"
