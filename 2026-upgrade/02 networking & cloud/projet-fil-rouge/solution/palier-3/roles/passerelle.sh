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
# Palier 3 : les autres liens de la région — un second transitaire, le point d'échange, le circuit
# dédié vers l'autre région. Adresses données par le fournisseur (conservées), noms parlants.
for l in ${AUTRES_LIENS:-}; do lien "$l" "" "" ""; done
# un routeur multi-attaché reçoit légitimement du trafic par un lien, et répond par un autre (le
# meilleur chemin BGP de retour) : la vérification STRICTE de la source (rp_filter=1) le jetterait.
# Mode souple (2) : « l'adresse source est-elle routable par AU MOINS un lien ? ». L'anti-usurpation
# côté VPC reste assurée par le pare-feu.
rpf=1; [ -n "${ASN:-}" ] && rpf=2
cat > /etc/sysctl.d/90-routeur.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = $rpf
net.ipv4.conf.default.rp_filter = $rpf
EOF
sysctl -q --system
reseau_pret pub "$PUB4"
# les liens par lesquels on sort vers Internet (SNAT, et retours autorisés vers le VPC)
UPLINKS=$(for l in internet ${UPLINKS_BGP:-}; do printf '"%s", ' "$l"; done); UPLINKS=${UPLINKS%, }
# les liens vers l'autre région : le tunnel, et (Palier 3) le circuit dédié
INTERCO='"wg0"'; [ -n "${FIBRE:-}" ] && INTERCO='"wg0", "fibre"'
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
# Palier 3 : NOS adresses (le préfixe annoncé en BGP) — l'adresse unicast de la région, et les
# adresses ANYCAST, portées par les deux régions à la fois : chaque client arrive à la plus proche
[ -z "${PI:-}" ] || dnat+="        ip daddr $PI tcp dport { 80, 443 } dnat to $LB"$'\n'
for a in ${ANYCAST_WWW:-}; do dnat+="        ip daddr $a tcp dport { 80, 443 } dnat to $LB"$'\n'; done
for a in ${ANYCAST_DNS:-}; do dnat+="        ip daddr $a meta l4proto { tcp, udp } th dport 53 dnat to $NS"$'\n'; done
# sortie vers Internet : par N'IMPORTE QUEL lien amont, avec NOTRE adresse (le retour arrive par BGP)
snat="        oifname \"internet\" ip saddr $VPC masquerade"
[ -z "${PI:-}" ] || snat="        oifname { $UPLINKS } ip saddr $VPC snat to $PI"
# BGP (tcp 179) avec les voisins déclarés ; BFD (udp 3784 à un saut, 4784 multi-sauts)
bgp_in=""
if [ -n "${ASN:-}" ]; then
    voisins=$(for v in $BGP_VOISINS; do printf '%s, ' "${v%%:*}"; done); voisins=${voisins%, }
    bgp_in="        tcp dport 179 ip saddr { $voisins } accept"$'\n'
    bgp_in+="        udp dport { 3784, 4784 } ip saddr { $voisins } accept"$'\n'
fi

cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;
$dnat    }
    chain postrouting {
        type nat hook postrouting priority srcnat;
$snat
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
$bgp_in        ip saddr ${SUPERVISION:-127.0.0.2} tcp dport 9100 accept          # métriques (dont les alertes IDS)
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
        iifname { "pub", $VLAN_IFS } oifname { $UPLINKS } accept
        # (Palier 3 : les applications ne s'ouvrent plus que par leur sidecar mTLS, port 8443)
        iifname "pub" oifname { $VLAN_IFS } ip saddr $LB_SOURCE tcp dport 8443 accept
        # la supervision (à Lomé) lit les métriques des applications, des bases, et sonde le coffre
        ip saddr ${SUPERVISION:-127.0.0.2} tcp dport { 8443, 8200, 9100 } accept
        ip saddr ${SUPERVISION:-127.0.0.2} ip daddr ${ADMIN} tcp dport 9100 accept     # la conformité, sur la console
        # entre régions (VPN site à site, et au Palier 3 le circuit dédié) : les applications et le
        # résolveur de l'autre région — par l'un ou l'autre lien, selon ce que BGP a choisi
        iifname { $INTERCO } ip saddr ${AUTRES_VPC:-127.0.0.2} accept
        oifname { $INTERCO } ip daddr ${AUTRES_VPC:-127.0.0.2} accept
        iifname "wg0" ip6 saddr ${AUTRES_VPC6:-::2} accept
        oifname "wg0" ip6 daddr ${AUTRES_VPC6:-::2} accept
        # le résolveur de l'autre région interroge ns1 depuis son adresse VPN
        iifname { $INTERCO } ip saddr ${ADMIN} meta l4proto { tcp, udp } th dport 53 accept
        iifname "wg0" oifname { $INTERCO } ip saddr ${ADMIN} accept      # console → autre région (transit)
        iifname { $INTERCO } oifname "wg0" ip daddr ${ADMIN} accept      # et le retour, s'il arrive par le circuit
        # l'administration, par le VPN seulement : SSH, API de gestion (PowerDNS 8081), supervision (9090, 9093)
        iifname { $INTERCO } ip saddr ${ADMIN} tcp dport { 22, 8081, 9090, 9093 } accept
        iifname { $INTERCO } icmp type echo-request accept
        meta l4proto ipv6-icmp accept
        icmp type echo-request ip saddr $VPC accept
    }
    chain acl_donnees_entree {
$regles_acl_entree        ip saddr ${ADMIN} tcp dport 22 accept
        ip saddr { $VPC, ${ADMIN} } icmp type echo-request accept
        iifname { $UPLINKS } tcp sport { 80, 443 } tcp dport 1024-65535 accept
        icmp type { echo-reply, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
        counter drop
    }
    chain acl_donnees_sortie {
$regles_acl_sortie        tcp sport 22 ip daddr ${ADMIN} accept
        oifname { $UPLINKS } tcp dport { 80, 443 } accept
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
    if [ -n "${ASN:-}" ]; then
        # Palier 3 : ce n'est plus wg-quick qui décide des routes vers l'autre région, c'est BGP (le
        # circuit d'abord, le tunnel en secours). Le tunnel reste un lien ; AllowedIPs, un filtre.
        printf 'Table = off\n'
        [ -z "${AUTRES_VPC6:-}" ] || printf 'PostUp = ip -6 route replace %s dev wg0\n' "$AUTRES_VPC6"   # (IPv6 : sans BGP, par le tunnel)
    fi
    for p in /lab/wg/pairs/*.conf; do [ -e "$p" ] && { echo; cat "$p"; }; done
} > /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf
systemctl enable -q wg-quick@wg0 && systemctl restart wg-quick@wg0
systemctl restart unbound                              # il écoute aussi sur l'adresse de wg0

# ------------------------------------------------------------------ BGP (Palier 3) : Marché, AS 64500
# BGP_VOISINS : « adresse:AS:type[:local-pref[:allongement]] » — type transit, ixp, fibre (iBGP par le
# circuit dédié, sous BFD) ou vpn (iBGP par le tunnel, en secours).
# ANNONCES : ce que la région annonce (son /26 unicast, et le /26 anycast commun aux deux régions).
if [ -n "${ASN:-}" ]; then
    # nos adresses publiques sur une interface factice : joignables (ping), et DNATées vers les services
    ip link show anycast >/dev/null 2>&1 || ip link add anycast type dummy
    ip link set anycast up
    for a in ${PI:-} ${ANYCAST_WWW:-} ${ANYCAST_DNS:-}; do ip addr replace "$a/32" dev anycast; done
    read -r fibre_moi fibre_pair_reseau fibre_circuit <<< "${FIBRE:-}"
    sed -i 's/^bgpd=no/bgpd=yes/; s/^bfdd=no/bfdd=yes/' /etc/frr/daemons
    {
        printf 'frr defaults traditional\nhostname passerelle-%s\nlog syslog informational\nservice integrated-vtysh-config\n!\n' "$REGION"
        # ce que NOUS annonçons, et ce qui est à nous (qu'on ne doit jamais accepter de l'extérieur)
        n=5; for p in $ANNONCES; do printf 'ip prefix-list MES-PREFIXES seq %s permit %s\n' $n "$p"; n=$((n + 5)); done
        printf 'ip prefix-list NOTRE-ESPACE seq 5 permit %s le 32\n' "$ESPACE"
        printf 'ip prefix-list NOTRE-ESPACE seq 10 permit 10.0.0.0/8 le 32\n'
        # des « ancres » : une route vers nulle part fait exister le préfixe dans la table, et BGP ne
        # peut annoncer que ce qui existe. (Le /26 anycast n'en a pas ici : c'est la SANTÉ de la région
        # qui l'ajoute ou le retire — voir anycast-sante.)
        for p in $ANNONCES; do [ "$p" = "${ANYCAST_PREFIXE:-}" ] || printf 'ip route %s blackhole\n' "$p"; done
        printf 'ip route %s blackhole\n' "$VPC"
        [ -z "$fibre_moi" ] || printf 'ip route %s %s\n' "$fibre_pair_reseau" "$fibre_circuit"
        # Le tunnel de SECOURS doit passer par Internet, jamais par le circuit qu'il secourt : son
        # extrémité est épinglée sur notre transitaire. (Vécu : l'adresse de l'autre passerelle, apprise
        # aussi par iBGP, a un moment été jointe par le circuit ; WireGuard, qui suit l'adresse des
        # derniers paquets reçus, y a déplacé le tunnel — et la coupure du circuit l'a emporté avec lui.)
        [ -z "${VPN_EXTREMITE:-}" ] || printf 'ip route %s/32 %s\n' "$VPN_EXTREMITE" "$AMONT"
        printf '!\n'
        # vers un transitaire : nos préfixes, et RIEN d'autre (sinon on transporterait le trafic d'un
        # transitaire vers l'autre : une fuite de routes) ; vers l'IXP : pas plus loin que nos pairs
        # RTBH : une adresse attaquée, annoncée seule (/32) avec la communauté « trou noir » du
        # transitaire (65010:666), est JETÉE chez lui, avant d'avoir saturé notre lien. La liste est vide
        # en temps normal ; trou-noir.sh y ajoute une adresse pendant une attaque.
        printf 'ip prefix-list TROU-NOIR seq 1000 deny any\n'      # (les adresses attaquées s'insèrent AVANT)
        printf 'route-map VERS-TRANSIT permit 5\n match ip address prefix-list TROU-NOIR\n set community 65010:666 no-export\nexit\n'
        printf 'route-map VERS-TRANSIT permit 10\n match ip address prefix-list MES-PREFIXES\nexit\nroute-map VERS-TRANSIT deny 20\nexit\n'
        printf 'route-map VERS-TRANSIT-ALLONGE permit 10\n match ip address prefix-list MES-PREFIXES\n set as-path prepend %s %s\nexit\nroute-map VERS-TRANSIT-ALLONGE deny 20\nexit\n' "$ASN" "$ASN"
        printf 'route-map VERS-IXP permit 10\n match ip address prefix-list MES-PREFIXES\n set community no-export\nexit\nroute-map VERS-IXP deny 20\nexit\n'
        printf 'route-map DEPUIS-VPN permit 10\n set local-preference 50\nexit\n'
        # Les routes Internet apprises de l'AUTRE région passent APRÈS nos propres transitaires : chaque
        # région répond par ses propres liens. (Vécu : l'Europe préférait joindre les clients de Lomé via
        # l'IXP de Lomé — sa préférence 300 transmise en iBGP. Une requête arrivée en Europe repartait
        # par Lomé, dont le pare-feu À ÉTAT n'avait jamais vu la connexion : jetée. Routage asymétrique +
        # pare-feux à état = connexions cassées.)
        printf 'route-map IBGP permit 10\n set local-preference 150\nexit\n'
        # L'anycast ne se transmet PAS à l'autre région : chaque région n'annonce que l'anycast qu'ELLE
        # sert. (Vécu : Lomé, malade, retirait son annonce… puis réapprenait le même préfixe de l'Europe
        # par iBGP, et continuait de l'annoncer à l'IXP — les clients arrivaient toujours à Lomé, où le
        # DNAT les envoyait vers le répartiteur arrêté.)
        [ -z "${ANYCAST_PREFIXE:-}" ] || printf 'ip prefix-list ANYCAST seq 5 permit %s\n' "$ANYCAST_PREFIXE"
        printf 'route-map VERS-IBGP deny 5\n match ip address prefix-list ANYCAST\nexit\nroute-map VERS-IBGP permit 10\nexit\n'
        # Ce que la passerelle envoie ELLE-MÊME vers l'autre région (son résolveur qui interroge le DNS
        # d'en face…) part de son adresse INTERNE — pas de celle du circuit, que personne là-bas n'attend.
        # (Vécu : par le tunnel, la source était 10.99.0.x, admise partout ; par le circuit elle devenait
        # 198.18.9.x — le secours de Lomé vers ns1 ne répondait plus, et rien ne l'avait signalé.)
        printf 'ip prefix-list INTERNE seq 5 permit 10.0.0.0/8 le 32\n'
        printf 'route-map SOURCE-INTERNE permit 10\n match ip address prefix-list INTERNE\n set src %s\nexit\nroute-map SOURCE-INTERNE permit 20\nexit\n' "${PUB4%/*}"
        printf 'ip protocol bgp route-map SOURCE-INTERNE\n'
        for v in $BGP_VOISINS; do
            IFS=: read -r ip as type lp _ <<< "$v"
            case $type in transit|ixp)
                printf 'route-map DEPUIS-%s deny 5\n match ip address prefix-list NOTRE-ESPACE\nexit\n' "$ip"
                printf 'route-map DEPUIS-%s permit 10\n set local-preference %s\nexit\n' "$ip" "${lp:-100}" ;;
            esac
        done
        printf '!\n'
        if [ -n "$fibre_moi" ]; then
            # BFD : 3 paquets manqués à 300 ms d'intervalle → circuit déclaré mort en moins d'une seconde
            # (sans lui, BGP attendrait la fin de son « hold timer » — 3 minutes par défaut)
            printf 'bfd\n profile circuit\n  receive-interval 300\n  transmit-interval 300\n  detect-multiplier 3\n exit\nexit\n!\n'
        fi
        printf 'router bgp %s\n bgp router-id %s\n bgp log-neighbor-changes\n' "$ASN" "$BGP_ID"
        printf ' no bgp enforce-first-as\n'          # (le serveur de routes de l'IXP ne s'insère pas dans le chemin)
        for v in $BGP_VOISINS; do
            IFS=: read -r ip as type _ _ <<< "$v"
            printf ' neighbor %s remote-as %s\n neighbor %s description %s\n' "$ip" "$as" "$ip" "$type"
            case $type in
                fibre) printf ' neighbor %s update-source %s\n neighbor %s bfd\n neighbor %s bfd profile circuit\n' "$ip" "$fibre_moi" "$ip" "$ip" ;;
                vpn)   printf ' neighbor %s update-source %s\n neighbor %s timers 10 30\n' "$ip" "${WG_ADRESSE%/*}" "$ip" ;;
            esac
        done
        printf ' !\n address-family ipv4 unicast\n'
        for p in $ANNONCES; do printf '  network %s\n' "$p"; done
        printf '  network %s\n' "$VPC"
        for v in $BGP_VOISINS; do
            IFS=: read -r ip as type lp allonge <<< "$v"
            case $type in
                transit) printf '  neighbor %s route-map DEPUIS-%s in\n  neighbor %s route-map %s out\n  neighbor %s maximum-prefix 1000\n' \
                             "$ip" "$ip" "$ip" "$([ "${allonge:-0}" -gt 0 ] && echo VERS-TRANSIT-ALLONGE || echo VERS-TRANSIT)" "$ip" ;;
                ixp)     printf '  neighbor %s route-map DEPUIS-%s in\n  neighbor %s route-map VERS-IXP out\n  neighbor %s send-community\n  neighbor %s maximum-prefix 1000\n' \
                             "$ip" "$ip" "$ip" "$ip" "$ip" ;;
                fibre)   printf '  neighbor %s next-hop-self\n  neighbor %s route-map IBGP in\n  neighbor %s route-map VERS-IBGP out\n' "$ip" "$ip" "$ip" ;;
                vpn)     printf '  neighbor %s next-hop-self\n  neighbor %s route-map DEPUIS-VPN in\n  neighbor %s route-map VERS-IBGP out\n' "$ip" "$ip" "$ip" ;;
            esac
        done
        printf ' exit-address-family\nexit\n'
    } > /etc/frr/frr.conf
    chown frr:frr /etc/frr/frr.conf && chmod 640 /etc/frr/frr.conf
    systemctl enable -q frr && systemctl restart frr

    # L'anycast n'est annoncé QUE si la région sert : sinon, on attirerait des clients vers un site en
    # panne. Une boucle vérifie le répartiteur (/sante) chaque seconde ; deux échecs → retrait du /26
    # anycast, un succès → annonce. (Un même /26 porte www ET le DNS : ils partagent ce destin — un
    # opérateur sérieux donne à chaque service son propre préfixe.)
    cat > /usr/local/sbin/anycast-sante <<EOF
#!/bin/bash
echecs=0
while :; do
    if curl -sf -o /dev/null -m 1 "$SANTE"; then echecs=0; voulu=oui; else echecs=\$((echecs + 1)); [ \$echecs -ge 2 ] && voulu=non; fi
    present=\$(vtysh -c "show ip route $ANYCAST_PREFIXE" 2>/dev/null | grep -c 'blackhole')
    if [ "\${voulu:-}" = oui ] && [ "\$present" = 0 ]; then
        vtysh -c 'configure terminal' -c "ip route $ANYCAST_PREFIXE blackhole" && logger -t anycast "région en santé : $ANYCAST_PREFIXE ANNONCÉ"
    elif [ "\${voulu:-}" = non ] && [ "\$present" != 0 ]; then
        vtysh -c 'configure terminal' -c "no ip route $ANYCAST_PREFIXE blackhole" && logger -t anycast "région malade : $ANYCAST_PREFIXE RETIRÉ"
    fi
    sleep 1
done
EOF
    chmod 755 /usr/local/sbin/anycast-sante
    printf '[Unit]\nDescription=Annonce anycast conditionnée à la santé de la région\nAfter=frr.service\n[Service]\nExecStart=/usr/local/sbin/anycast-sante\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' \
        > /etc/systemd/system/anycast-sante.service
    systemctl daemon-reload && systemctl enable -q anycast-sante && systemctl restart anycast-sante
fi
# ------------------------------------------------------------------ SD-WAN (Palier 3) : le chemin PAR APPLICATION
# Deux liens vers l'autre région : le circuit dédié (cher, capacité réservée, délai stable) et le
# tunnel sur Internet (gratuit, partagé). BGP choisit UN chemin pour tout ; ici, on choisit par
# application : le VOLUMINEUX (SDWAN_INTERNET : les ports du stockage objet) part par le tunnel, et
# laisse le circuit à l'interactif (la base, l'API). Si le tunnel tombe, sa route disparaît de la
# table dédiée, et ce trafic retombe sur la table principale : le circuit.
if [ -n "${SDWAN_INTERNET:-}" ]; then
    pair_vpn=$(for v in $BGP_VOISINS; do IFS=: read -r ip _ type _ <<< "$v"; [ "$type" = vpn ] && echo "$ip"; done)
    ports=$(echo "$SDWAN_INTERNET" | tr ' ' ','); ports=${ports%,}
    cat > /etc/nftables.d-sdwan.conf <<EOF2
table inet sdwan {
    chain classement {
        type filter hook prerouting priority mangle; policy accept;
        # le volumineux vers l'autre région (aller) et ses réponses (retour) : marqué « internet »
        ip daddr ${AUTRES_VPC} tcp dport { $ports } meta mark set meta mark | 0x2
        ip daddr ${AUTRES_VPC} tcp sport { $ports } meta mark set meta mark | 0x2
    }
}
EOF2
    grep -q 'nftables.d-sdwan.conf' /etc/nftables.conf || echo 'include "/etc/nftables.d-sdwan.conf"' >> /etc/nftables.conf
    systemctl reload nftables
    ip route replace "$AUTRES_VPC" via "$pair_vpn" dev wg0 table 200
    ip rule show | grep -q 'fwmark 0x2/0x2 lookup 200' || ip rule add fwmark 0x2/0x2 lookup 200 priority 100
    # La santé du CHEMIN, pas de l'interface : WireGuard n'a pas d'état de connexion — si l'autre bout
    # tombe, notre wg0 reste « up » et nos réponses partent dans le vide. (Vécu : tunnel arrêté à Lomé,
    # l'Europe y renvoyait toujours ses réponses.) Une sonde, comme tout SD-WAN : l'autre extrémité
    # du tunnel répond-elle ? Trois échecs → le volumineux quitte le tunnel ; il y revient à la guérison.
    cat > /usr/local/sbin/sdwan-sante <<EOF2
#!/bin/bash
echecs=0
while :; do
    if ping -c1 -W1 -I wg0 $pair_vpn >/dev/null 2>&1; then echecs=0; else echecs=\$((echecs + 1)); fi
    present=\$(ip route show table 200 | grep -c .)
    if [ \$echecs -ge 3 ] && [ "\$present" != 0 ]; then
        ip route flush table 200 && logger -t sdwan "tunnel MALADE : le volumineux passe par le circuit"
    elif [ \$echecs = 0 ] && [ "\$present" = 0 ]; then
        ip route replace $AUTRES_VPC via $pair_vpn dev wg0 table 200 && logger -t sdwan "tunnel sain : le volumineux y revient"
    fi
    sleep 1
done
EOF2
    chmod 755 /usr/local/sbin/sdwan-sante
    printf '[Unit]\nDescription=SD-WAN : santé du tunnel\nAfter=wg-quick@wg0.service\n[Service]\nExecStart=/usr/local/sbin/sdwan-sante\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' \
        > /etc/systemd/system/sdwan-sante.service
    systemctl daemon-reload && systemctl enable -q sdwan-sante && systemctl restart sdwan-sante
fi

# ------------------------------------------------------------------ IDS/IPS (Palier 3) : Suricata EN LIGNE
# Tout ce qui arrive d'un lien amont passe par Suricata (NFQUEUE) avant nos propres règles : il
# ALERTE (balayages, SSH cherché depuis Internet) et BLOQUE ce qui est sans ambiguïté (les requêtes
# DNS « ANY », l'arme des attaques par amplification). « bypass » : si Suricata tombe, le trafic PASSE
# — le choix de la disponibilité ; sans lui, un IPS arrêté coupe tout (le choix de la sécurité).
if [ -n "${IDS:-}" ]; then
    c=/etc/suricata/suricata.yaml
    # nos adresses (publiques et internes : après le DNAT, la destination est déjà l'adresse interne)
    sed -i "s|^    HOME_NET: .*|    HOME_NET: \"[10.0.0.0/8,${ESPACE:-198.51.100.0/24},${PUBLIQUE}]\"|" $c
    sed -i 's|^default-rule-path: .*|default-rule-path: /etc/suricata/marche|; s|^  - suricata.rules$|  - marche.rules|' $c
    sed -i 's|^      #ja3-fingerprints: auto|      ja3-fingerprints: yes|' $c        # l'empreinte d'un client TLS, même chiffré
    install -d /etc/suricata/marche
    cat > /etc/suricata/marche/marche.rules <<'EOF2'
# balayage : beaucoup de connexions tentées, vers des ports différents, depuis une même source
alert tcp $EXTERNAL_NET any -> $HOME_NET any (msg:"MARCHE balayage de ports"; flow:stateless; flags:S,12; threshold:type both, track by_src, count 20, seconds 10; classtype:attempted-recon; sid:9000001; rev:1;)
# SSH depuis Internet : nos serveurs ne l'ouvrent QUE par le VPN — quelqu'un cherche une porte
alert tcp $EXTERNAL_NET any -> $HOME_NET 22 (msg:"MARCHE SSH tenté depuis Internet"; flow:stateless; flags:S,12; threshold:type limit, track by_src, count 1, seconds 60; classtype:attempted-recon; sid:9000002; rev:1;)
# DNS ANY : 30 octets de question, des milliers de réponse — l'arme de l'amplification. BLOQUÉE.
drop udp $EXTERNAL_NET any -> $HOME_NET 53 (msg:"MARCHE requête DNS ANY bloquée (amplification)"; content:"|00 00 ff 00 01|"; classtype:attempted-dos; sid:9000003; rev:1;)
EOF2
    # les scanners AUTORISÉS (la surveillance de conformité cherche SSH sur nos adresses toutes les
    # 5 min : c'est son travail). Sans cette exception, l'alerte « intrusion » sonnait en permanence —
    # et une alerte qui sonne toujours, on ne la lit plus (vécu). Une exception étroite : cette source,
    # CETTE signature ; un balayage venu de la console alerterait encore.
    : > /etc/suricata/threshold.config
    for s in ${IDS_AUTORISES:-}; do printf 'suppress gen_id 1, sig_id 9000002, track by_src, ip %s\n' "$s" >> /etc/suricata/threshold.config; done
    sed -i 's|^# threshold-file: /etc/suricata/threshold.config|threshold-file: /etc/suricata/threshold.config|' $c
    install -d /etc/systemd/system/suricata.service.d
    printf '[Service]\nExecStart=\nExecStart=/usr/bin/suricata -D -q 0 -c /etc/suricata/suricata.yaml --pidfile /run/suricata.pid\n' \
        > /etc/systemd/system/suricata.service.d/en-ligne.conf
    # la file d'attente vers Suricata : une table À PART, avant la nôtre (priorité -50). Le verdict
    # « accepter » de Suricata ne vaut que pour CETTE chaîne : nos règles s'appliquent ensuite.
    # LES DEUX SENS : un IPS qui ne voit que l'entrant reçoit, pour une connexion ouverte de l'intérieur
    # (la base vers le S3 du fournisseur), une réponse SYN-ACK sans avoir vu le SYN — et la rejette.
    # (Vécu : les sauvegardes s'étaient arrêtées ; l'alerte « archivage » l'a signalé.)
    cat > /etc/nftables.d-ips.conf <<EOF2
table inet ips {
    chain transit { type filter hook forward priority -50; policy accept; iifname { $UPLINKS } queue num 0 bypass; oifname { $UPLINKS } queue num 0 bypass; }
    chain entree  { type filter hook input priority -50; policy accept; iifname { $UPLINKS } queue num 0 bypass; }
    chain sortie  { type filter hook output priority -50; policy accept; oifname { $UPLINKS } queue num 0 bypass; }
}
EOF2
    grep -q 'nftables.d-ips.conf' /etc/nftables.conf || echo 'include "/etc/nftables.d-ips.conf"' >> /etc/nftables.conf
    systemctl daemon-reload && systemctl enable -q suricata && systemctl restart suricata
    systemctl reload nftables
    # les alertes, pour la supervision : un compteur par signature (collecteur « textfile »)
    cat > /usr/local/sbin/metriques-ids <<'EOF2'
#!/bin/sh
f=/var/lib/prometheus/node-exporter/ids.prom
jq -r 'select(.event_type == "alert") | "\(.alert.signature_id) \(.alert.action)"' /var/log/suricata/eve.json 2>/dev/null \
  | sort | uniq -c \
  | awk '{printf "marche_ids_alertes_total{sid=\"%s\",action=\"%s\"} %s\n", $2, $3, $1}' > "$f.tmp"
mv "$f.tmp" "$f"
EOF2
    chmod 755 /usr/local/sbin/metriques-ids
    install -d /var/lib/prometheus/node-exporter
    printf '[Unit]\nDescription=Alertes IDS pour la supervision\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/metriques-ids\n' > /etc/systemd/system/metriques-ids.service
    printf '[Unit]\nDescription=Alertes IDS toutes les 15 s\n[Timer]\nOnBootSec=15\nOnUnitActiveSec=15\nAccuracySec=1\n[Install]\nWantedBy=timers.target\n' > /etc/systemd/system/metriques-ids.timer
    systemctl daemon-reload && systemctl enable -q --now prometheus-node-exporter metriques-ids.timer
fi
annoncer                                               # toutes les interfaces sont prêtes (VLAN, 2de IP publique)
cle_admin
echo "passerelle ${REGION} prête"
