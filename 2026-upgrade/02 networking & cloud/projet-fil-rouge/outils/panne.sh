#!/usr/bin/env bash
# panne.sh — pannes réseau du projet fil rouge. À lancer SUR L'HÔTE du lab.
#
#   ./outils/panne.sh liste [palier]        le catalogue
#   ./outils/panne.sh <nom>                 injecter une panne connue (entraînement)
#   ./outils/panne.sh aveugle [n] [palier]  n pannes au hasard (défaut 2), sans dire lesquelles
#   ./outils/panne.sh revele                révéler le tirage
#   ./outils/panne.sh annuler <nom>         dernier recours (= manche perdue)
#
# Règle du jeu : symptôme → hypothèse → mesure (ping, traceroute, tcpdump, dig, openssl…)
# → cause → correction, notés dans INCIDENTS.md. Redémarrer une machine n'est pas diagnostiquer
# (et plusieurs de ces pannes survivent au redémarrage).
set -uo pipefail
export MSYS_NO_PATHCONV=1
TICKET=$(cd "$(dirname "$0")/.." && pwd)/.panne-aveugle
sur() { local m=$1; shift; docker exec "$m" bash -c "$*"; }

# nom|palier|symptôme vu par les utilisateurs (ce que dit le ticket)|couche
CATALOGUE=(
  "mtu-trou-noir|1|Depuis Lomé, le site ne charge plus (délai dépassé)… mais le ping passe, et le DNS répond.|L3 (MTU, ICMP)"
  "route-retour|1|Toutes les commandes échouent ; la base « répond au ping » d'après l'équipe.|L3 (routage)"
  "vlan-errone|1|Un serveur d'application a disparu de la rotation après une « petite modif réseau ».|L2 (VLAN)"
  "arp-doublon|1|Des commandes échouent au hasard, une sur deux environ, depuis l'ajout d'une adresse sur le stockage.|L2 (ARP)"
  "dns-glue|1|Depuis Lomé, plus personne ne trouve www.marche.test ; dans le VPC, tout va bien.|L7 (DNS, délégation)"
  "dns-negatif|1|Un collègue a « nettoyé » la zone DNS, puis tout remis… mais Lomé ne voit toujours pas le site.|L7 (DNS, cache négatif)"
  "chaine-incomplete|1|Nouveau certificat installé : certains clients refusent le site, le navigateur du collègue l'accepte.|TLS (chaîne)"
  "nat-oublie|1|Le site marche, mais aucune machine du VPC n'arrive plus à télécharger ses mises à jour.|L3/L4 (NAT)"
  "acl-retour|1|Après un « durcissement » de l'ACL des données : plus aucune commande, rien dans les journaux de la base.|L4 (ACL sans état)"
  "cdn-no-store|1|Les images sont redevenues lentes à Lomé, alors que le CDN est « en place ».|L7 (cache HTTP)"
  "sg-sante|1|Un serveur d'application est marqué DOWN par le répartiteur, alors que le service tourne.|L4 (security group)"
  "wg-cle|1|Plus moyen d'administrer le VPC depuis la console ; le site, lui, fonctionne.|VPN (WireGuard)"
  "machine-fantome|2|La facture du mois a pris 15 % ; personne n'a rien déployé, jure l'équipe.|IaC (dérive, FinOps)"
  "verrou-orphelin|2|Plus moyen de déployer : « Error acquiring the state lock » depuis que le portable d'Aminata a planté en plein apply.|IaC (état, verrou)"
  "coffre-scelle|2|Les instances remplacées ne démarrent plus leur application ; les autres tournent… pour l'instant.|Secrets (coffre)"
  "replication-coupee|2|La supervision : la réplique a de plus en plus de retard, et le disque de la primaire se remplit.|Données (réplication, L4)"
  "cle-sauvegarde|2|Alerte : plus aucun WAL archivé depuis 10 min — le RPO des sauvegardes s'envole.|Données (IAM, dérive)"
  "gslb-epingle|2|Depuis Lomé, le site est rapide… une fois sur deux ; l'autre fois, il met 400 ms.|DNS (GSLB, NAT en épingle)"
  "db-lecture-seule|2|À Lomé, les commandes échouent (500) mais le catalogue s'affiche ; en Europe, tout va bien.|DNS privé (point d'accès)"
  "groupe-vide|2|Après le déploiement de ce matin, les clients de Lomé passent par l'Europe (lent) ; « tout est vert » d'après l'équipe.|Déploiement (découverte)"
  "qos-retiree|2|Depuis la « mise à jour du routeur », les commandes de Lomé rament dès qu'un gros transfert passe — et seulement à ce moment-là.|QoS (files d'attente)"
  "fuite-routes|3|TransAtlantique (transitaire A) écrit : « vous nous annoncez des réseaux qui ne sont pas à vous — corrigez, ou nous coupons la session ».|BGP (politique sortante)"
  "anycast-aveugle|3|Plus aucun client de Lomé n'arrive sur le site ; l'Europe va très bien. Pourquoi ne sont-ils pas partis en Europe tout seuls, comme au dernier exercice ?|Anycast (santé)"
  "bfd-retire|3|Travaux de l'opérateur du circuit cette nuit : 3 minutes sans aucune commande à Lomé. Aux travaux précédents, personne n'avait rien remarqué.|BGP (détection de panne)"
  "identite-perimee|3|Une instance de Lomé est sortie de la rotation il y a quelques minutes ; en local, son application répond. « Personne n'y a touché. »|Zero Trust (identités)"
  "ips-sans-bypass|3|Depuis la « mise à jour de sécurité » de la passerelle de Lomé, plus rien n'arrive d'Internet à Lomé ; le site y est injoignable.|IPS (mode en ligne)"
  "sdwan-inverse|3|L'opérateur du circuit (facturé au volume) : la facture du mois a triplé, sans hausse des ventes.|SD-WAN (routage par politique)"
  "bucket-public|3|La supervision sonne « NonConformite » depuis ce matin ; l'équipe produit jure n'avoir rien changé « d'important ».|Conformité (CSPM, landing zone)"
  "asymetrie|3|Les clients de TogoNet n'arrivent plus à joindre l'adresse de l'Europe (198.51.100.10) ; depuis le reste d'Internet, elle répond.|BGP (routage asymétrique)"
)
champ() { cut -d'|' -f"$2" <<< "$1"; }
existe() { local l; for l in "${CATALOGUE[@]}"; do [[ $(champ "$l" 1) == "$1" ]] && return 0; done; return 1; }

