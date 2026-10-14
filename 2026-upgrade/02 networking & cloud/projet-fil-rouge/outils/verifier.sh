#!/usr/bin/env bash
# verifier.sh — correcteur du projet fil rouge Networking & Cloud. À lancer SUR L'HÔTE du lab.
#
#   ./outils/verifier.sh 1            Palier 1
#   ./outils/verifier.sh 1 --rapide   sans les tests longs (redémarrages, bascule)
#
# Il MESURE, depuis le point de vue de chaque acteur (un client à Lomé, une application, la
# console…), et PROVOQUE ce qu'il vérifie : il arrête une application, tente les connexions
# interdites, redémarre des machines, dépose des objets avec les clés de l'application.
set -uo pipefail
export MSYS_NO_PATHCONV=1
PALIER=${1:-1}; RAPIDE=0; [ "${2:-}" = --rapide ] && RAPIDE=1
RACINE=$(cd "$(dirname "$0")/.." && pwd)
RENDU=$RACINE/rendu/palier-$PALIER

OK=0; KO=0
vert()  { printf '  \033[32m✔\033[0m %s\n' "$1"; OK=$((OK + 1)); }
rouge() { printf '  \033[31m✘\033[0m %s\033[2m  → %s\033[0m\n' "$1" "$2"; KO=$((KO + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
info()  { printf '  \033[2m• %s\033[0m\n' "$1"; }
critere() { local l=$1 i=$2; shift 2; if "$@" >/dev/null 2>&1; then vert "$l"; else rouge "$l" "$i"; fi; }
sur() { local m=$1; shift; timeout 60 docker exec "$m" bash -c "$*"; }      # sur <machine> <commande>
sur_long() { local m=$1; shift; timeout 300 docker exec "$m" bash -c "$*"; }
# sauts <machine> <destination> : les routeurs traversés, un par saut. traceroute -I (ICMP) : par
# défaut il envoie de l'UDP vers des ports élevés, qu'un pare-feu en « policy drop » jette sans
# répondre. 3 sondes par saut : le noyau limite le débit de ses ICMP « time exceeded ».
sauts() { sur "$1" "traceroute -I -n -q3 -w1 $2" 2>/dev/null | awk 'NR > 1 {for (i = 2; i <= NF; i++) if ($i ~ /^[0-9.]+$/) {print $i; break}}' | paste -sd' '; }

# ------------------------------------------------------------------------------ préalables
case $PALIER in
    1) machines="backbone dns-racine client console edge passerelle lb ns1 app1 app2 db stockage" ;;
    2) machines="backbone dns-racine client console s3 edge passerelle lb ns1 db stockage coffre
                 passerelle-lome lb-lome ns2 db-lome supervision" ;;   # (+ les instances d'application : voir palier2)
    3) machines="backbone dns-racine client console s3 edge passerelle lb ns1 db stockage coffre
                 passerelle-lome lb-lome ns2 db-lome supervision transit-b rs-ixp fai-lome circuit" ;;
    *) machines="" ;;
esac
for m in $machines; do
    [ "$(docker inspect -f '{{.State.Running}}' "$m" 2>/dev/null)" = true ] \
        || { echo "La machine $m ne tourne pas (palier $PALIER : voir palier-$PALIER.md)" >&2; exit 2; }
done

