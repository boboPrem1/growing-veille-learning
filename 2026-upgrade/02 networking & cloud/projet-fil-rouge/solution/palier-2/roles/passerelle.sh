#!/bin/bash
# passerelle — le routeur d'une région (Internet Gateway + NAT Gateway + route tables + Network ACL
# + résolveur du VPC + VPN). Le même rôle sert aux deux régions ; tout ce qui diffère est dans
# /lab/parametres.sh (écrit par Terraform). Relancé à chaque démarrage : idempotent.
# shellcheck source=commun.sh
. /lab/roles/commun.sh

# ------------------------------------------------------------------ interfaces
lien internet "" "$AMONT" ""
# une seconde adresse publique (« IP élastique » supplémentaire) pour le service GSLB de la région
[ -z "${GSLB_PUBLIQUE:-}" ] || printf 'Address=%s/24\n' "$GSLB_PUBLIQUE" >> /etc/systemd/network/10-internet.network
printf '[Match]\nName=pub\n[Network]\nKeepConfiguration=yes\nAddress=%s\nAddress=%s\nIPv6SendRA=yes\n[IPv6SendRA]\nDNS=%s\n[IPv6Prefix]\nPrefix=%s\n' \
    "$PUB4" "$PUB6" "${PUB6%/*}" "$(python3 -c "import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)" "$PUB6")" \
    > /etc/systemd/network/10-pub.network
{ printf '[Match]\nName=baie\n[Network]\nKeepConfiguration=yes\nLinkLocalAddressing=no\n'
  for v in $VLANS; do printf 'VLAN=baie.%s\n' "${v%%=*}"; done; } > /etc/systemd/network/10-baie.network
for v in $VLANS; do
    IFS='=' read -r id a4 a6 <<< "$v"
    printf '[NetDev]\nName=baie.%s\nKind=vlan\n[VLAN]\nId=%s\n' "$id" "$id" > "/etc/systemd/network/20-baie.$id.netdev"
    printf '[Match]\nName=baie.%s\n[Network]\nAddress=%s\nAddress=%s\nIPv6SendRA=yes\n[IPv6SendRA]\nDNS=%s\n[IPv6Prefix]\nPrefix=%s\n' \
        "$id" "$a4" "$a6" "${a6%/*}" "$(python3 -c "import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)" "$a6")" \
        > "/etc/systemd/network/20-baie.$id.network"
done
cat > /etc/sysctl.d/90-routeur.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
sysctl -q --system
reseau_pret pub "$PUB4"
DONNEES_IF=baie.$(for v in $VLANS; do echo "${v%%=*}"; done | tail -1)   # le dernier VLAN : les données
# (nftables : pas de joker « baie.* » dans un ensemble — la liste exacte des interfaces du VPC)
VLAN_IFS=$(for v in $VLANS; do printf '"baie.%s", ' "${v%%=*}"; done); VLAN_IFS=${VLAN_IFS%, }

# ------------------------------------------------------------------ pare-feu, NAT, ACL sans état
ensemble() { [ -n "$1" ] && echo "{ $1 }"; }       # « a, b » → « { a, b } »
regles_acl_entree=""; regles_acl_sortie=""
ajouter() { regles_acl_entree+="        $1"$'\n'; regles_acl_sortie+="        $2"$'\n'; }
[ -z "${DB_CLIENTS:-}" ]   || ajouter "ip saddr $(ensemble "$DB_CLIENTS") ip daddr $DB tcp dport 5432 accept" \
                                      "ip saddr $DB tcp sport 5432 ip daddr $(ensemble "$DB_CLIENTS") tcp dport 1024-65535 accept"
[ -z "${DB_CLIENTS6:-}" ]  || ajouter "ip6 saddr $(ensemble "$DB_CLIENTS6") ip6 daddr $DB6 tcp dport 5432 accept" \
                                      "ip6 saddr $DB6 tcp sport 5432 ip6 daddr $(ensemble "$DB_CLIENTS6") tcp dport 1024-65535 accept"
[ -z "${S3_CLIENTS:-}" ]   || ajouter "ip saddr $(ensemble "$S3_CLIENTS") ip daddr $STOCKAGE tcp dport 8333 accept" \
                                      "ip saddr $STOCKAGE tcp sport 8333 ip daddr $(ensemble "$S3_CLIENTS") tcp dport 1024-65535 accept"
[ -z "${COFFRE_CLIENTS:-}" ] || ajouter "ip saddr $(ensemble "$COFFRE_CLIENTS") ip daddr $COFFRE tcp dport 8200 accept" \
                                      "ip saddr $COFFRE tcp sport 8200 ip daddr $(ensemble "$COFFRE_CLIENTS") tcp dport 1024-65535 accept"