# ------------------------------------------------------------------ injections
p_mtu-trou-noir() {   # le lien Internet de la passerelle passe à 1400 (un tunnel chez l'opérateur) ET
                      # l'ICMP « fragmentation needed » qu'elle devrait renvoyer est filtré
    sur passerelle "ip link set internet mtu 1400
        nft add table inet panne; nft 'add chain inet panne sortie { type filter hook output priority -10 ; }'
        nft add rule inet panne sortie icmp type destination-unreachable icmp code frag-needed drop"; }
p_route-retour()     { sur db "ip route del default; ip route add 10.0.2.0/24 via 10.0.3.254"; }
p_vlan-errone()      { sur app2 "sed -i 's/Id=20/Id=21/' /etc/systemd/network/20-baie.20.netdev 2>/dev/null
        ip link del baie.20 2>/dev/null; ip link add link baie name baie.20 type vlan id 21
        ip addr add 10.0.2.12/24 dev baie.20; ip link set baie.20 up"; }
# Le stockage s'attribue l'adresse de la base ET l'annonce (ARP gratuit) toutes les 2 s, comme le
# ferait une machine mal configurée qui insiste. (Une annonce isolée ne suffit pas : la vraie base
# répond aux requêtes ARP suivantes et reprend la main — vu en construisant la panne.)
p_arp-doublon()      { sur stockage "ip addr add 10.0.3.10/24 dev baie.30 2>/dev/null
        systemd-run --unit=panne-arp --quiet bash -c 'while :; do arping -q -c 1 -U -I baie.30 10.0.3.10; sleep 2; done'"; }
p_dns-glue()         { sur dns-racine "registre deleguer marche.test ns1.marche.test 203.0.113.99 >/dev/null
        unbound-control flush_zone marche.test >/dev/null; unbound-control flush_infra all >/dev/null; unbound-control flush_requestlist >/dev/null"; }
# zone_ns1 <supprimer-www|remettre-www> : modifie la zone PUBLIQUE de ns1 comme le ferait un
# collègue, numéro de série incrémenté, puis recharge. (Script envoyé sur l'entrée standard :
# plus lisible que des guillemets imbriqués.)
zone_ns1() { docker exec -i ns1 bash -s "$1" <<'EOF'
set -e
# le fichier de la zone marche.test vue d'Internet : dans la vue « externe » s'il y a des vues
# (première version : elle prenait le premier « file » venu — la zone INTERNE)
fichier() { awk -v vue="$1" '(vue == "" || $0 ~ "view \"" vue "\"") {v = 1} v && /file/ {for (i = 1; i <= NF; i++) if ($i == "file") {f = $(i + 1); gsub(/[";]/, "", f); print f; exit}}' /etc/bind/named.conf; }
z=$(fichier externe); [ -f "$z" ] || z=$(fichier "")
case $1 in
    supprimer-www) cp "$z" /root/.panne-zone; sed -i -E '/^www[[:space:]]/d' "$z" ;;
    # (cp SANS -a, et sed : garder la date de la sauvegarde ferait croire à BIND que rien n'a
    #  changé — « rndc reload » ne recharge pas la zone. Vécu en construisant cette panne.)
    remettre-www)  grep -q '^www[[:space:]]' "$z" || sed -i "/IN *NS/a $(grep -E '^www[[:space:]]' /root/.panne-zone)" "$z" ;;
esac
# numéro de série + 1 (mawk, l'awk d'Ubuntu, ignore les intervalles {8,} : on teste la longueur)
s=$(awk '/SOA/ {f = 1} f {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/ && length($i) >= 8) {print $i; exit}}' "$z")
sed -i "0,/$s/s//$((s + 1))/" "$z"
rndc reload >/dev/null
EOF
}
p_dns-negatif()      { zone_ns1 supprimer-www; sleep 1
      sur dns-racine "unbound-control flush www.marche.test >/dev/null"
      sur client "dig +short www.marche.test >/dev/null"        # un client demande : NXDOMAIN, mis en cache
      # « le collègue remet tout » : la zone est juste… mais le NXDOMAIN reste dans le cache du FAI
      zone_ns1 remettre-www; }
p_chaine-incomplete() { sur lb "f=\$(awk '/crt / {for (i=1;i<=NF;i++) if (\$i==\"crt\") print \$(i+1)}' /etc/haproxy/haproxy.cfg | head -1)
        cp -a \"\$f\" /root/.panne-pem
        awk '/BEGIN CERT/ {n++} n>=2 && /BEGIN CERT/ {skip=1} !skip {print} /END CERT/ && skip {skip=0}' /root/.panne-pem > \"\$f\"
        systemctl reload haproxy"; }
p_nat-oublie()       { sur passerelle "h=\$(nft -a list chain ip nat postrouting | awk '/masquerade|snat/ {print \$NF; exit}')
        [ -n \"\$h\" ] && nft delete rule ip nat postrouting handle \$h"; }
p_acl-retour()       { sur passerelle "for h in \$(nft -a list ruleset | awk '/sport 5432/ {print \$NF}'); do
            c=\$(nft -a list ruleset | awk -v h=\"\$h\" '/chain / {c=\$2} \$NF==h {print c; exit}')
            t=\$(nft -a list ruleset | awk -v h=\"\$h\" '/^table/ {t=\$2\" \"\$3} \$NF==h {print t; exit}')
            nft delete rule \$t \$c handle \$h
        done"; }
p_cdn-no-store()     { sur lb "cp -a /etc/haproxy/haproxy.cfg /root/.panne-haproxy.cfg
        sed -i '0,/^backend statique/s//backend statique\n    http-response set-header Cache-Control no-store/' /etc/haproxy/haproxy.cfg
        systemctl reload haproxy"
      sur edge "rm -rf /var/cache/nginx/cdn/*; systemctl reload nginx"; }
p_sg-sante()         { sur app1 "nft add table inet panne; nft 'add chain inet panne entree { type filter hook input priority -10 ; }'
        nft add rule inet panne entree ip saddr 10.0.1.10 tcp dport 8000 drop"; }
p_wg-cle()           { sur passerelle "cp -a /etc/wireguard/prive.key /root/.panne-wg; umask 077; wg genkey > /etc/wireguard/prive.key
        sed -i \"s#^PrivateKey = .*#PrivateKey = \$(cat /etc/wireguard/prive.key)#\" /etc/wireguard/wg0.conf; systemctl restart wg-quick@wg0"; }

# ------------------------------------------------------------------ Palier 2
AWSF='AWS_DEFAULT_REGION=us-east-1 AWS_PROFILE=fournisseur AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt aws --endpoint-url https://s3.fournisseur.test'
BAO='export BAO_ADDR=https://10.0.3.30:8200 BAO_CACERT=/root/pki/racine.crt BAO_TLS_SERVER_NAME=coffre.marche.test BAO_TOKEN=$(jq -r .root_token /root/cles/bao-init.json);'
# qui est primaire en ce moment (la bascule de région peut avoir inversé les rôles)
primaire() { for b in db db-lome; do [ "$(sur $b "runuser -u postgres -- psql -tAc 'select pg_is_in_recovery()'" 2>/dev/null)" = f ] && { echo $b; return; }; done; }
ip_de()    { [ "$1" = db ] && echo 10.0.3.10 || echo 10.1.0.70; }
gw_de()    { [ "$1" = db ] && echo passerelle || echo passerelle-lome; }
apps_de()  { docker ps --filter label=projet=marche --filter label=role=app --filter label=region="$([ "$1" = db ] && echo europe || echo lome)" --format '{{.Names}}'; }

# une instance lancée « pour un essai » à la main, jamais arrêtée : elle a les étiquettes du projet
p_machine-fantome()  { docker run -d --name marche-essai-gpu --label projet=marche --label equipe=data \
        --label env=dev --label region=europe --network none --entrypoint sleep marche-net/ubuntu:24.04 infinity >/dev/null; }
# un verrou laissé par un « apply » interrompu (le portable a planté) : personne ne le lèvera
p_verrou-orphelin()  { docker exec console bash -c "printf '%s' '{\"ID\":\"6f1c2b9e-4d7a-4c1e-9b3f-2a8d5e0c7f14\",\"Operation\":\"OperationTypeApply\",\"Info\":\"\",\"Who\":\"aminata@portable\",\"Version\":\"1.16.4\",\"Created\":\"$(date -u +%FT%T.000000000Z)\",\"Path\":\"marche-etat-terraform/regions/terraform.tfstate\"}' > /tmp/verrou.json
        $AWSF s3 cp /tmp/verrou.json s3://marche-etat-terraform/regions/terraform.tfstate.tflock >/dev/null"; }
# le service du coffre redémarre seul (mise à jour automatique…) : il repart SCELLÉ
p_coffre-scelle()    { sur coffre "systemctl restart bao"; }
# un « durcissement » de la passerelle de la réplique coupe sa connexion vers la primaire
p_replication-coupee() { local p r; p=$(primaire); r=$([ "$p" = db ] && echo db-lome || echo db)
      sur "$(gw_de "$r")" "nft add table inet panne; nft 'add chain inet panne transit { type filter hook forward priority -10 ; }'
        nft add rule inet panne transit ip saddr $(ip_de "$r") ip daddr $(ip_de "$p") tcp dport 5432 drop"; }
# la clé d'accès de pgBackRest est supprimée chez le fournisseur (« nettoyage des vieilles clés »)
p_cle-sauvegarde()   { docker exec console bash -c "for k in \$($AWSF iam list-access-keys --user-name marche-pgbackrest --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
            $AWSF iam delete-access-key --user-name marche-pgbackrest --access-key-id \$k; done"; }
# la règle de NAT « en épingle » de Lomé disparaît : la sonde du GSLB de Lomé vers SON site échoue
p_gslb-epingle()     { sur passerelle-lome "h=\$(nft -a list chain ip nat postrouting | awk '/ct status dnat masquerade/ {print \$NF; exit}')
        [ -n \"\$h\" ] && nft delete rule ip nat postrouting handle \$h"; }
# « un collègue » fait pointer db.marche.test vers la base de SA région… qui est la réplique
p_db-lecture-seule() { local p r a; p=$(primaire); r=$([ "$p" = db ] && echo db-lome || echo db)
      sur "$(gw_de "$r")" "unbound-control local_data 'db.marche.test. 30 IN A $(ip_de "$r")' >/dev/null"
      for a in $(apps_de "$r"); do sur "$a" "systemctl restart marche.target"; done; }

# « on a déployé à Lomé » : la couleur active passe au groupe… qui n'a aucune instance
p_groupe-vide()      { docker exec console bash -c "f=/root/p2/terraform/trafic/flotte.auto.tfvars.json
        c=\$(jq -r .couleur_active.lome \$f); [ \$c = bleu ] && n=vert || n=bleu; cp \$f /root/.panne-couleur
        jq \".couleur_active.lome = \\\"\$n\\\"\" \$f > \$f.n && mv \$f.n \$f; cd /root/p2/terraform/trafic && terraform apply -input=false -auto-approve >/dev/null"; }
# la file équitable du tunnel remplacée par une simple FIFO (« c'est plus simple ») — des deux côtés
p_qos-retiree()      { for g in passerelle passerelle-lome; do sur $g "tc qdisc del dev wg0 parent 1:10 2>/dev/null; tc qdisc add dev wg0 parent 1:10 handle 11: pfifo limit 1000"; done; }

# ------------------------------------------------------------------ Palier 3
# (les changements de FRR sont ENREGISTRÉS — write memory : ils survivent à un redémarrage)
frr() { local m=$1; shift; local a=(); for c in "$@"; do a+=(-c "$c"); done; docker exec "$m" vtysh -c 'configure terminal' "${a[@]}" -c end -c 'write memory' >/dev/null; }
# « on simplifie la politique sortante » : le refus final vers le transitaire A devient une acceptation
p_fuite-routes()     { frr passerelle 'no route-map VERS-TRANSIT deny 20' 'route-map VERS-TRANSIT permit 20'
      sur passerelle "vtysh -c 'clear ip bgp 203.0.113.1 soft out'"; }
# la sonde de santé de l'anycast est arrêtée (« elle remplissait les journaux ») ; plus tard, le répartiteur tombe
p_anycast-aveugle()  { sur passerelle-lome "systemctl disable -q --now anycast-sante"; sur lb-lome "systemctl stop haproxy"; }
# « BFD, c'est pour les opérateurs » : retiré des deux côtés du circuit
p_bfd-retire()       { frr passerelle 'router bgp 64500' 'no neighbor 198.18.9.10 bfd'; frr passerelle-lome 'router bgp 64500' 'no neighbor 198.18.9.2 bfd'; }
# l'agent OpenBao d'une instance arrêté pour « déboguer » ; son identité, courte, expire
p_identite-perimee() { local a; a=$(apps_de db-lome | head -1)
      sur "$a" "systemctl disable -q --now bao-agent"
      docker exec console bash -c "$BAO bao write -format=json pki-services/issue/app common_name=app.svc.marche.test ttl=90s" \
        | docker exec -i "$a" bash -c 'jq -r ".data.private_key, .data.certificate" > /etc/identite/service.pem && /usr/local/sbin/identite-installer >/dev/null 2>&1'; }
# la mise à jour de Suricata a planté, et la file d'attente a perdu son « bypass »
p_ips-sans-bypass()  { sur passerelle-lome "cp -a /etc/nftables.d-ips.conf /root/.panne-ips; sed -i 's/ bypass//g' /etc/nftables.d-ips.conf
        systemctl reload nftables; systemctl stop suricata"; }
# la sonde SD-WAN arrêtée, et la table du volumineux pointée sur le circuit (« le circuit est plus rapide »)
p_sdwan-inverse()    { sur passerelle-lome "systemctl disable -q --now sdwan-sante; ip route replace 10.0.0.0/16 via 198.18.9.9 dev fibre table 200"; }
# l'équipe produit ouvre son bucket à tous « pour partager un fichier avec un partenaire »
p_bucket-public()    { docker exec console bash -c "$AWSF s3api put-bucket-policy --bucket marche-dev-donnees --policy '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Partenaire\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::marche-dev-donnees/*\"}]}'
        systemctl start cspm"; }
# « la préférence 150 sur l'iBGP ne sert à rien » : l'Europe reprend la préférence de Lomé (IXP : 300)
p_asymetrie()        { frr passerelle 'route-map IBGP permit 10' 'no set local-preference'; sur passerelle "vtysh -c 'clear ip bgp 198.18.9.10 soft in'"; }

a_fuite-routes()     { frr passerelle 'no route-map VERS-TRANSIT permit 20' 'route-map VERS-TRANSIT deny 20'; sur passerelle "vtysh -c 'clear ip bgp 203.0.113.1 soft out'"; }
a_anycast-aveugle()  { sur lb-lome "systemctl start haproxy"; sur passerelle-lome "systemctl enable -q --now anycast-sante"; }
a_bfd-retire()       { frr passerelle 'router bgp 64500' 'neighbor 198.18.9.10 bfd' 'neighbor 198.18.9.10 bfd profile circuit'
      frr passerelle-lome 'router bgp 64500' 'neighbor 198.18.9.2 bfd' 'neighbor 198.18.9.2 bfd profile circuit'; }
a_identite-perimee() { sur "$(apps_de db-lome | head -1)" "systemctl enable -q --now bao-agent"; }
a_ips-sans-bypass()  { sur passerelle-lome "cp -a /root/.panne-ips /etc/nftables.d-ips.conf; systemctl reload nftables; systemctl start suricata"; }
a_sdwan-inverse()    { sur passerelle-lome "ip route flush table 200; systemctl enable -q --now sdwan-sante"; }
a_bucket-public()    { docker exec console bash -c "$AWSF s3api delete-bucket-policy --bucket marche-dev-donnees; systemctl start cspm"; }
a_asymetrie()        { frr passerelle 'route-map IBGP permit 10' 'set local-preference 150'; sur passerelle "vtysh -c 'clear ip bgp 198.18.9.10 soft in'"; }

# ------------------------------------------------------------------ annulations (dernier recours)
a_groupe-vide()      { docker exec console bash -c "cp /root/.panne-couleur /root/p2/terraform/trafic/flotte.auto.tfvars.json && cd /root/p2/terraform/trafic && terraform apply -input=false -auto-approve >/dev/null"; }
a_qos-retiree()      { for g in passerelle passerelle-lome; do sur $g "/usr/local/sbin/qos-wg0"; done; }
a_machine-fantome()  { docker rm -f marche-essai-gpu >/dev/null; }
a_verrou-orphelin()  { docker exec console bash -c "$AWSF s3 rm s3://marche-etat-terraform/regions/terraform.tfstate.tflock >/dev/null"; }
a_coffre-scelle()    { sur coffre "export BAO_ADDR=https://10.0.3.30:8200 BAO_CACERT=/lab/tls/racine.crt BAO_TLS_SERVER_NAME=coffre.marche.test
        bao operator unseal \"\$(jq -r '.unseal_keys_b64[0]' /var/lib/bao/init.json)\" >/dev/null"; }
a_replication-coupee() { sur passerelle "nft delete table inet panne 2>/dev/null"; sur passerelle-lome "nft delete table inet panne 2>/dev/null"; true; }
a_cle-sauvegarde()   { docker exec console bash -c "cd /root/p2/terraform/plateforme && terraform apply -auto-approve -input=false >/dev/null"
      sur "$(primaire)" "systemctl restart bao-agent"; }
a_gslb-epingle()     { sur passerelle-lome "systemctl reload nftables"; }
a_db-lecture-seule() { local a; for g in passerelle passerelle-lome; do sur $g "systemctl restart unbound"; done
      for a in $(docker ps --filter label=projet=marche --filter label=role=app --format '{{.Names}}'); do sur "$a" "systemctl restart marche.target"; done; }

# ------------------------------------------------------------------ annulations (dernier recours) — palier 1
a_mtu-trou-noir()    { sur passerelle "ip link set internet mtu 1500; nft delete table inet panne 2>/dev/null; true"; }
a_route-retour()     { sur db "ip route del 10.0.2.0/24 via 10.0.3.254 2>/dev/null; ip route replace default via 10.0.3.1"; }
a_vlan-errone()      { sur app2 "sed -i 's/Id=21/Id=20/' /etc/systemd/network/20-baie.20.netdev 2>/dev/null; ip link del baie.20; systemctl restart systemd-networkd"; }
a_arp-doublon()      { sur stockage "systemctl stop panne-arp 2>/dev/null; ip addr del 10.0.3.10/24 dev baie.30"; sur passerelle "ip neigh flush dev baie.30"; }
# (le résolveur du FAI garde aussi les ÉCHECS — SERVFAIL, NXDOMAIN — en cache : on vide tout)
vider_fai()          { sur dns-racine "unbound-control flush_zone marche.test; unbound-control flush_infra all
        unbound-control flush_negative; unbound-control flush_bogus; unbound-control flush_requestlist" >/dev/null; }
a_dns-glue()         { sur dns-racine "registre deleguer marche.test ns1.marche.test 203.0.113.10 >/dev/null"; vider_fai; }
a_dns-negatif()      { zone_ns1 remettre-www; vider_fai; }
a_chaine-incomplete() { sur lb "f=\$(awk '/crt / {for (i=1;i<=NF;i++) if (\$i==\"crt\") print \$(i+1)}' /etc/haproxy/haproxy.cfg | head -1); cp -a /root/.panne-pem \"\$f\"; systemctl reload haproxy"; }
a_nat-oublie()       { sur passerelle "systemctl reload nftables"; }
a_acl-retour()       { sur passerelle "systemctl reload nftables"; }
a_cdn-no-store()     { sur lb "cp -a /root/.panne-haproxy.cfg /etc/haproxy/haproxy.cfg; systemctl reload haproxy"; }
a_sg-sante()         { sur app1 "nft delete table inet panne 2>/dev/null; systemctl reload nftables"; }
a_wg-cle()           { sur passerelle "cp -a /root/.panne-wg /etc/wireguard/prive.key
        sed -i \"s#^PrivateKey = .*#PrivateKey = \$(cat /etc/wireguard/prive.key)#\" /etc/wireguard/wg0.conf; systemctl restart wg-quick@wg0"; }

# ------------------------------------------------------------------ commandes
case "${1:-}" in
    liste)
        for l in "${CATALOGUE[@]}"; do
            [[ -z "${2:-}" || $(champ "$l" 2) == "$2" ]] && printf 'P%s  %-18s %-22s %s\n' "$(champ "$l" 2)" "$(champ "$l" 1)" "[$(champ "$l" 4)]" "$(champ "$l" 3)"
        done ;;
    aveugle)
        n=${2:-2}; pal=${3:-1}
        [ -e "$TICKET" ] && { echo "Un tirage est déjà en cours : « $0 revele » d'abord." >&2; exit 1; }
        # (les pannes DU palier : celles des précédents visent des machines configurées autrement)
        mapfile -t tirage < <(for l in "${CATALOGUE[@]}"; do [ "$(champ "$l" 2)" = "$pal" ] && champ "$l" 1; done | shuf -n "$n")
        for p in "${tirage[@]}"; do "p_$p" >/dev/null 2>&1 || true; done
        printf '%s|%s\n' "$(date '+%F %T')" "${tirage[*]}" | base64 > "$TICKET"
        echo "🔥 $n panne(s) injectée(s) à $(date +%T). Les tickets des utilisateurs :"
        for p in "${tirage[@]}"; do for l in "${CATALOGUE[@]}"; do [[ $(champ "$l" 1) == "$p" ]] && echo "  • « $(champ "$l" 3) »"; done; done | shuf ;;
    revele)
        [ -e "$TICKET" ] || { echo "Aucun tirage en cours."; exit 0; }
        IFS='|' read -r quand pannes < <(base64 -d "$TICKET")
        echo "Tirage du $quand :"
        for p in $pannes; do for l in "${CATALOGUE[@]}"; do [[ $(champ "$l" 1) == "$p" ]] && echo "  • $p [$(champ "$l" 4)]"; done; done
        rm -f "$TICKET" ;;
    annuler)
        p=${2:?panne ?}; existe "$p" || { echo "Panne inconnue : $p" >&2; exit 1; }
        "a_$p" && echo "↩ $p annulée." ;;
    ""|-h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
        existe "$1" || { echo "Panne inconnue : $1 (voir : $0 liste)" >&2; exit 1; }
        "p_$1" && echo "🔥 Panne « $1 » injectée à $(date +%T)."
        for l in "${CATALOGUE[@]}"; do [[ $(champ "$l" 1) == "$1" ]] && echo "   Ticket : « $(champ "$l" 3) »"; done ;;
esac