# ============================================================================ PALIER 1
palier1() {
section "Palier 1 — Adressage, VLAN et routage (M2, M4, M5)"
critere "passerelle : baie.20 est le VLAN 802.1Q 20, en 10.0.2.1/24" "networkd : .netdev Kind=vlan Id=20 ; Address=" \
    sur passerelle "ip -d link show baie.20 | grep -q 'vlan protocol 802.1Q id 20' && ip -4 -br addr show baie.20 | grep -q 10.0.2.1/24"
critere "passerelle : baie.30 est le VLAN 802.1Q 30, en 10.0.3.1/24" "idem, VLAN 30" \
    sur passerelle "ip -d link show baie.30 | grep -q 'vlan protocol 802.1Q id 30' && ip -4 -br addr show baie.30 | grep -q 10.0.3.1/24"
for x in "app1 20 10.0.2.11" "app2 20 10.0.2.12" "db 30 10.0.3.10" "stockage 30 10.0.3.20"; do
    set -- $x
    critere "$1 : dans le VLAN $2 ($3), route par défaut via la passerelle du VLAN" "sous-interface baie.$2 ; Gateway=10.0.$(($2 / 10)).1" \
        sur "$1" "ip -d link show baie.$2 | grep -q 'id $2' && ip -4 -br addr show baie.$2 | grep -q '$3/24' && ip route show default | grep -q 'via 10.0.$(($2 / 10)).1'"
done
for m in lb ns1; do
    critere "$m : route par défaut via 10.0.1.1" "Gateway=10.0.1.1" sur "$m" "ip route show default | grep -q 'via 10.0.1.1'"
done
critere "passerelle : routage activé (IPv4 et IPv6), route par défaut vers la dorsale" "sysctl ip_forward, forwarding ; Gateway=203.0.113.1" \
    sur passerelle "[ \$(sysctl -n net.ipv4.ip_forward) = 1 ] && [ \$(sysctl -n net.ipv6.conf.all.forwarding) = 1 ] && ip route show default | grep -q 203.0.113.1"
critere "Les VLAN sont étanches : app1 atteint db en passant par la passerelle (2 sauts)" "deux VLAN = deux réseaux : on route entre eux" \
    test "$(sauts app1 10.0.3.10)" = "10.0.2.1 10.0.3.10"
sur passerelle "rm -f /tmp/v.txt; timeout 10 tcpdump -eni baie -c 2 'vlan and icmp' > /tmp/v.txt 2>/dev/null &"; sleep 2
sur app1 "ping -c3 -i 0.3 -W1 10.0.3.10 >/dev/null" || true; sleep 1
critere "Le trunk porte des trames étiquetées : 802.1Q vu sur le lien « baie » de la passerelle" "tcpdump -e -i baie vlan : le trafic app ↔ données traverse le trunk" \
    sur passerelle "grep -q '802.1Q' /tmp/v.txt"
critere "Depuis Lomé, www.marche.test est à 2 sauts : le routeur du FAI, puis votre passerelle" "traceroute -I ; DNAT sur 203.0.113.10" \
    test "$(sauts client 203.0.113.10)" = "192.0.2.1 203.0.113.10"

section "Palier 1 — IPv6 (M3)"
critere "app1 : adresse ULA dans fd00:4d41:5243:20::/64" "Address= ou SLAAC" \
    sur app1 "ip -6 -br addr show baie.20 | grep -q 'fd00:4d41:5243:20:'"
critere "app1 : route IPv6 par défaut APPRISE par annonce de routeur (proto ra)" "IPv6SendRA sur la passerelle (ou radvd), IPv6AcceptRA sur app1" \
    sur app1 "ip -6 route show default | grep -q 'proto ra'"
critere "app1 → db en IPv6, à travers la passerelle" "forwarding IPv6, ICMPv6 autorisé" \
    sur app1 "ping -6 -c2 -W2 fd00:4d41:5243:30::10"
critere "db.marche.test a un AAAA, et PostgreSQL y répond en IPv6 depuis app1" "publier un AAAA, c'est promettre l'IPv6 : pare-feux, ACL, listen_addresses, pg_hba" \
    sur app1 "a=\$(dig +short AAAA db.marche.test | head -1); [ -n \"\$a\" ] && timeout 5 bash -c \"</dev/tcp/\$a/5432\""

section "Palier 1 — NAT (M10)"
sur client "timeout 20 socat TCP-LISTEN:9999,reuseaddr SYSTEM:'echo \$SOCAT_PEERADDR' >/dev/null 2>&1 &" ; sleep 1
src=$(sur app1 "timeout 5 socat - TCP:192.0.2.50:9999" 2>/dev/null | tr -d '\r\n')
critere "SNAT : app1 sort sur Internet avec l'adresse publique (vue de Lomé : ${src:-rien})" "masquerade/snat vers 203.0.113.10 ; la dorsale jette les adresses privées" \
    test "$src" = 203.0.113.10
critere "SNAT : db (sous-réseau privé, ACL sans état) sort aussi (HTTPS vers 1.1.1.1)" "ACL : sortie 443 ET retour" \
    sur db "curl -s -o /dev/null -m 10 https://1.1.1.1"
critere "DNAT : 203.0.113.10:443 mène au répartiteur, 203.0.113.10:53 au DNS" "dnat to 10.0.1.10 / 10.0.1.53" \
    sur client "curl -s -o /dev/null -m 10 https://www.marche.test/ && dig +short +time=3 @203.0.113.10 www.marche.test | grep -q 203.0.113.10"

section "Palier 1 — Security groups (avec état) et ACL (sans état) (M10, M19)"
critere "app1:8000 refusé à app2 (même VLAN : c'est le pare-feu d'app1 qui décide)" "SG d'app1 : 8000 depuis lb seulement" \
    sur app2 "! timeout 4 bash -c '</dev/tcp/10.0.2.11/8000'"
critere "app1:8000 refusé à ns1 (même sous-réseau public que lb)" "une source précise, pas un sous-réseau" \
    sur ns1 "! timeout 4 bash -c '</dev/tcp/10.0.2.11/8000'"
critere "db:5432 ouvert à app1, fermé à stockage (même VLAN) et à lb" "SG de db + ACL" \
    bash -c "docker exec app1 timeout 4 bash -c '</dev/tcp/10.0.3.10/5432' && ! docker exec stockage timeout 4 bash -c '</dev/tcp/10.0.3.10/5432' && ! docker exec lb timeout 4 bash -c '</dev/tcp/10.0.3.10/5432'"
critere "Stockage : l'API S3 (8333) ouverte aux applications, rien d'autre (console d'admin 23646 fermée)" "SG de stockage" \
    sur app1 "timeout 4 bash -c '</dev/tcp/10.0.3.20/8333' && ! timeout 4 bash -c '</dev/tcp/10.0.3.20/23646'"
acl=$(sur passerelle "nft list ruleset" 2>/dev/null | awk '/chain/ && /acl|nacl|donnees/ {f=1} f {print} /^\t}/ {f=0}')
critere "ACL du sous-réseau données SANS ÉTAT : ses règles n'utilisent pas le suivi de connexion" "une chaîne dédiée à baie.30, sans « ct state » : chaque sens explicitement" \
    bash -c "[ -n \"\$1\" ] && ! grep -q 'ct state' <<< \"\$1\"" _ "$acl"
critere "ACL : les retours de la base vers les applications sont autorisés (ports éphémères)" "sans état : le retour n'est PAS automatique" \
    bash -c "grep -qE 'sport 5432' <<< \"\$1\"" _ "$acl"
critere "SSH fermé depuis Internet (203.0.113.10:22)" "22 : depuis le VPN seulement" \
    sur client "! timeout 4 bash -c '</dev/tcp/203.0.113.10/22'"
critere "SSH vers app1 refusé depuis ns1 (hors VPN)" "SG : 22 depuis 10.99.0.0/24 seulement" \
    sur ns1 "! timeout 4 bash -c '</dev/tcp/10.0.2.11/22'"

section "Palier 1 — DNS (M7)"
critere "Registre : marche.test délégué à ns1.marche.test, avec glue 203.0.113.10" "./lab/docker/lab.sh registre deleguer marche.test ns1.marche.test 203.0.113.10" \
    sur client "dig +norec @192.0.2.54 marche.test NS | grep -q 'ns1.marche.test.*203.0.113.10' || dig +norec @192.0.2.54 marche.test NS | grep -A3 ADDITIONAL | grep -q 203.0.113.10"
critere "Résolution depuis Lomé (résolveur du FAI) : www → 203.0.113.10, static → 192.0.2.80" "vue externe de ns1" \
    sur client "[ \"\$(dig +short www.marche.test)\" = 203.0.113.10 ] && [ \"\$(dig +short static.marche.test)\" = 192.0.2.80 ]"
critere "ns1 répond en faisant autorité (aa) et refuse de résoudre pour les autres (REFUSED)" "recursion no" \
    sur client "dig @203.0.113.10 www.marche.test | grep -q 'flags: qr aa' && dig @203.0.113.10 ns.tld.test | grep -q REFUSED"
critere "Split-horizon : dans le VPC, www → 10.0.1.10 et app1 → 10.0.2.11" "vue interne (match-clients 10.0.0.0/16)" \
    sur app2 "[ \"\$(dig +short www.marche.test)\" = 10.0.1.10 ] && [ \"\$(dig +short app1.marche.test)\" = 10.0.2.11 ]"
critere "Aucun nom interne ne fuit sur Internet : app1.marche.test inconnu vu de Lomé" "les noms privés restent dans la vue interne" \
    sur client "dig app1.marche.test | grep -q NXDOMAIN"
critere "Le résolveur du VPC (10.0.2.1) résout les noms du lab ; celui des machines du VPC est le vôtre" "unbound : local-zone \"test.\" nodefault ; stub-zone" \
    sur app1 "grep -q '^nameserver 10.0.2.1' /etc/resolv.conf && dig +short @10.0.2.1 ns.tld.test | grep -q 192.0.2.54"
critere "SOA : TTL négatif (minimum) de 1 h au plus" "le dernier champ du SOA : un NXDOMAIN est gardé en cache aussi longtemps" \
    sur client "[ \$(dig +short @203.0.113.10 marche.test SOA | awk '{print \$7}') -le 3600 ]"
critere "Le domaine qui n'envoie pas de courriel le dit : SPF « -all »" "TXT \"v=spf1 -all\"" \
    sur client "dig +short marche.test TXT | grep -q 'v=spf1 -all'"

section "Palier 1 — HTTP et TLS (M8, M9)"
chaine=$(sur client "echo | timeout 10 openssl s_client -connect 203.0.113.10:443 -servername www.marche.test -showcerts 2>/dev/null")
critere "Le client de Lomé valide le certificat avec VOTRE racine seule (code 0)" "racine installée chez le client (update-ca-certificates)" \
    grep -q 'Verify return code: 0' <<< "$chaine"
critere "Chaîne servie : la feuille PUIS l'intermédiaire (2 certificats, pas la racine)" "cat feuille.crt intermediaire.crt > chaine" \
    test "$(grep -c 'BEGIN CERTIFICATE' <<< "$chaine")" -eq 2
feuille=$(sur client "echo | timeout 10 openssl s_client -connect 203.0.113.10:443 -servername www.marche.test 2>/dev/null | openssl x509 -noout -text")
critere "Feuille : SAN www.marche.test, usage serverAuth, validité ≤ 200 jours" "subjectAltName, extendedKeyUsage ; plafond des AC publiques depuis mars 2026 (CA/B Forum SC-081) : 200 j, puis 100, puis 47" \
    bash -c "grep -q 'DNS:www.marche.test' <<< \"\$1\" && grep -q 'TLS Web Server Authentication' <<< \"\$1\" && \
             d1=\$(date -d \"\$(sed -n 's/.*Not Before: //p' <<< \"\$1\")\" +%s) && d2=\$(date -d \"\$(sed -n 's/.*Not After : //p' <<< \"\$1\")\" +%s) && \
             [ \$(( (d2 - d1) / 86400 )) -le 200 ]" _ "$feuille"
critere "L'intermédiaire est une AC (CA:TRUE) qui ne peut pas en créer d'autres (pathlen 0)" "basicConstraints=critical,CA:TRUE,pathlen:0" \
    bash -c "awk '/BEGIN CERT/{n++} n==2' <<< \"\$1\" | openssl x509 -noout -ext basicConstraints | grep -q 'CA:TRUE, pathlen:0'" _ "$chaine"
# Chaque serveur ne détient QUE la clé de son propre certificat : ni celle de la racine, ni celle
# de l'intermédiaire (elles restent sur la console). On compare chaque clé privée trouvée sur la
# machine à la clé publique du certificat qu'elle présente réellement.
cles_seules() {   # cles_seules <machine> <nom servi>
    local pub f p; pub=$(sur client "echo | timeout 10 openssl s_client -connect $2:443 -servername $2 2>/dev/null | openssl x509 -noout -pubkey")
    [ -n "$pub" ] || return 1
    for f in $(sur "$1" "grep -rlE 'BEGIN (EC |RSA )?PRIVATE KEY' /etc /root 2>/dev/null | grep -v -e '^/etc/ssh/' -e snakeoil"); do
        p=$(sur "$1" "openssl pkey -in $f -pubout 2>/dev/null"); [ -z "$p" ] || [ "$p" = "$pub" ] || return 1
    done
}
critere "lb et edge ne détiennent que la clé de LEUR certificat (racine et intermédiaire restent sur la console)" "une AC hors ligne : sa clé ne va sur aucun serveur" \
    bash -c "$(declare -f sur cles_seules); cles_seules lb www.marche.test && cles_seules edge static.marche.test"
critere "TLS 1.3 accepté, TLS 1.1 refusé par le serveur" "ssl-min-ver TLSv1.2 (test en @SECLEVEL=0 : c'est le serveur qui refuse)" \
    sur client "echo | timeout 10 openssl s_client -connect 203.0.113.10:443 -servername www.marche.test -tls1_3 2>/dev/null | grep -q 'TLSv1.3' && \
               ! (echo | timeout 10 openssl s_client -connect 203.0.113.10:443 -servername www.marche.test -tls1_1 -cipher 'DEFAULT@SECLEVEL=0' 2>/dev/null | grep -q 'Cipher is [A-Z]')"
critere "HTTP/2 négocié (ALPN h2)" "alpn h2,http/1.1" \
    sur client "[ \$(curl -s -o /dev/null -w '%{http_version}' https://www.marche.test/api/products) = 2 ]"
critere "http:// → 301 vers https://, et en-tête HSTS" "redirect scheme https code 301 ; Strict-Transport-Security" \
    sur client "curl -s -o /dev/null -w '%{http_code} %{redirect_url}' http://www.marche.test/ | grep -q '^301 https://' && curl -sI https://www.marche.test/ | grep -qi '^strict-transport-security'"
critere "/admin refusé (403)" "http-request deny if { path_beg /admin }" \
    sur client "[ \$(curl -s -o /dev/null -w '%{http_code}' https://www.marche.test/admin/) = 403 ]"
critere "Un gros objet (400 Ko) arrive EN ENTIER à Lomé, depuis l'origine, en moins de 10 s" "petites réponses OK mais grosses bloquées ? tracepath, ping -M do -s 1472 : MTU et ICMP « frag needed »" \
    sur client "[ \$(curl -s -o /dev/null -m 10 -w '%{size_download}' https://www.marche.test/static/catalogue.jpg) = 400000 ]"

section "Palier 1 — Répartition de charge L7 (M11)"
stats() { sur lb "echo 'show stat' | socat stdio /run/haproxy/admin.sock" 2>/dev/null; }
s=$(stats)
critere "HAProxy : app1 et app2 UP, contrôle de santé HTTP actif" "option httpchk GET /healthz" \
    bash -c "grep -q '^[^,]*,app1,.*,UP,' <<< \"\$1\" && grep -q '^[^,]*,app2,.*,UP,' <<< \"\$1\" && docker exec lb grep -q httpchk /etc/haproxy/haproxy.cfg" _ "$s"
avant=$(awk -F, '$2=="app1"||$2=="app2" {print $2, $8}' <<< "$s")
sur client "for i in \$(seq 20); do curl -s -o /dev/null https://www.marche.test/api/products; done"
apres=$(awk -F, '$2=="app1"||$2=="app2" {print $2, $8}' <<< "$(stats)")
critere "20 requêtes depuis Lomé : les deux serveurs en ont reçu" "balance roundrobin/leastconn" \
    bash -c 'join <(sort <<< "$1") <(sort <<< "$2") | awk "\$3 > \$2 {n++} END {exit n != 2}"' _ "$avant" "$apres"
critere "Routage L7 : /static/ est servi par le stockage objet (Cache-Control d'S3)" "use_backend … if { path_beg /static/ } ; set-path" \
    sur client "curl -sI https://www.marche.test/static/logo.svg | grep -qi '^cache-control: .*max-age'"
if [ "$RAPIDE" -eq 0 ]; then
    sur app2 "systemctl stop marche.target"; sleep 6
    ko=$(sur client "k=0; for i in \$(seq 20); do curl -sf -o /dev/null -m 5 https://www.marche.test/api/products || k=\$((k+1)); done; echo \$k")
    critere "app2 arrêtée : le site répond toujours (échecs : ${ko:-?}/20) et HAProxy la voit DOWN" "le contrôle de santé retire le serveur" \
        bash -c "[ \"\${1:-99}\" -le 1 ] && grep -q '^[^,]*,app2,.*,DOWN' <<< \"\$2\"" _ "$ko" "$(stats)"
    sur app2 "systemctl start marche.target"; sleep 8
fi

section "Palier 1 — CDN (M12)"
# Temps de TRANSFERT, sans la résolution DNS : quand le TTL a expiré, le résolveur de Lomé repart
# interroger ns1 en Europe (120 ms) — ce n'est pas le CDN qu'on mesurerait.
tps='%{time_total} %{time_namelookup}\n'
duree() { awk '{printf "%.3f", $1 - $2}'; }
sur client "curl -s -o /dev/null https://static.marche.test/catalogue.jpg" >/dev/null
h=$(sur client "curl -s -o /dev/null -D - https://static.marche.test/catalogue.jpg" | grep -i '^x-cache' | tr -d '\r')
t2=$(sur client "curl -s -o /dev/null -w '$tps' https://static.marche.test/catalogue.jpg" | duree)
critere "static.marche.test (servi à Lomé) : en cache (${h:-sans en-tête X-Cache}) et en moins de 50 ms (${t2}s)" "proxy_cache ; en-tête X-Cache ; Cache-Control de l'origine" \
    bash -c "grep -qi 'x-cache: HIT' <<< \"\$1\" && awk -v t=\"\$2\" 'BEGIN {exit !(t < 0.05)}'" _ "$h" "$t2"
to=$(sur client "curl -s -o /dev/null -w '$tps' https://www.marche.test/static/catalogue.jpg" | duree)
critere "Le CDN est plus rapide que l'origine (origine : ${to}s)" "l'origine est à 120 ms d'aller-retour" \
    awk -v a="$t2" -v b="$to" 'BEGIN {exit !(a * 5 < b)}'
critere "Le nœud CDN vérifie le certificat de l'origine" "proxy_ssl_verify on + racine" \
    sur edge "grep -rqs 'proxy_ssl_verify *on' /etc/nginx/"

section "Palier 1 — VPN d'accès distant (M13)"
sur console "ping -c1 -W3 10.99.0.1 >/dev/null" || true
critere "console : tunnel WireGuard établi (poignée de main de moins de 3 min)" "wg show ; PersistentKeepalive" \
    sur console "t=\$(wg show wg0 latest-handshakes | awk '{print \$2}' | head -1); [ -n \"\$t\" ] && [ \$((\$(date +%s) - t)) -lt 180 ]"
critere "Split tunnel : 10.0.2.11 par wg0, Internet (1.1.1.1) par le FAI" "AllowedIPs = 10.0.0.0/16, 10.99.0.0/24" \
    sur console "ip route get 10.0.2.11 | grep -q 'dev wg0' && ! ip route get 1.1.1.1 | grep -q 'dev wg0'"
critere "SSH console → app1 et → db, par le tunnel, avec une clé" "authorized_keys ; SG : 22 depuis 10.99.0.0/24" \
    sur console "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 ubuntu@10.0.2.11 true && ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 ubuntu@10.0.3.10 true"

section "Palier 1 — Stockage objet et IAM (M18, M20)"
critere "marche-statique : lecture anonyme OUI, écriture et liste anonymes NON" "politique de bucket : Principal \"*\", s3:GetObject seulement" \
    sur app1 "[ \$(curl -s -o /dev/null -w '%{http_code}' http://10.0.3.20:8333/marche-statique/logo.svg) = 200 ] && \
              [ \$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data x http://10.0.3.20:8333/marche-statique/pirate.txt) = 403 ] && \
              [ \$(curl -s -o /dev/null -w '%{http_code}' http://10.0.3.20:8333/marche-statique/) = 403 ]"
s3app() { sur app1 "set -a; . /etc/marche/s3.env; set +a; export AWS_DEFAULT_REGION=us-east-1 AWS_ENDPOINT_URL=http://10.0.3.20:8333; $*"; }
critere "Clés de l'application : dépôt et relecture d'une facture dans marche-factures" "politique : s3:PutObject + s3:GetObject sur marche-factures/*" \
    s3app "echo test > /tmp/f.txt && aws s3 cp /tmp/f.txt s3://marche-factures/verif.txt && aws s3 cp s3://marche-factures/verif.txt -"
critere "Clés de l'application : suppression, écriture dans marche-statique, IAM et création de bucket REFUSÉES" "moindre privilège" \
    s3app "! aws s3 rm s3://marche-factures/verif.txt && ! aws s3 cp /etc/hostname s3://marche-statique/x.txt && ! aws iam list-users && ! aws s3 mb s3://pirate"
critere "Clés de l'application : fichier lisible par root et le service seulement (pas par tous)" "chmod 640, groupe marche" \
    sur app1 "f=/etc/marche/s3.env; [ -f \$f ] && [ \$(stat -c %a \$f | cut -c3) = 0 ]"

section "Palier 1 — De bout en bout"
n1=$(sur db "runuser -u postgres -- psql -tAc 'select count(*) from orders' marche" 2>/dev/null); sleep 10
n2=$(sur db "runuser -u postgres -- psql -tAc 'select count(*) from orders' marche" 2>/dev/null)
critere "Les clients de Lomé commandent en continu (+$(( ${n2:-0} - ${n1:-0} )) commandes en 10 s)" "marche-loadgen sur client, vers https://www.marche.test" \
    test "${n2:-0}" -gt "${n1:-0}"
critere "Une commande passée depuis Lomé est enregistrée (201, ou 402 : paiement refusé — une réponse métier)" "toute la chaîne : DNS → NAT → TLS → L7 → app → base" \
    sur client "curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{\"product_id\":2,\"quantity\":1,\"payment_method\":\"mobile_money\"}' https://www.marche.test/api/orders | grep -qE '^(201|402)\$' || exit 1"

section "Palier 1 — Rendu (rendu/palier-1/)"
p=$RENDU/poignee.pcap
critere "poignee.pcap : une poignée de main TCP complète (SYN, SYN-ACK, ACK) vers www" "tcpdump -w, pendant un curl" \
    bash -c "[ -f '$p' ] && docker exec -i client tshark -r - -Y 'tcp.flags.syn==1 && tcp.flags.ack==1' 2>/dev/null < '$p' | grep -q ."
critere "poignee.pcap : un ClientHello TLS avec le nom demandé (SNI www.marche.test)" "tls.handshake.extensions_server_name" \
    bash -c "[ -f '$p' ] && docker exec -i client tshark -r - -Y 'tls.handshake.type==1' -T fields -e tls.handshake.extensions_server_name 2>/dev/null < '$p' | grep -q www.marche.test"
critere "PLAN-ADRESSAGE.md : le plan d'adressage (sous-réseaux, VLAN, IPv6)" "rendu/palier-1/PLAN-ADRESSAGE.md" \
    bash -c "grep -q '10.0.2.0/24' '$RENDU/PLAN-ADRESSAGE.md' && grep -qi 'fd00:4d41:5243' '$RENDU/PLAN-ADRESSAGE.md'"
critere "CLOUD.md : la correspondance lab ↔ AWS / GCP / Azure" "rendu/palier-1/CLOUD.md" \
    bash -c "grep -qi 'vpc' '$RENDU/CLOUD.md' && grep -qiE 'security group|pare-feu' '$RENDU/CLOUD.md'"

if [ "$RAPIDE" -eq 0 ]; then
    section "Palier 1 — Tout survit à un redémarrage"
    info "redémarrage de la passerelle et d'app2…"
    docker restart passerelle app2 >/dev/null; sleep 25
    critere "Après redémarrage : le site répond depuis Lomé, app2 est revenue dans la rotation" "systemd-networkd, nftables.conf, sysctl.d, services « enabled »" \
        bash -c "docker exec client curl -sf -o /dev/null -m 10 https://www.marche.test/api/products && sleep 5 && docker exec lb sh -c \"echo 'show stat' | socat stdio /run/haproxy/admin.sock\" | grep -q '^[^,]*,app2,.*,UP,'"
    critere "Après redémarrage : VPN, résolveur et NAT de la passerelle sont revenus" "wg-quick@wg0, unbound, nftables activés" \
        sur passerelle "systemctl is-active -q wg-quick@wg0 unbound nftables && nft list ruleset | grep -q masquerade"
fi
}