# la supervision (à Lomé) : métriques des bases (node exporter) et santé du coffre
[ -z "${SUPERVISION:-}" ]  || ajouter "ip saddr $SUPERVISION tcp dport { 8200, 9100 } accept" \
                                      "ip daddr $SUPERVISION tcp sport { 8200, 9100 } tcp dport 1024-65535 accept"
# la réplique d'une autre région, ou la base qui en est une : connexions SORTANTES des données vers une base distante
[ -z "${DB_DISTANTE:-}" ]  || ajouter "ip saddr $DB_DISTANTE tcp sport 5432 tcp dport 1024-65535 accept" \
                                      "ip daddr $DB_DISTANTE tcp dport 5432 accept"
# le coffre d'une autre région (la base de Lomé, devenue primaire, y lit le secret de ses sauvegardes)
[ -z "${COFFRE_DISTANT:-}" ] || ajouter "ip saddr $COFFRE_DISTANT tcp sport 8200 tcp dport 1024-65535 accept" \
                                        "ip daddr $COFFRE_DISTANT tcp dport 8200 accept"

dnat=""
# (DNAT pour TOUT paquet qui vise l'adresse publique — pas seulement ceux qui arrivent d'Internet : un
#  client du VPC qui vise l'adresse publique doit aussi être traduit, c'est le NAT « en épingle »)
[ -z "${LB:-}" ] || dnat+="        ip daddr $PUBLIQUE tcp dport { 80, 443 } dnat to $LB"$'\n'
[ -z "${NS:-}" ] || dnat+="        ip daddr $PUBLIQUE meta l4proto { tcp, udp } th dport 53 dnat to $NS"$'\n'
[ -z "${GSLB:-}" ] || dnat+="        ip daddr ${GSLB_PUBLIQUE} meta l4proto { tcp, udp } th dport 53 dnat to $GSLB"$'\n'

cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;
$dnat    }
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "internet" ip saddr $VPC masquerade
        # NAT « en épingle » (hairpin) : une machine du VPC qui vise une adresse PUBLIQUE de ce même
        # VPC (le GSLB qui vérifie le site de sa propre région) — sans lui, la réponse contournerait
        # la passerelle, et la connexion échouerait.
        ip saddr $VPC ct status dnat masquerade
    }
}
table inet filtre {
    chain entree {
        type filter hook input priority filter; policy drop;
        ct state invalid counter drop
        ct state established,related accept
        iif lo accept
        icmp type { echo-request, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
        udp dport ${WG_PORT} accept
        iifname "wg0" tcp dport 22 accept
        iifname { "pub", $VLAN_IFS, "wg0" } meta l4proto { tcp, udp } th dport 53 accept
    }
    chain transit {
        type filter hook forward priority filter; policy drop;
        ct state invalid counter drop
        oifname "$DONNEES_IF" jump acl_donnees_entree
        iifname "$DONNEES_IF" jump acl_donnees_sortie
        ct state established,related accept
        ct status dnat accept                                   # ce que publie le DNAT (d'Internet ou du VPC)
        iifname { "pub", $VLAN_IFS } oifname "internet" accept
        iifname "pub" oifname { $VLAN_IFS } ip saddr $LB_SOURCE tcp dport 8000 accept
        # la supervision (à Lomé) lit les métriques des applications, des bases, et sonde le coffre
        ip saddr ${SUPERVISION:-127.0.0.2} tcp dport { 8000, 8200, 9100 } accept
        # entre régions (VPN site à site) : les applications et le résolveur de l'autre région
        iifname "wg0" ip saddr ${AUTRES_VPC:-127.0.0.2} accept
        oifname "wg0" ip daddr ${AUTRES_VPC:-127.0.0.2} accept
        iifname "wg0" ip6 saddr ${AUTRES_VPC6:-::2} accept
        oifname "wg0" ip6 daddr ${AUTRES_VPC6:-::2} accept
        # le résolveur de l'autre région interroge ns1 depuis son adresse VPN
        iifname "wg0" ip saddr ${ADMIN} meta l4proto { tcp, udp } th dport 53 accept
        iifname "wg0" oifname "wg0" ip saddr ${ADMIN} accept      # console → autre région (transit)
        # l'administration, par le VPN seulement : SSH, API de gestion (PowerDNS 8081), supervision (9090, 9093)
        iifname "wg0" ip saddr ${ADMIN} tcp dport { 22, 8081, 9090, 9093 } accept
        iifname "wg0" icmp type echo-request accept
        meta l4proto ipv6-icmp accept
        icmp type echo-request ip saddr $VPC accept
    }
    chain acl_donnees_entree {
$regles_acl_entree        ip saddr ${ADMIN} tcp dport 22 accept
        ip saddr { $VPC, ${ADMIN} } icmp type echo-request accept
        iifname "internet" tcp sport { 80, 443 } tcp dport 1024-65535 accept
        icmp type { echo-reply, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
        counter drop
    }
    chain acl_donnees_sortie {
$regles_acl_sortie        tcp sport 22 ip daddr ${ADMIN} accept
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

# ------------------------------------------------------------------ résolveur du VPC
rm -f /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf /etc/unbound/unbound.conf.d/remote-control.conf
printf '.                3600000  NS  a.racine.test.\na.racine.test.   3600000  A   192.0.2.53\n' > /etc/unbound/racine.hints
{
    printf 'server:\n    interface: 127.0.0.1\n    interface-automatic: no\n    ip-freebind: yes\n'
    for a in "${PUB4%/*}" $(for v in $VLANS; do IFS='=' read -r _ a4 _ <<< "$v"; echo "${a4%/*}"; done) "${WG_ADRESSE%/*}"; do
        printf '    interface: %s\n' "$a"
    done
    printf '    access-control: 127.0.0.0/8 allow\n    access-control: %s allow\n    access-control: %s allow\n' "$VPC" "$ADMIN"
    printf '    root-hints: /etc/unbound/racine.hints\n    module-config: "iterator"\n    local-zone: "test." nodefault\n'
    # le point d'accès de la base est servi par le résolveur de CHAQUE région (comme une zone privée
    # associée au VPC) : on peut le changer lors d'une bascule même si le DNS de l'autre région est mort.
    # (seulement un A : AAAA → « pas de donnée », les applications passent en IPv4)
    printf '    local-data: "db.marche.test. 30 IN A %s"\n' "$DB_PRIMAIRE"
    printf '    private-domain: "marche.test"\nstub-zone:\n    name: "marche.test"\n'
    # les DEUX serveurs internes (celui de la région d'abord) : unbound choisit le plus rapide qui répond
    for ns in $NS_PRIVE; do printf '    stub-addr: %s\n' "$ns"; done
    printf 'remote-control:\n    control-enable: yes\n    control-interface: 127.0.0.1\n    control-use-cert: no\n'
} > /etc/unbound/unbound.conf.d/vpc.conf
unbound-checkconf >/dev/null
systemctl enable -q unbound && systemctl restart unbound
resolveur 127.0.0.1

# ------------------------------------------------------------------ VPN : administration + site à site
install -d -m 700 /etc/wireguard
install -m 600 /lab/wg/prive.key /etc/wireguard/prive.key

# QoS du lien intercontinental. Le câble a une capacité limitée et, chez l'opérateur, un GROS tampon :
# un transfert massif le remplit, et CHAQUE paquet attend derrière (vécu : 122 ms → 750 ms pour une
# simple poignée de main vers la base). On reprend la main sur la file :
#  1. HTB limite le débit JUSTE SOUS celui du câble : la file se forme ICI, plus chez l'opérateur ;
#  2. fq_codel y sert chaque flux à tour de rôle et garde la file courte (5 ms).
# (Une FIFO à la place de fq_codel : pire que rien — 706 ms, la file a juste changé de place.)
# Sur wg0, AVANT le chiffrement : après, tout le tunnel n'est qu'UN flux UDP, indiscernable.
# overhead 60 : ce que WireGuard ajoute à chaque paquet (IP 20 + UDP 8 + WireGuard 32).
cat > /usr/local/sbin/qos-wg0 <<EOF
#!/bin/sh
[ -n "${DEBIT_TUNNEL:-}" ] || exit 0
tc qdisc del dev wg0 root 2>/dev/null                 # (relançable : on repart de zéro)
tc qdisc add dev wg0 root handle 1: htb default 10 r2q 100
tc class add dev wg0 parent 1: classid 1:10 htb rate ${DEBIT_TUNNEL:-0} ceil ${DEBIT_TUNNEL:-0} overhead 60
tc qdisc add dev wg0 parent 1:10 handle 10: fq_codel
EOF
chmod 755 /usr/local/sbin/qos-wg0
{
    printf '[Interface]\nAddress = %s\nListenPort = %s\nPrivateKey = %s\n' "$WG_ADRESSE" "$WG_PORT" "$(cat /etc/wireguard/prive.key)"
    printf 'PostUp = /usr/local/sbin/qos-wg0\n'      # (wg0 recréée → ses files aussi)
    for p in /lab/wg/pairs/*.conf; do [ -e "$p" ] && { echo; cat "$p"; }; done
} > /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf
systemctl enable -q wg-quick@wg0 && systemctl restart wg-quick@wg0
systemctl restart unbound                              # il écoute aussi sur l'adresse de wg0
annoncer                                               # toutes les interfaces sont prêtes (VLAN, 2de IP publique)
cle_admin
echo "passerelle ${REGION} prête"
