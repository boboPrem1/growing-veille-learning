#!/bin/bash
# ns — DNS de marche.test, dans une région.
#  MODE_DNS=primaire   (Europe) : BIND fait autorité en split-horizon ; le CONTENU des zones est du
#                      code Terraform (/lab/zones/). Chaque vue est transférée au secondaire,
#                      authentifié par une clé TSIG (c'est la clé qui choisit la vue, pas l'adresse).
#  MODE_DNS=secondaire (Lomé)   : BIND copie les DEUX vues depuis la primaire (AXFR/IXFR + NOTIFY).
#  Et, dans les deux régions, PowerDNS fait autorité sur gslb.marche.test (bascule entre régions),
#  sur une seconde adresse ; ses enregistrements se pilotent par API (Terraform, couche plateforme).
# shellcheck source=commun.sh
. /lab/roles/commun.sh
{
    printf '[Match]\nName=pub\n[Network]\nKeepConfiguration=yes\nGateway=%s\nAddress=%s\nIPv6AcceptRA=yes\n' "$GW" "$ADRESSE6"
    printf 'Address=%s\n' "$GSLB_ADRESSE"                 # l'adresse du service GSLB (PowerDNS)
} > /etc/systemd/network/10-pub.network
reseau_pret pub "${GSLB_ADRESSE}"
resolveur "$RESOLVEUR"

# DEUX clés TSIG, une par vue : c'est la clé qui choisit la vue (pas l'adresse) — à l'aller (transfert
# demandé par le secondaire) comme au retour (NOTIFY de la primaire).
cles_tsig="key \"externe\" { algorithm hmac-sha256; secret \"$TSIG\"; };
key \"interne\" { algorithm hmac-sha256; secret \"$TSIG_INTERNE\"; };"
interne="match-clients { key interne; !key externe; ${CLIENTS_INTERNES}; 127.0.0.1; };"
externe="match-clients { key externe; any; };"
if [ "$MODE_DNS" = primaire ]; then
    install -m 640 -o root -g bind /lab/zones/externe /etc/bind/marche.test.externe
    install -m 640 -o root -g bind /lab/zones/interne /etc/bind/marche.test.interne
    zones=$(cat <<EOF2
$cles_tsig
view "interne" {
    $interne
    zone "marche.test" {
        type primary; file "/etc/bind/marche.test.interne";
        allow-transfer { key interne; };
        also-notify { ${SECONDAIRES} key interne; };
        notify explicit;
    };
};
view "externe" {
    $externe
    zone "marche.test" {
        type primary; file "/etc/bind/marche.test.externe";
        allow-transfer { key externe; };
        also-notify { ${SECONDAIRES} key externe; };
        notify explicit;
    };
};
EOF2
)
else
    # le secondaire copie les DEUX vues : si l'Europe tombe, Lomé résout encore ses noms internes
    zones=$(cat <<EOF2
$cles_tsig
view "interne" {
    $interne
    zone "marche.test" {
        type secondary; primaries { ${PRIMAIRE_DNS} key interne; };
        file "/var/cache/bind/marche.test.interne";
    };
};
view "externe" {
    $externe
    zone "marche.test" {
        type secondary; primaries { ${PRIMAIRE_DNS} key externe; };
        file "/var/cache/bind/marche.test.externe";
    };
};
EOF2
)
fi
cat > /etc/bind/named.conf <<EOF2
options {
    directory "/var/cache/bind";
    listen-on { ${ADRESSE4}; 127.0.0.1; };
    listen-on-v6 { ${ADRESSE6%/*}; };
    recursion no;
    allow-transfer { none; };
    dnssec-validation no;
    version "non communiquée";
};
include "/etc/bind/rndc.key";
controls { inet 127.0.0.1 allow { localhost; } keys { "rndc-key"; }; };
$zones
EOF2
named-checkconf /etc/bind/named.conf
systemctl enable -q named && systemctl restart named

# ------------------------------------------------------------------ PowerDNS : gslb.marche.test
install -d -o pdns -g pdns /var/lib/pdns
[ -s /var/lib/pdns/pdns.sqlite3 ] || { sqlite3 /var/lib/pdns/pdns.sqlite3 < /usr/share/doc/pdns-backend-sqlite3/schema.sqlite3.sql; chown pdns:pdns /var/lib/pdns/pdns.sqlite3; }
rm -f /etc/powerdns/pdns.d/*
cat > /etc/powerdns/pdns.conf <<EOF2
launch=gsqlite3
gsqlite3-database=/var/lib/pdns/pdns.sqlite3
# WAL : Terraform écrit plusieurs enregistrements EN PARALLÈLE — sans lui, « database is locked »
gsqlite3-pragma-journal-mode=WAL
enable-lua-records=yes
local-address=${GSLB_ADRESSE%/*}
api=yes
api-key=${PDNS_API}
webserver=yes
webserver-address=${GSLB_ADRESSE%/*}
webserver-port=8081
webserver-allow-from=${ADMIN}
EOF2
chmod 640 /etc/powerdns/pdns.conf && chown root:pdns /etc/powerdns/pdns.conf
systemctl enable -q pdns && systemctl restart pdns

pare_feu "        meta l4proto { tcp, udp } th dport 53 accept
        ip saddr ${ADMIN} tcp dport { 22, 8081 } accept"
cle_admin
echo "ns ($MODE_DNS) prête"