# ============================================================================ PALIER 2
# Conventions imposées par l'énoncé : le code est sur la console dans /root/p2/terraform/<couche>,
# l'état de chaque couche dans s3://marche-etat-terraform/<couche>/terraform.tfstate (chez le fournisseur).
TF=/root/p2/terraform
AWSF='AWS_DEFAULT_REGION=us-east-1 AWS_PROFILE=fournisseur AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt aws --endpoint-url https://s3.fournisseur.test'
BAO='export BAO_ADDR=https://10.0.3.30:8200 BAO_CACERT=/root/pki/racine.crt BAO_TLS_SERVER_NAME=coffre.marche.test BAO_TOKEN=$(jq -r .root_token /root/cles/bao-init.json);'
console() { timeout 300 docker exec console bash -c "$*"; }          # (terraform plan : plus de 60 s)
pgq() { sur "$1" "runuser -u postgres -- psql -d marche -tAc \"$2\""; }
primaire() { for b in db db-lome; do [ "$(pgq $b 'select pg_is_in_recovery()' 2>/dev/null)" = f ] && { echo $b; return; }; done; }
commande() { sur "$1" "curl -s -o /dev/null -m 10 -w '%{http_code}' -X POST localhost:8000/api/orders -H 'content-type: application/json' -d '{\"product_id\":1,\"quantity\":1,\"payment_method\":\"card\"}'"; }

