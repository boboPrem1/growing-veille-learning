#!/bin/bash
# db — PostgreSQL dans le sous-réseau « données » (VLAN 30), joignable par les applications seules.
# usage : db.sh <mot de passe de l'utilisateur marche>
set -euo pipefail
MDP=${1:?mot de passe}
bash /root/vlan.sh 30 10 10

v=$(ls /etc/postgresql)
cat > /etc/postgresql/$v/main/conf.d/reseau.conf <<'EOF'
# Toutes les adresses ('*') : ce sont pg_hba et le pare-feu qui filtrent. Une liste explicite
# échoue EN SILENCE pour l'IPv6 au démarrage : l'adresse est encore « tentative » (détection de
# doublon, DAD) quand PostgreSQL démarre → « could not bind IPv6 address », et il continue sans.
listen_addresses = '*'
password_encryption = 'scram-sha-256'
EOF
f=/etc/postgresql/$v/main/pg_hba.conf
sed -i '/# marche : applications/,$d' "$f"
cat >> "$f" <<'EOF'
# marche : applications (et elles seules), mot de passe haché (SCRAM)
host  marche  marche  10.0.2.11/32  scram-sha-256
host  marche  marche  10.0.2.12/32  scram-sha-256
# db.marche.test a aussi une adresse IPv6 (AAAA) : les applications peuvent venir en IPv6
host  marche  marche  fd00:4d41:5243:20::/64  scram-sha-256
EOF
systemctl enable -q postgresql && systemctl restart postgresql
runuser -u postgres -- psql -qtc "select 1 from pg_roles where rolname='marche'" | grep -q 1 \
    || runuser -u postgres -- psql -qc "create role marche login"
runuser -u postgres -- psql -qc "alter role marche password '$MDP'"
runuser -u postgres -- psql -qtc "select 1 from pg_database where datname='marche'" | grep -q 1 \
    || runuser -u postgres -- createdb -O marche marche

# Security group de la base : 5432 depuis les applications, SSH depuis le VPN, rien d'autre
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
        ip saddr { 10.0.2.11, 10.0.2.12 } tcp dport 5432 accept
        ip6 saddr fd00:4d41:5243:20::/64 tcp dport 5432 accept
        ip saddr 10.99.0.0/24 tcp dport 22 accept
    }
}
EOF
nft -c -f /etc/nftables.conf && systemctl enable -q nftables && { systemctl reload nftables 2>/dev/null || systemctl start nftables; }
echo "db prête"