palier2() {
# les instances d'application du moment (groupes, bleu/vert, autoscaler : leurs noms varient)
apps() { docker ps --filter label=projet=marche --filter label=role=app ${1:+--filter label=region=$1} --format '{{.Names}}' | sort; }
P3=$([ "$PALIER" -ge 3 ] && echo oui)   # (le Palier 3 rejoue ces critères : ceux qu'il change volontairement s'adaptent)
AE=$(apps europe | head -1); AL=$(apps lome | head -1); TOUTES=$(apps | paste -sd' ')
[ -n "$AE" ] && [ -n "$AL" ] || { echo "Aucune instance d'application dans l'une des régions" >&2; exit 2; }
info "applications : $TOUTES"
P=$(primaire); R=$([ "$P" = db ] && echo db-lome || echo db)
info "base primaire : ${P:-AUCUNE} — réplique : $R"

section "Palier 2 — L'infrastructure est du code (M18)"
critere "État chez le fournisseur : bucket marche-etat-terraform versionné, un état par couche" "backend « s3 », bucket créé AVANT (bootstrap), versioning" \
    console "$AWSF s3api get-bucket-versioning --bucket marche-etat-terraform | grep -q Enabled && [ \$($AWSF s3 ls s3://marche-etat-terraform --recursive | grep -c 'terraform.tfstate\$') -ge 2 ]"
for c in regions plateforme; do
    critere "couche $c : le réel est conforme au code (plan : aucun changement)" "terraform plan -detailed-exitcode = 0 ; une dérive permanente masque les vraies" \
        console "cd $TF/$c && terraform plan -input=false -lock-timeout=60s -detailed-exitcode >/dev/null"
done
# le verrou : on en pose un faux ; un plan doit refuser de démarrer
verrou=s3://marche-etat-terraform/regions/terraform.tfstate.tflock
if console "$AWSF s3 ls $verrou" >/dev/null 2>&1; then
    # (on ne touche pas à un verrou qui n'est pas le nôtre : c'est peut-être un apply en cours)
    rouge "Verrou : un verrou est DÉJÀ posé sur l'état « regions » — apply en cours, ou orphelin ?" \
          "qui ? (terraform plan affiche Who/Created) ; s'il est orphelin : terraform force-unlock <ID>"
else
    console "echo '{\"ID\":\"verifier\",\"Who\":\"correcteur\"}' > /tmp/faux.tflock && $AWSF s3 cp /tmp/faux.tflock $verrou" >/dev/null 2>&1
    critere "Verrou : un plan refuse de démarrer pendant qu'un autre tient l'état" "use_lockfile = true (ou une table de verrous)" \
        console "cd $TF/regions && terraform plan -input=false -lock-timeout=2s 2>&1 | grep -qi 'state lock'"
    console "$AWSF s3 rm $verrou" >/dev/null 2>&1
fi
n_etat=$(console "cd $TF/regions && terraform state list" 2>/dev/null | grep -c 'docker_container')
n_reel=$(docker ps -q --filter label=projet=marche | wc -l)
critere "Rien ne tourne hors du code : $n_reel machines du projet, $n_etat dans l'état Terraform" "tout est créé par Terraform — pas de « docker run » à la main" \
    test "$n_etat" -eq "$n_reel" -a "$n_reel" -ge 15
critere "Étiquettes FinOps : chaque machine porte projet, equipe, env et region" "labels du conteneur (les « tags » du cloud) : qui paie quoi" \
    bash -c "for c in \$(docker ps -q --filter label=projet=marche); do docker inspect -f '{{index .Config.Labels \"equipe\"}} {{index .Config.Labels \"env\"}} {{index .Config.Labels \"region\"}}' \$c | grep -qE '^[^ ]+ [^ ]+ [^ ]+\$' || exit 1; done"
critere "Données hors de l'instance : db, db-lome, coffre et stockage ont un volume persistant" "docker_volume (prevent_destroy) : remplacer l'instance ne perd rien" \
    bash -c "for m in db:/var/lib/postgresql db-lome:/var/lib/postgresql coffre:/var/lib/bao stockage:/var/lib; do docker inspect -f '{{range .Mounts}}{{.Type}}:{{.Destination}} {{end}}' \${m%%:*} | grep -q \"volume:\${m#*:}\" || exit 1; done"

section "Palier 2 — Deux régions, un réseau (M5, M7, M13)"
critere "Lomé en VLSM : applications 10.1.0.0/26, données 10.1.0.64/28, public 10.1.0.80/28" "des sous-réseaux à la taille du besoin" \
    sur passerelle-lome "ip -4 -br addr show baie.20 | grep -q 10.1.0.1/26 && ip -4 -br addr show baie.30 | grep -q 10.1.0.65/28 && ip -4 -br addr show pub | grep -q 10.1.0.81/28"
critere "VPN site à site : poignée de main de moins de 3 min entre les deux passerelles" "WireGuard, PersistentKeepalive" \
    sur passerelle-lome "wg show wg0 latest-handshakes | awk '{print \$2}' | while read t; do [ \$((\$(date +%s) - t)) -lt 180 ] || exit 1; done"
if [ -z "$P3" ]; then   # (au Palier 3, les régions se parlent par le circuit : critères du Palier 3)
critere "$AL (Lomé) atteint la base d'Europe par le tunnel : sa passerelle, puis celle d'Europe (10.99.0.1)" "route 10.0.0.0/16 via wg0 ; AllowedIPs" \
    grep -q '^10.1.0.1 10.99.0.1' <<< "$(sauts $AL 10.0.3.10)"
docker exec backbone sh -c 'rm -f /tmp/c.txt; timeout 8 tcpdump -ni any -c 200 "host 192.0.2.100 and host 203.0.113.10" > /tmp/c.txt 2>/dev/null &' ; sleep 1
for _ in 1 2 3; do commande $AL >/dev/null; done; sleep 2
critere "Sur la dorsale, le trafic Lomé → base n'est QUE de l'UDP chiffré (pas de PostgreSQL en clair)" "tout ce qui traverse Internet passe dans le tunnel" \
    docker exec backbone sh -c "sleep 5; grep -q 'UDP' /tmp/c.txt && ! grep -qE '\.5432[ :]' /tmp/c.txt"
fi

section "Palier 2 — DNS : deux régions, deux vues, une bascule (M8, M14)"
w=$([ -n "$P3" ] && echo www-gslb || echo www)   # (Palier 3 : www est anycast ; le GSLB reste, sous www-gslb)
critere "ns2 (Lomé) sert la vue publique : $w → www.gslb, coffre inexistant" "secondaire de la vue externe" \
    sur client "dig +short @192.0.2.100 $w.marche.test | grep -q www.gslb && dig @192.0.2.100 coffre.marche.test | grep -q NXDOMAIN"
critere "ns2 sert aussi la vue interne : Lomé résout ses noms même sans l'Europe" "une clé TSIG par vue ; le résolveur de Lomé interroge ns2 d'abord" \
    sur passerelle-lome "[ \"\$(dig +short @10.1.0.83 coffre.marche.test)\" = 10.0.3.30 ]"
critere "Transferts de zone refusés sans clé TSIG (ns1 et ns2)" "allow-transfer { key … ; }" \
    sur client "dig @203.0.113.10 axfr marche.test | grep -q 'Transfer failed' && dig @192.0.2.100 axfr marche.test | grep -q 'Transfer failed'"
critere "Même série partout : ns1 et ns2, vue publique et vue interne" "NOTIFY + transfert ; incrémenter la série" \
    bash -c "s=\$( { for v in 10.0.1.53 10.1.0.83; do docker exec passerelle-lome dig +short @\$v soa marche.test; done; for v in 203.0.113.10 192.0.2.100; do docker exec client dig +short @\$v soa marche.test; done; } | awk '{print \$3}' | sort -u); [ \$(echo \"\$s\" | grep -c .) = 1 ]"
critere "GSLB : les deux serveurs répondent, et envoient les clients vers Lomé (la plus proche)" "PowerDNS, enregistrement LUA ifportup" \
    sur client "[ \"\$(dig +short @192.0.2.101 www.gslb.marche.test)\" = 192.0.2.100 ] && [ \"\$(dig +short @203.0.113.11 www.gslb.marche.test)\" = 192.0.2.100 ]"
ip_p=$([ "$P" = db ] && echo 10.0.3.10 || echo 10.1.0.70)
critere "db.marche.test mène à la PRIMAIRE ($ip_p), dans les deux régions" "servi par le résolveur de chaque région : modifiable même si l'autre est tombée" \
    bash -c "[ \"\$(docker exec passerelle dig +short @127.0.0.1 db.marche.test)\" = $ip_p ] && [ \"\$(docker exec passerelle-lome dig +short @127.0.0.1 db.marche.test)\" = $ip_p ]"
if [ "$RAPIDE" -eq 0 ]; then
    info "panne du répartiteur de Lomé (haproxy arrêté)…"
    sur lb-lome "systemctl stop haproxy"; t=0
    until [ "$(sur client 'dig +short @203.0.113.11 www.gslb.marche.test')" = 203.0.113.10 ] || [ $t -ge 90 ]; do sleep 3; t=$((t + 3)); done
    critere "GSLB : Lomé en panne → www part en Europe (en ${t}s, moins de 60 s)" "ifportup vérifie le port 443 de chaque région" test "$t" -lt 60
    sur lb-lome "systemctl start haproxy"; t=0
    until [ "$(sur client 'dig +short @203.0.113.11 www.gslb.marche.test')" = 192.0.2.100 ] || [ $t -ge 90 ]; do sleep 3; t=$((t + 3)); done
    critere "GSLB : Lomé réparée → www y revient (en ${t}s)" "pas de retour manuel à faire" test "$t" -lt 60
fi

section "Palier 2 — Secrets (M15)"
critere "Aucun mot de passe de base sur les applications : des comptes temporaires (v-…)" "moteur « database » d'OpenBao ; rien dans le user data" \
    bash -c "for a in $TOUTES; do docker exec \$a grep -q 'DATABASE_URL=postgresql://v-' /etc/marche/marche.env && ! docker exec \$a grep -qiE 'mdp|password|secret' /lab/parametres.sh || exit 1; done"
critere "Les comptes temporaires expirent (VALID UNTIL, au plus 24 h)" "default_ttl / max_ttl du rôle" \
    test "$(pgq "$P" "select count(*) from pg_roles where rolname like 'v-%' and (rolvaliduntil is null or rolvaliduntil > now() + interval '25 hours')")" = 0
critere "Coffre : descellé, en TLS avec votre AC, joignable depuis une application" "listener TLS ; certificat coffre.marche.test" \
    sur $AE "curl -sf --cacert /etc/bao-agent/racine.crt https://coffre.marche.test:8200/v1/sys/health | grep -q '\"sealed\":false'"
# (Palier 3 : le répartiteur a besoin du coffre — il y obtient son identité de service)
critere "Coffre : fermé à ce qui n'en a pas besoin (${P3:+Internet}${P3:-le répartiteur, Internet})" "pare-feu du coffre + ACL du sous-réseau de données" \
    bash -c "${P3:+true || }! docker exec lb timeout 3 bash -c '</dev/tcp/10.0.3.30/8200' 2>/dev/null && ! docker exec client timeout 3 bash -c '</dev/tcp/10.0.3.30/8200' 2>/dev/null"
# un compte temporaire à nous (jq : sur la console — l'hôte n'en a pas forcément)
read -r u pw bail <<< "$(console "$BAO bao read -format=json base/creds/app | jq -r '[.data.username, .data.password, .lease_id] | join(\" \")'" 2>/dev/null)"
sur $AE "rm -f /tmp/session.rc; (PGPASSWORD='$pw' psql -h db.marche.test -U '$u' -d marche -tAc 'select pg_sleep(40)' >/dev/null 2>&1; echo \$? > /tmp/session.rc) &" ; sleep 3
console "$BAO bao lease revoke '$bail'" >/dev/null 2>&1; sleep 8
critere "Révocation : le compte disparaît de la base ET sa session ouverte est coupée" "revocation_statements : pg_terminate_backend + DROP ROLE (PostgreSQL 16 : GRANT du rôle à bao d'abord)" \
    bash -c "[ -n '$u' ] && [ \"\$(docker exec $P runuser -u postgres -- psql -tAc \"select count(*) from pg_roles where rolname='$u'\")\" = 0 ] && [ \"\$(docker exec $AE cat /tmp/session.rc 2>/dev/null)\" != '' ] && [ \"\$(docker exec $AE cat /tmp/session.rc)\" != 0 ]"

section "Palier 2 — Données : réplication et sauvegardes (M16)"
critere "Réplication en flux entre les régions ($P → $R), retard de moins de 5 s" "pg_basebackup -R -S <slot> ; pg_hba « replication »" \
    test "$(pgq "$P" "select count(*) from pg_stat_replication where state='streaming' and coalesce(replay_lag, '0') < interval '5 seconds'")" = 1
critere "La réplique refuse les écritures" "hot standby : lecture seule" \
    bash -c "docker exec $R runuser -u postgres -- psql -d marche -tAc 'create table pirate(x int)' 2>&1 | grep -q 'read-only'"
critere "Sauvegardes chez le fournisseur : dépôt sain, chiffré (aes-256-cbc), une complète de moins de 26 h" "pgBackRest, repo S3, repo1-cipher-type ; minuteries" \
    sur "$P" "runuser -u postgres -- pgbackrest --stanza=marche info --output=json | jq -e '.[0].status.code == 0 and .[0].cipher == \"aes-256-cbc\" and ([.[0].backup[] | select(.type == \"full\") | .timestamp.stop] | max) > (now - 93600)'"
critere "Archivage continu : un WAL archivé il y a moins de 3 min, aucun échec en attente" "archive_command + archive_timeout (le RPO des sauvegardes)" \
    test "$(pgq "$P" "select (last_archived_time > now() - interval '3 minutes') and (last_failed_time is null or last_failed_time < last_archived_time) from pg_stat_archiver")" = t
critere "Le fournisseur ne stocke que du chiffré (« Salted__ » en tête des fichiers)" "chiffrement CÔTÉ CLIENT : la clé ne quitte pas le coffre" \
    console "k=\$($AWSF s3 ls s3://marche-sauvegardes/ --recursive | awk '/\\.gz\$/ {print \$4}' | tail -1); [ -n \"\$k\" ] && $AWSF s3 cp \"s3://marche-sauvegardes/\$k\" - | head -c 8 | grep -q Salted__"
critere "Moindre privilège : la clé de pgBackRest ne voit pas l'état Terraform" "politique IAM limitée au bucket des sauvegardes" \
    console "$BAO k=\$(bao kv get -format=json kv/marche/pgbackrest | jq -r .data.data.access_key); s=\$(bao kv get -format=json kv/marche/pgbackrest | jq -r .data.data.secret_key); \
             ! AWS_ACCESS_KEY_ID=\$k AWS_SECRET_ACCESS_KEY=\$s AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt aws --endpoint-url https://s3.fournisseur.test s3 ls s3://marche-etat-terraform >/dev/null 2>&1 \
             && AWS_ACCESS_KEY_ID=\$k AWS_SECRET_ACCESS_KEY=\$s AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt aws --endpoint-url https://s3.fournisseur.test s3 ls s3://marche-sauvegardes/ >/dev/null"
if [ "$RAPIDE" -eq 0 ]; then
    # (juste après un premier déploiement, « il y a 2 min » peut précéder la toute première sauvegarde
    #  complète : aucune restauration ne remonte avant elle — vécu, 0 commande restaurée. On attend.)
    premiere=$(sur "$P" "runuser -u postgres -- pgbackrest --stanza=marche info --output=json | jq '[.[0].backup[] | select(.type == \"full\") | .timestamp.stop] | min // 0'" 2>/dev/null)
    if [ "${premiere:-0}" -gt $(( $(date +%s) - 140 )) ]; then
        info "la première sauvegarde complète a moins de 2 min : on attend qu'elle en ait plus…"
        until [ "$(date +%s)" -gt $(( ${premiere:-0} + 140 )) ]; do sleep 5; done
    fi
    info "restauration d'essai : l'état d'il y a 2 min, dans une instance jetable (port 5499)…"
    n=$(sur_long "$P" "cible=\$(date -u -d '-2 min' '+%F %T+00'); d=/var/tmp/verif-restauration; rm -rf \$d; install -d -o postgres -m 700 \$d
        runuser -u postgres -- pgbackrest --stanza=marche --pg1-path=\$d --type=time \"--target=\$cible\" --target-action=promote restore >/dev/null 2>&1 || exit 1
        runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl -D \$d -w -t 120 -l /var/tmp/verif.log -o \"-c config_file=/etc/postgresql/16/main/postgresql.conf -c data_directory=\$d -c port=5499 -c listen_addresses='' -c archive_mode=off -c external_pid_file='' -c hba_file=/etc/postgresql/16/main/pg_hba.conf -c ident_file=/etc/postgresql/16/main/pg_ident.conf\" start >/dev/null 2>&1 || exit 1
        for _ in \$(seq 60); do [ \"\$(runuser -u postgres -- psql -p 5499 -tAc 'select pg_is_in_recovery()' 2>/dev/null)\" = f ] && break; sleep 1; done
        runuser -u postgres -- psql -p 5499 -d marche -tAc 'select count(*) from orders'
        runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl -D \$d -m fast stop >/dev/null 2>&1; rm -rf \$d" 2>/dev/null | tail -1)
    critere "Une sauvegarde qui n'est pas restaurée n'est pas une sauvegarde : restauration à T−2 min réussie (${n:-0} commandes)" "pgbackrest restore --type=time ; WAL archivés" \
        test "${n:-0}" -gt 0
fi

section "Palier 2 — Flotte : groupes, découverte, déploiement, mise à l'échelle (M12, M18)"
# Conventions imposées : regions/flotte.auto.tfvars.json (variable « groupes » : taille et version de
# <région>-<couleur>) et trafic/flotte.auto.tfvars.json (variables « couleur_active » et « retrait » :
# les instances à ne plus publier, avant de les éteindre).
serveurs() { sur "$1" "echo 'show servers state applications' | socat stdio /run/haproxy/admin.sock" | awk 'NR > 2 && $5 ~ /^[0-9.]+$/ && $6 == 2 {print $5}' | sort | paste -sd' '; }
for r in europe lome; do
    lbr=$([ "$r" = europe ] && echo lb || echo lb-lome)
    publie=$(sur client "dig +short @$([ "$r" = europe ] && echo 203.0.113.11 || echo 192.0.2.101) apps-$r.gslb.marche.test" 2>/dev/null | sort | paste -sd' ')
    critere "$r : le répartiteur a DÉCOUVERT ses instances dans le DNS (${publie:-rien de publié})" "server-template + resolvers ; apps-$r.gslb.marche.test publié par la couche trafic" \
        test -n "$publie" -a "$(serveurs "$lbr")" = "$publie"
done
critere "Les instances d'un groupe portent sa version, et Lomé est servi par la version du groupe actif" "étiquettes groupe/version ; X-Marche-Version" \
    bash -c "g=lome-\$(docker exec console jq -r .couleur_active.lome $TF/trafic/flotte.auto.tfvars.json); v=\$(docker exec console jq -r \".groupes[\\\"\$g\\\"].version\" $TF/regions/flotte.auto.tfvars.json)
             [ -n \"\$v\" ] && [ \"\$(docker ps --filter label=groupe=\$g --format '{{.Label \"version\"}}' | sort -u)\" = \"\$v\" ] \
             && docker exec client curl -s -D - -o /dev/null https://www.marche.test/api/products | grep -qi \"^x-marche-version: \$v\""
if [ "$RAPIDE" -eq 0 ]; then
    g=lome-$(console "jq -r .couleur_active.lome $TF/trafic/flotte.auto.tfvars.json"); t=$(console "jq -r '.groupes[\"$g\"].taille' $TF/regions/flotte.auto.tfvars.json")
    id_lb=$(docker inspect -f '{{.Id}}' lb-lome)
    info "mise à l'échelle : $g passe de $t à $((t + 1)) instances, pendant qu'un client commande…"
    sur client "rm -f /tmp/e.txt; (end=\$((SECONDS + 150)); while [ \$SECONDS -lt \$end ]; do curl -s -o /dev/null -m 5 -w '%{http_code}\n' https://www.marche.test/api/products >> /tmp/e.txt; sleep 0.3; done) >/dev/null 2>&1 &"
    agrandir() { console "f=$TF/regions/flotte.auto.tfvars.json; jq '.groupes[\"$g\"].taille = $1' \$f > \$f.n && mv \$f.n \$f
                          cd $TF/regions && terraform apply -input=false -auto-approve >/dev/null && cd ../trafic && terraform apply -input=false -auto-approve >/dev/null"; }
    agrandir $((t + 1)); sleep 20
    critere "Agrandir : $((t + 1)) instances dans la rotation de Lomé, SANS remplacer le répartiteur" "découverte DNS : la liste des instances n'est pas dans la configuration du répartiteur" \
        bash -c "[ \$(echo '$(serveurs lb-lome)' | wc -w) = $((t + 1)) ] && [ \"\$(docker inspect -f '{{.Id}}' lb-lome)\" = '$id_lb' ]"
    # réduire comme il se doit : dépublier (variable « retrait » de la couche trafic), laisser les requêtes
    # en cours se terminer, PUIS éteindre. (Éteindre d'abord : une requête déjà partie vers l'instance
    # qui s'arrête reste sans réponse — le répartiteur ne rejoue pas une requête envoyée.)
    console "f=$TF/trafic/flotte.auto.tfvars.json; jq '.retrait = [\"app-$g-$((t + 1))\"]' \$f > \$f.n && mv \$f.n \$f
             cd $TF/trafic && terraform apply -input=false -auto-approve >/dev/null"; sleep 15
    agrandir "$t"
    console "f=$TF/trafic/flotte.auto.tfvars.json; jq '.retrait = []' \$f > \$f.n && mv \$f.n \$f; cd $TF/trafic && terraform apply -input=false -auto-approve >/dev/null"
    sleep 25
    sur client "sleep 1; true"
    critere "Agrandir puis réduire : aucune erreur vue par le client ($(sur client "grep -vc '^200\$' /tmp/e.txt" 2>/dev/null) sur $(sur client "wc -l < /tmp/e.txt" 2>/dev/null))" "retry-on conn-failure + redispatch ; publier AVANT de router, dépublier AVANT d'éteindre" \
        sur client "! grep -qv '^200\$' /tmp/e.txt"
fi

section "Palier 2 — Supervision (M17)"
# (après une mise à l'échelle, la découverte DNS de Prometheus met jusqu'à 15 s à suivre : on lui en laisse 60)
for _ in $(seq 12); do
    cibles=$(sur supervision "curl -s localhost:9090/api/v1/targets" 2>/dev/null)
    [ "$(echo "$cibles" | grep -o '"health":"up"' | wc -l)" -ge 12 ] \
        && [ "$(echo "$cibles" | grep -o '"health":"up"' | wc -l)" = "$(echo "$cibles" | grep -o '"health":' | wc -l)" ] && break
    sleep 5
done
critere "Prometheus (à Lomé) : toutes ses cibles répondent — $(echo "$cibles" | grep -o '"health":"up"' | wc -l) sur $(echo "$cibles" | grep -o '"health":' | wc -l)" "répartiteurs, applications (découvertes par DNS), bases, sondes du site, du coffre et du GSLB" \
    bash -c "[ $(echo "$cibles" | grep -o '"health":"up"' | wc -l) -ge 12 ] && [ $(echo "$cibles" | grep -o '"health":"up"' | wc -l) = $(echo "$cibles" | grep -o '"health":' | wc -l) ]"
# (juste après un déploiement qui remplace les machines, ou un passage précédent du correcteur, des
#  alertes légitimes sont encore actives : on laisse au système 5 minutes pour retrouver le repos)
# (Palier 3 : les alertes de BUDGET d'erreur restent légitimement actives jusqu'à 30 min après de
#  vraies erreurs — celles d'un passage précédent, d'un déploiement — ce ne sont pas des fausses alarmes)
alertes_graves() { sur supervision "curl -s localhost:9093/api/v2/alerts?active=true | jq -e '[.[] | select(.labels.gravite == \"critique\" or .labels.gravite == \"majeure\") | select(.labels.alertname | startswith(\"BudgetErreur\") | not)] | length > 0' >/dev/null"; }
t=0; while alertes_graves && [ $t -lt 300 ]; do sleep 10; t=$((t + 10)); done
[ $t -gt 0 ] && info "des alertes graves étaient actives (déploiement ou passage précédent) : retombées en ${t} s"
au_repos() { ! alertes_graves; }
critere "Au repos, aucune alerte critique ou majeure" "des alertes qui sonnent pour rien, on finit par ne plus les écouter" au_repos
critere "Les règles d'alerte couvrent site, erreurs, capacité, coffre, réplication, archivage" "rule_files ; promtool check rules" \
    sur supervision "r=\$(curl -s localhost:9090/api/v1/rules); for a in SiteIndisponible ErreursServeur CapaciteReduite CoffreIndisponible RepliqueEnRetard ArchivageEnPanne; do echo \"\$r\" | grep -q \"\\\"\$a\\\"\" || exit 1; done"

if [ "$RAPIDE" -eq 0 ]; then
    section "Palier 2 — Qualité de service sur le lien intercontinental (M4)"
    rtt() { sur "$AL" 'for i in $(seq 25); do s=$(date +%s%N); exec 3<>/dev/tcp/10.0.3.10/5432 && e=$(date +%s%N); exec 3>&-; echo $(( (e - s) / 1000000 )); sleep 0.2; done' \
            | sort -n | awk '{v[NR] = $1} END {print v[int(NR * 0.95)]}'; }
    repos=$(rtt)
    info "transfert massif Europe → Lomé (8 téléchargements en parallèle) pendant 35 s…"
    sur client 'for j in $(seq 8); do (end=$((SECONDS + 35)); while [ $SECONDS -lt $end ]; do curl -s -o /dev/null https://www.marche.test/static/catalogue.jpg; done) & done >/dev/null 2>&1 &'
    sleep 5; charge=$(rtt); sleep 25
    critere "Pendant un transfert massif, l'aller-retour vers la base reste court : p95 ${charge:-?} ms (au repos : ${repos:-?} ms)" "mise en forme juste sous la capacité + file équitable (fq_codel) sur wg0, avant le chiffrement" \
        test "${charge:-9999}" -lt $(( ${repos:-0} * 2 ))
fi

section "Palier 2 — De bout en bout"
critere "Une commande passée depuis Lomé est enregistrée (201, ou 402 : paiement refusé — une réponse métier)" "DNS → GSLB → Lomé → tunnel → base primaire" \
    sur client "curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{\"product_id\":2,\"quantity\":1,\"payment_method\":\"mobile_money\"}' https://www.marche.test/api/orders | grep -qE '^(201|402)\$' || exit 1"
critere "Toutes les applications ($(echo $TOUTES | wc -w)), dans les deux régions, écrivent dans la base primaire" "une seule primaire ; les autres régions y écrivent par le tunnel" \
    bash -c "for a in $TOUTES; do case \$(docker exec \$a curl -s -o /dev/null -m 10 -w '%{http_code}' -X POST localhost:8000/api/orders -H 'content-type: application/json' -d '{\"product_id\":1,\"quantity\":1,\"payment_method\":\"card\"}') in 201|402) ;; *) exit 1 ;; esac; done"
if [ "$RAPIDE" -eq 0 ]; then
    europe=$(docker ps -q --filter label=projet=marche --filter label=region=europe)
    info "l'Europe disparaît pendant 75 s (toutes ses machines gelées)…"
    docker pause $europe >/dev/null; sleep 75
    critere "Sans l'Europe : le site répond encore depuis Lomé (lecture du catalogue)" "GSLB + ns2 : plus rien ne dépend de l'Europe pour LIRE" \
        sur client "[ \$(curl -s -o /dev/null -m 10 -w '%{http_code}' https://www.marche.test/api/products) = 200 ]"
    critere "Sans l'Europe : Lomé résout encore ses noms internes (ns2, vue interne)" "stub-addr : ns2 d'abord" \
        sur passerelle-lome "[ \"\$(dig +short +time=3 @127.0.0.1 db-lome.marche.test)\" = 10.1.0.70 ]"
    critere "Sans l'Europe : la supervision (à Lomé) a ALERTÉ — le pager a reçu « site indisponible » et « coffre »" "Prometheus + Alertmanager hors de la région qu'ils surveillent ; « for: 30s »" \
        sur supervision "journalctl -u pager --since '-85 s' --no-pager -o cat | grep -q 'SiteIndisponible' && journalctl -u pager --since '-85 s' --no-pager -o cat | grep -q 'CoffreIndisponible'"
    docker unpause $europe >/dev/null
    for _ in $(seq 60); do [ "$(pgq "$P" "select count(*) from pg_stat_replication where state='streaming'" 2>/dev/null)" = 1 ] && break; sleep 2; done
    info "Europe dégelée : réplication $(pgq "$P" "select state from pg_stat_replication" 2>/dev/null)"
fi

section "Palier 2 — Rendu (rendu/palier-2/)"
critere "RUNBOOK.md : restaurer à un instant, basculer de région, revenir" "rendu/palier-2/RUNBOOK.md — les commandes, dans l'ordre, et pourquoi" \
    bash -c "f='$RACINE/rendu/palier-2/RUNBOOK.md'; grep -qi 'restaur' \"\$f\" && grep -qi 'bascul' \"\$f\" && grep -qi 'revoke\|révoqu' \"\$f\""
critere "MESURES.md : RTO et RPO MESURÉS (en secondes, en commandes perdues)" "rendu/palier-2/MESURES.md — le chiffre, et comment vous l'avez obtenu" \
    bash -c "f='$RACINE/rendu/palier-2/MESURES.md'; grep -qiE 'RTO[^0-9]*[0-9]' \"\$f\" && grep -qiE 'RPO[^0-9]*[0-9]' \"\$f\""
}

# ============================================================================ PALIER 3
# Conventions imposées par l'énoncé (palier-3.md) : Marché est l'AS 64500, 198.51.100.0/24 — l'Europe
# annonce 198.51.100.0/26, Lomé 198.51.100.64/26, et chacune l'anycast 198.51.100.192/26 (www .200,
# dns .253) tant qu'elle sert ; les identités de service sont dans /etc/identite/ (service.crt,
# service.key, combine.pem, ca.pem) ; rendu/palier-3/trou-noir.sh <europe|lome> activer|lever <adresse>.
bgp_etablies() { sur "$1" "vtysh -c 'show bgp summary json' | jq '[.ipv4Unicast.peers[] | select(.state == \"Established\")] | length'"; }
# recues <routeur> <voisin> : ce que <routeur> reçoit de <voisin>, AVANT ses propres filtres (ce que
# NOUS envoyons, donc — soft-reconfiguration inbound chez les fournisseurs du lab)
recues() { sur "$1" "vtysh -c 'show ip bgp neighbors $2 received-routes json' | jq -r '.receivedRoutes | keys[]'" | sort | paste -sd' '; }
region_www() { sur client "curl -s -o /dev/null -D - -m 5 https://www.marche.test/api/products" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1) == "x-marche-region" {print $2}'; }
code_8443() { sur "$1" "curl -sk -o /dev/null -m 5 -w '%{http_code}' ${3:+--cert $3} https://$IPA:8443$2"; }   # code_8443 <depuis> <chemin> [identité]
eve_n() { sur "$1" "grep -c '\"signature_id\":$2,' /var/log/suricata/eve.json; true" 2>/dev/null; }
promq() { sur supervision "curl -s localhost:9090/api/v1/query --data-urlencode 'query=$1' | jq -r '.data.result[0].value[1] // empty'" 2>/dev/null; }   # (jq : sur la machine — l'hôte n'en a pas forcément)
alerte_active() { sur supervision "curl -s 'localhost:9093/api/v2/alerts?active=true' | grep -q '\"alertname\":\"$1\"'"; }

palier3() {
# Le Palier 3 ne casse rien : tout le Palier 2 est rejoué (ce qu'il change VOLONTAIREMENT s'adapte).
palier2
IPA=$(serveurs lb-lome | awk '{print $1}')   # une instance de Lomé, telle que son répartiteur la voit
info "instance de Lomé éprouvée : ${IPA:-AUCUNE}"

section "Palier 3 — Le code : quatre couches, la landing zone d'abord (M11)"
for c in fondations trafic; do
    critere "couche $c : le réel est conforme au code (plan : aucun changement)" "terraform plan -detailed-exitcode = 0" \
        console "cd $TF/$c && terraform plan -input=false -lock-timeout=60s -detailed-exitcode >/dev/null"
done

section "Palier 3 — Un système autonome : BGP avec trois fournisseurs (M1, M2, M4)"
critere "Europe : 4 sessions BGP établies (transitaires A et B, circuit, VPN)" "neighbor … ; pare-feu : tcp 179 (et BFD) depuis les voisins" \
    test "$(bgp_etablies passerelle)" = 4
critere "Lomé : 5 sessions BGP établies (transitaires A et B, IXP, circuit, VPN)" "neighbor … ; pare-feu : tcp 179 (et BFD) depuis les voisins" \
    test "$(bgp_etablies passerelle-lome)" = 5
europe_attendu="198.51.100.0/26 198.51.100.192/26"; lome_attendu="198.51.100.192/26 198.51.100.64/26"
for v in "backbone 203.0.113.10 europe_attendu" "transit-b 198.18.2.10 europe_attendu" "backbone 192.0.2.100 lome_attendu" "transit-b 198.18.3.100 lome_attendu" "rs-ixp 198.18.1.64 lome_attendu"; do
    read -r rt vs att <<< "$v"; r=$(recues "$rt" "$vs")
    critere "$rt reçoit de $vs exactement : ${!att} (reçu : ${r:-rien})" "route-map sortante : SES préfixes et rien d'autre — relayer ce qu'on apprend d'un fournisseur vers un autre, c'est une fuite de routes" \
        test "$r" = "${!att}"
done
critere "Transitaire B (le secours) reçoit nos annonces allongées : 64500 64500 64500" "as-path prepend : le monde nous joint par A tant que A est là" \
    sur transit-b "vtysh -c 'show ip bgp 198.51.100.0/26' | grep -q '64500 64500 64500' && ! vtysh -c 'show ip bgp 198.51.100.0/26' | grep -qE '^  64500\$'"
critere "Vers l'IXP, nos routes portent « no-export » (elles ne vont pas plus loin que les pairs)" "route-map VERS-IXP : set community no-export ; send-community" \
    sur fai-lome "vtysh -c 'show ip bgp 198.51.100.64/26' | grep -q no-export"
critere "Lomé joint TogoNet par l'IXP (direct, gratuit) plutôt que par un transitaire" "local-preference : IXP 300 > transit A 200 > transit B 100" \
    sur passerelle-lome "ip route get 198.18.30.50 | grep -q 'dev ixp'"
critere "L'Europe sort par SES transitaires, pas par Lomé : pas de routage asymétrique à travers les pare-feux à état" "routes apprises en iBGP : préférence 150 < 200" \
    sur passerelle "ip route get 198.18.30.50 | grep -q 'via 203.0.113.1'"

section "Palier 3 — Anycast : une adresse, deux régions (M4, M13)"
critere "Un client de Lomé (TogoNet) entre par l'IXP, à Lomé, pour www (198.51.100.200) — servi par : $(region_www)" "anycast : les deux régions annoncent le /26 ; le chemin le plus court gagne" \
    bash -c "docker exec fai-lome ip route get 198.51.100.200 | grep -q 'via 198.18.1.64' && [ \"$(region_www)\" = lome ]"
critere "Le DNS aussi est anycast : 198.51.100.253 répond (www → 198.51.100.200)" "DNAT de l'adresse anycast vers le serveur de noms de la région" \
    sur client "[ \"\$(dig +short +time=3 @198.51.100.253 www.marche.test)\" = 198.51.100.200 ]"
if [ "$RAPIDE" -eq 0 ]; then
    info "Lomé ne sert plus (haproxy arrêté sur lb-lome)…"
    sur lb-lome "systemctl stop haproxy"; t=0
    until [ "$(region_www)" = europe ] || [ $t -ge 60 ]; do sleep 1; t=$((t + 1)); done
    critere "Anycast : Lomé malade → elle retire son annonce, les clients arrivent en Europe (en ${t} s, moins de 15)" "annonce conditionnée à la santé ; l'anycast ne se réapprend pas par iBGP" \
        test "$t" -lt 15
    sur lb-lome "systemctl start haproxy"; t=0
    until [ "$(region_www)" = lome ] || [ $t -ge 60 ]; do sleep 1; t=$((t + 1)); done
    critere "Anycast : Lomé guérie → les clients y reviennent (en ${t} s)" "la sonde réannonce d'elle-même" test "$t" -lt 15
fi

section "Palier 3 — Un circuit dédié entre les régions, le VPN en secours (M1, M12)"
critere "BFD : session active sur le circuit, des deux côtés" "bfd + neighbor … bfd ; sans lui, une coupure dure le « hold timer » (3 min)" \
    bash -c "docker exec passerelle vtysh -c 'show bfd peers brief' | grep -qw up && docker exec passerelle-lome vtysh -c 'show bfd peers brief' | grep -qw up"
# (le chemin, lu sur la passerelle : le routeur du circuit ne répond pas aux traceroutes)
chemin_lome() { sur passerelle-lome "ip route get 10.0.3.10" 2>/dev/null | grep -o 'dev [a-z0-9]*' | cut -d' ' -f2; }
critere "Lomé joint le réseau d'Europe par le circuit (interface : $(chemin_lome))" "iBGP par le circuit, préféré au VPN (préférence locale)" \
    test "$(chemin_lome)" = fibre
critere "Le tunnel de secours passe par Internet, jamais par le circuit qu'il secourt" "extrémité WireGuard épinglée : une route /32 via le transitaire" \
    sur passerelle-lome "ip route get 203.0.113.10 | grep -q 'via 192.0.2.1' && wg show wg0 endpoints | grep -q '203.0.113.10:'"
critere "Les passerelles parlent à l'autre région avec leur adresse INTERNE : le résolveur de Lomé joint ns1 (secours)" "set src (ip protocol bgp route-map) ; sinon la source est l'adresse du circuit, inattendue en face" \
    sur passerelle-lome "dig +short +time=3 +tries=1 @10.0.1.53 soa marche.test | grep -q hostmaster"
# le circuit est privé… pas chiffré : ce qui le traverse doit l'être (Zero Trust)
docker exec circuit sh -c 'rm -f /tmp/c.txt; timeout 10 tcpdump -ni any -A -c 400 "tcp port 5432" > /tmp/c.txt 2>/dev/null &'; sleep 1
for _ in 1 2 3; do commande $AL >/dev/null; done
critere "Sur le circuit, PostgreSQL est chiffré (TLS) : aucune requête SQL lisible" "sslmode=verify-full côté application ; hostssl côté base" \
    docker exec circuit sh -c "sleep 9; [ \$(grep -c '5432' /tmp/c.txt) -gt 5 ] && ! grep -qiE 'INSERT INTO|SELECT |SCRAM' /tmp/c.txt"
if [ "$RAPIDE" -eq 0 ]; then
    info "le circuit est coupé (une pelleteuse) pendant 30 s, pendant que Lomé commande…"
    sur $AL "rm -f /tmp/k.txt; (end=\$((SECONDS + 70)); while [ \$SECONDS -lt \$end ]; do curl -s -o /dev/null -m 3 -w '%{http_code}\n' -X POST localhost:8000/api/orders -H 'content-type: application/json' -d '{\"product_id\":1,\"quantity\":1,\"payment_method\":\"card\"}' >> /tmp/k.txt; sleep 0.5; done) >/dev/null 2>&1 &"
    sleep 5; docker exec circuit ip link set fibre-lome down; sleep 3
    bfd=$(sur passerelle-lome "vtysh -c 'show bfd peers brief'" | grep -cw up)
    sleep 12; chemin=$(chemin_lome)
    critere "Circuit coupé : BFD l'a vu en moins de 3 s" "profil BFD 300 ms × 3" test "$bfd" = 0
    critere "Circuit coupé : Lomé atteint la base par le VPN (interface : $chemin)" "iBGP par le tunnel, préférence 50 : il ne sert qu'en secours" \
        test "$chemin" = wg0
    sleep 15; docker exec circuit ip link set fibre-lome up
    for _ in $(seq 30); do [ "$(chemin_lome)" = fibre ] && break; sleep 2; done
    critere "Circuit réparé : le trafic y revient de lui-même" "BFD + BGP : rien à faire à la main" test "$(chemin_lome)" = fibre
    sleep 30; n=$(sur $AL "grep -vcE '^(201|402)\$' /tmp/k.txt"); total=$(sur $AL "wc -l < /tmp/k.txt")
    critere "Circuit coupé puis rétabli : au plus 4 commandes en échec (${n} sur ${total})" "BFD : moins d'une seconde pour décider ; keepalives TCP côté application" \
        test "${n:-99}" -le 4
fi

section "Palier 3 — Sous attaque : le trou noir à distance (RTBH, M2, M6)"
tn=$RENDU/trou-noir.sh
if [ -f "$tn" ]; then
    bash "$tn" europe activer 198.51.100.10 >/dev/null 2>&1; sleep 6
    critere "RTBH : le transitaire A JETTE, chez lui, le trafic vers 198.51.100.10" "annonce du /32 avec la communauté 65010:666 (et no-export)" \
        sur backbone "ip route get 198.51.100.10 | grep -q trou-noir"
    critere "RTBH : l'adresse attaquée est injoignable, le reste du Marché répond" "on sacrifie UNE adresse pour sauver le lien" \
        bash -c "! docker exec client curl -sk -o /dev/null -m 5 https://198.51.100.10/ && [ \$(docker exec client curl -s -o /dev/null -m 5 -w '%{http_code}' https://www.marche.test/api/products) = 200 ]"
    bash "$tn" europe lever 198.51.100.10 >/dev/null 2>&1; sleep 6
    critere "RTBH levé : 198.51.100.10 répond de nouveau" "retirer le /32" sur client "curl -sk -o /dev/null -m 5 https://198.51.100.10/"
else
    rouge "RTBH : $tn introuvable" "rendu/palier-3/trou-noir.sh <europe|lome> activer|lever <adresse> — lancé depuis l'hôte"
fi

section "Palier 3 — Zero Trust : chaque service prouve qui il est (M5)"
for m in $AL lb-lome supervision db; do
    critere "$m : identité de service valide, de 24 h au plus, émise par l'AC des services" "moteur PKI d'OpenBao, ttl=24h ; renouvelée par l'agent — jamais l'identité provisoire" \
        sur $m "c=/etc/identite/service.crt; d=\$(( \$(date -d \"\$(openssl x509 -in \$c -noout -enddate | cut -d= -f2)\" +%s) - \$(date -d \"\$(openssl x509 -in \$c -noout -startdate | cut -d= -f2)\" +%s) ))
               [ \$d -le 90000 ] && openssl x509 -in \$c -noout -checkend 0 && openssl verify -CAfile /etc/identite/ca.pem \$c && ! openssl x509 -in \$c -noout -issuer | grep -qi snakeoil"
done
critere "L'application n'écoute que sur elle-même : le port 8000 est fermé au réseau" "écoute sur 127.0.0.1 ; seul le sidecar TLS (8443) est exposé" \
    bash -c "! docker exec lb-lome timeout 3 bash -c '</dev/tcp/$IPA/8000' 2>/dev/null"
critere "Sans certificat client, l'application refuse (8443 → 400)" "ssl_verify_client on" test "$(code_8443 lb-lome /api/products)" = 400
critere "Le répartiteur (identité lb) accède à l'API, pas aux métriques (200 puis 403)" "autorisation PAR IDENTITÉ : le nom dans le certificat" \
    test "$(code_8443 lb-lome /api/products /etc/identite/combine.pem)$(code_8443 lb-lome /metrics /etc/identite/combine.pem)" = 200403
critere "La supervision (identité supervision) lit les métriques, pas l'API (200 puis 403)" "autorisation PAR IDENTITÉ" \
    test "$(code_8443 supervision /metrics /etc/identite/combine.pem)$(code_8443 supervision /api/products /etc/identite/combine.pem)" = 200403
sur lb-lome "openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=lb.svc.marche.test -keyout /tmp/faux.key -out /tmp/faux.crt 2>/dev/null && cat /tmp/faux.crt /tmp/faux.key > /tmp/faux.pem" >/dev/null 2>&1
critere "Une identité FORGÉE (le bon nom, une autre autorité) est refusée" "ssl_client_certificate : l'AC des services, et elle seule" \
    test "$(code_8443 lb-lome /api/products /tmp/faux.pem)" = 400
critere "La base refuse toute connexion non chiffrée" "pg_hba : hostnossl … reject" \
    sur $AL "PGPASSWORD=x psql 'host=db.marche.test dbname=marche user=sonde sslmode=disable connect_timeout=5' -c 'select 1' 2>&1 | grep -q 'no encryption'"
critere "La base exige l'identité du client (TLS sans certificat : refusé)" "hostssl … clientcert=verify-ca" \
    sur $AL "PGPASSWORD=x psql 'host=db.marche.test dbname=marche user=sonde sslmode=require connect_timeout=5' -c 'select 1' 2>&1 | grep -q 'certificate'"

section "Palier 3 — Détection et prévention d'intrusion (M6)"
for p in passerelle passerelle-lome; do
    critere "$p : Suricata EN LIGNE (NFQUEUE), avec « bypass » (s'il tombe, le trafic passe)" "queue … bypass ; dans les deux sens" \
        sur $p "systemctl is-active -q suricata && nft list ruleset | grep -q 'queue.*bypass'"
done
avant=$(eve_n passerelle-lome 9000002); console "systemctl start cspm" >/dev/null 2>&1; sleep 2
critere "Le scanner AUTORISÉ (la conformité, depuis la console) ne déclenche pas d'alerte" "suppress … track by_src, ip <console> : une alerte qui sonne toujours n'est plus lue" \
    test "$(eve_n passerelle-lome 9000002)" = "$avant"
# (SSH d'abord : le balayage touche aussi le port 22, et la signature SSH ne sonne qu'une fois par
#  minute et par source — après le balayage, l'essai SSH passerait inaperçu)
avant=$(eve_n passerelle-lome 9000002)
bash "$RACINE/outils/attaque.sh" ssh 198.51.100.100 >/dev/null 2>&1; sleep 3
critere "Une recherche de SSH depuis Internet est DÉTECTÉE" "on n'administre que par le VPN : un SYN vers 22 venu d'Internet est suspect" test "$(eve_n passerelle-lome 9000002)" -gt "$avant"
avant=$(eve_n passerelle-lome 9000001)
bash "$RACINE/outils/attaque.sh" balayage 198.51.100.100 >/dev/null 2>&1; sleep 3
critere "Un balayage de ports depuis Internet est DÉTECTÉ" "règle : beaucoup de SYN d'une même source en peu de temps" test "$(eve_n passerelle-lome 9000001)" -gt "$avant"
res=$(bash "$RACINE/outils/attaque.sh" dns-any 198.51.100.253 2>/dev/null)
bloque() { grep -q ': 0 / 10' <<< "$res" && grep -q '198.51.100.200' <<< "$res"; }
critere "Requêtes DNS ANY (amplification) BLOQUÉES — les requêtes ordinaires servies pendant ce temps" "drop … (IPS) ; pas de blocage de l'adresse : de la chirurgie" bloque
for _ in $(seq 24); do alerte_active AttaqueBloquee && break; sleep 5; done
critere "La supervision est prévenue : alerte « AttaqueBloquee »" "eve.json → métrique (textfile) → règle → Alertmanager" alerte_active AttaqueBloquee
if [ "$RAPIDE" -eq 0 ]; then
    sur passerelle-lome "systemctl stop suricata"; sleep 2
    critere "Suricata arrêté : le site répond encore (bypass — le choix de la disponibilité)" "queue … bypass" \
        sur client "[ \$(curl -s -o /dev/null -m 5 -w '%{http_code}' https://www.marche.test/api/products) = 200 ]"
    sur passerelle-lome "systemctl start suricata"
fi

section "Palier 3 — Performance : TCP et SD-WAN (M3, M8)"
critere "BBR sur les machines qui ÉMETTENT (répartiteurs, CDN, applications)" "net.ipv4.tcp_congestion_control = bbr (mesuré : ×9 sur un chemin qui perd)" \
    bash -c "for m in lb lb-lome edge $AE $AL; do [ \"\$(docker exec \$m sysctl -n net.ipv4.tcp_congestion_control)\" = bbr ] || exit 1; done"
octets() { sur passerelle-lome "cat /sys/class/net/$1/statistics/rx_bytes"; }
w0=$(octets wg0); f0=$(octets fibre)
sur client "for i in \$(seq 10); do curl -s -o /dev/null -H 'Cache-Control: no-cache' https://www.marche.test/static/catalogue.jpg; done"
w=$(( $(octets wg0) - w0 )); f=$(( $(octets fibre) - f0 ))
critere "SD-WAN : le catalogue (stockage objet, 8333) arrive par le tunnel ($((w / 1024)) Kio), pas par le circuit ($((f / 1024)) Kio)" "le volumineux par Internet (marque → table de routage), le circuit pour l'interactif" \
    test "$w" -gt $(( f * 5 + 500000 ))

section "Palier 3 — Gouvernance : landing zone et conformité continue (M11, M16)"
lz=$(console "S='AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt AWS_DEFAULT_REGION=us-east-1'
    o=\$(cd $TF/fondations && terraform output -json deploiement); k=\$(echo \"\$o\" | jq -r .dev.access_key); s=\$(echo \"\$o\" | jq -r .dev.secret_key)
    dev() { env \$S AWS_ACCESS_KEY_ID=\$k AWS_SECRET_ACCESS_KEY=\$s aws --endpoint-url https://s3.fournisseur.test \"\$@\" >/dev/null 2>&1 && echo o || echo n; }
    aud() { env \$S AWS_PROFILE=audit aws --endpoint-url https://s3.fournisseur.test \"\$@\" >/dev/null 2>&1 && echo o || echo n; }
    echo v > /tmp/v
    echo \$(dev s3 cp /tmp/v s3://marche-dev-donnees/verif) \$(dev s3 ls s3://marche-prod-donnees/) \$(dev s3 ls s3://marche-sauvegardes/) \$(dev s3 cp /tmp/v s3://marche-journaux/prod/verif) \
         \$(aud s3 ls s3://marche-prod-donnees/) \$(aud s3 cp /tmp/v s3://marche-prod-donnees/verif)" 2>/dev/null)
critere "Landing zone : le compte dev écrit chez lui, ne voit ni la production, ni les sauvegardes, ni les journaux des autres" "une politique par compte, limitée à SES ressources" \
    test "$(cut -d' ' -f1-4 <<< "$lz")" = "o n n n"
critere "Landing zone : l'audit lit tout, et ne peut rien écrire" "s3:Get*/List* seulement : ce qui n'est pas accordé est refusé" \
    test "$(cut -d' ' -f5-6 <<< "$lz")" = "o n"
critere "Conformité continue : au moins 8 règles, évaluées il y a moins de 10 min, toutes respectées" "cspm (minuterie) → métriques → supervision ; exceptions documentées" \
    test "$(promq 'count(marche_cspm_conforme == 1) >= 8 and count(marche_cspm_conforme == 1) == count(marche_cspm_conforme) and on() (time() - marche_cspm_derniere_execution < 600)')" != ""
# une dérive, provoquée : un bucket ouvert à tous — la conformité doit la voir au prochain passage
console "$AWSF s3 mb s3://marche-verif-derive && $AWSF s3api put-bucket-policy --bucket marche-verif-derive --policy '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::marche-verif-derive/*\"}]}' && systemctl start cspm" >/dev/null 2>&1
critere "Une dérive (un bucket public, créé à la main) est vue par la conformité" "règle « bucket_public » : la politique de chaque bucket, lue avec l'identité d'audit" \
    console "grep -q 'regle=\"bucket_public\"} 0' /var/lib/prometheus/node-exporter/cspm.prom"
console "$AWSF s3 rb --force s3://marche-verif-derive; systemctl start cspm" >/dev/null 2>&1

section "Palier 3 — Coûts, capacité, périphérie (M9, M17, M18)"
c=$(promq 'marche:cout_euros:par_commande')
critere "FinOps : le coût complet d'UNE commande est calculé (${c:-?} €)" "coûts par poste (instances, plateforme, trafic inter-régions) ÷ commandes par heure" \
    bash -c "[ -n '$c' ] && awk 'BEGIN {exit !($c > 0)}'"
critere "FinOps : les trois postes de coût sont suivis" "marche:cout_euros:par_heure{poste=…}" \
    test "$(promq 'count(marche:cout_euros:par_heure)')" -ge 3
if [ "$RAPIDE" -eq 0 ]; then
    sur client "curl -s -o /dev/null https://static.marche.test/catalogue.jpg; curl -s -o /dev/null https://static.marche.test/catalogue.jpg"
    sur edge "nft add table ip verif && nft add chain ip verif sortie '{ type filter hook output priority 0; }' && nft add rule ip verif sortie tcp dport 443 drop"
    x=$(sur client "curl -s -o /dev/null -D - -m 15 -w 'code=%{http_code}' https://static.marche.test/catalogue.jpg" 2>/dev/null | tr -d '\r' | grep -iE '^x-cache|code=' | paste -sd' ')
    sur edge "nft delete table ip verif"
    critere "CDN : l'origine injoignable, le CDN sert encore sa copie ($x)" "proxy_cache_use_stale error timeout … ; la périphérie absorbe la panne" \
        grep -qiE 'x-cache: (HIT|STALE|UPDATING).*code=200' <<< "$x"
fi

section "Palier 3 — Objectifs de service : SLO et budget d'erreur (M14, M15)"
critere "SLI et budget enregistrés : erreurs sur 5 min, 1 h, 6 h ; budget restant" "règles d'enregistrement marche:sli_erreurs:ratio_rate<fenêtre>, marche:budget_erreur:restant_1d" \
    bash -c "for r in marche:sli_erreurs:ratio_rate5m marche:sli_erreurs:ratio_rate1h marche:sli_erreurs:ratio_rate6h marche:budget_erreur:restant_1d; do [ -n \"\$(docker exec supervision sh -c \"curl -s localhost:9090/api/v1/query --data-urlencode query=\$r | jq -r '.data.result[0].value[1] // empty'\")\" ] || exit 1; done"
critere "Alertes de consommation du budget : rapide (14,4×) et lente (6×), chacune sur deux fenêtres" "multi-window, multi-burn-rate (le livre SRE de Google)" \
    sur supervision "r=\$(curl -s localhost:9090/api/v1/rules); for a in BudgetErreurRapide BudgetErreurLent; do echo \"\$r\" | grep -q \"\\\"\$a\\\"\" || exit 1; done"

section "Palier 3 — Rendu (rendu/palier-3/)"
critere "RUNBOOK.md : attaque (trou noir, IPS), circuit coupé, identité compromise" "rendu/palier-3/RUNBOOK.md — les commandes, dans l'ordre, et pourquoi" \
    bash -c "f='$RENDU/RUNBOOK.md'; grep -qiE 'RTBH|trou noir' \"\$f\" && grep -qi 'circuit' \"\$f\" && grep -qiE 'certificat|identit' \"\$f\" && grep -qiE 'IPS|suricata' \"\$f\""
critere "MESURES.md : bascule anycast, coupure du circuit, BBR/CUBIC, capacité, coût par commande — chiffrés" "rendu/palier-3/MESURES.md — le chiffre, et comment vous l'avez obtenu" \
    bash -c "f='$RENDU/MESURES.md'; for m in anycast BFD BBR capacit 'co[uû]t.*commande'; do grep -qiE \"\$m\" \"\$f\" || exit 1; done && [ \$(grep -cE '[0-9]' \"\$f\") -ge 10 ]"
critere "REVUE.md : une revue d'architecture sur les six piliers (Well-Architected)" "fiabilité, sécurité, performance, coûts, excellence opérationnelle, durabilité — et ce qu'il reste à faire" \
    bash -c "f='$RENDU/REVUE.md'; for m in fiabilit sécurité performance coût excellence durabilit; do grep -qi \"\$m\" \"\$f\" || exit 1; done"

# en DERNIER : ce test laisse une alerte active quelques minutes (le temps que la fenêtre de 5 min se vide)
if [ "$RAPIDE" -eq 0 ]; then
    # (les pannes provoquées plus haut — l'Europe gelée — ont déjà brûlé du budget : on attend que
    #  l'alerte retombe, sinon on mesurerait l'ancienne)
    if alerte_active BudgetErreurRapideLab; then
        info "l'alerte de budget sonne encore (les pannes provoquées plus haut) : on attend qu'elle retombe…"
        for _ in $(seq 84); do alerte_active BudgetErreurRapideLab || break; sleep 5; done
    fi
    info "une version défaillante : 30 % d'erreurs sur toutes les instances, pendant que les clients naviguent…"
    for a in $TOUTES; do sur $a "curl -s -o /dev/null -X POST localhost:8000/admin/chaos -H 'content-type: application/json' -d '{\"error_rate\": 0.3}'"; done
    sur client "(end=\$((SECONDS + 180)); while [ \$SECONDS -lt \$end ]; do curl -s -o /dev/null -m 5 https://www.marche.test/api/products; sleep 0.2; done) >/dev/null 2>&1 &"
    t=0; until alerte_active BudgetErreurRapideLab || [ $t -ge 180 ]; do sleep 5; t=$((t + 5)); done
    for a in $TOUTES; do sur $a "curl -s -o /dev/null -X POST localhost:8000/admin/chaos -H 'content-type: application/json' -d '{\"error_rate\": 0}'"; done
    critere "Le budget d'erreur brûle 14× trop vite → alerte (à l'échelle du lab) en ${t} s" "BudgetErreurRapideLab : les fenêtres du SLO, divisées par 12" test "$t" -lt 180
    info "(les alertes provoquées se résolvent d'elles-mêmes en 5 à 10 min : attendez avant de relancer le correcteur)"
fi
}

case $PALIER in
    1) palier1 ;;
    2) palier2 ;;
    3) palier3 ;;
    *) echo "Palier inconnu : $PALIER" >&2; exit 2 ;;
esac

total=$((OK + KO))
printf '\n  Score : %d/%d\n' "$OK" "$total"
[ "$KO" -eq 0 ] && printf '  \033[32m🎉 Palier %s validé.\033[0m\n' "$PALIER"
exit $(( KO > 0 ))
