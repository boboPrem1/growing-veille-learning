#!/bin/bash
# commun.sh — fonctions partagées par les rôles (sourcé par chacun d'eux).
# Les paramètres de la machine sont dans /lab/parametres.sh, écrit par Terraform.
set -euo pipefail
# shellcheck source=/dev/null
. /lab/parametres.sh

# lien <interface> <adresse IPv4/masque ou ""> <passerelle IPv4 ou ""> <adresse IPv6/64 ou "">
#   configure une interface fournie par le « fournisseur » (adresse Docker conservée)
lien() {
    local i=$1 a4=$2 gw=$3 a6=$4
    {
        printf '[Match]\nName=%s\n[Network]\nKeepConfiguration=yes\n' "$i"
        [ -z "$a4" ] || printf 'Address=%s\n' "$a4"
        [ -z "$gw" ] || printf 'Gateway=%s\n' "$gw"
        [ -z "$a6" ] || printf 'Address=%s\nIPv6AcceptRA=yes\n' "$a6"
        [ -n "$a6" ] || printf 'LinkLocalAddressing=no\n'
    } > "/etc/systemd/network/10-$i.network"
}

# vlan <id> <adresse IPv4/masque> <passerelle IPv4> <adresse IPv6/64>   (sur le trunk « baie »)
vlan() {
    local v=$1 a4=$2 gw=$3 a6=$4
    printf '[Match]\nName=baie\n[Network]\nKeepConfiguration=yes\nLinkLocalAddressing=no\nVLAN=baie.%s\n' "$v" > /etc/systemd/network/10-baie.network
    printf '[NetDev]\nName=baie.%s\nKind=vlan\n[VLAN]\nId=%s\n' "$v" "$v" > "/etc/systemd/network/20-baie.$v.netdev"
    printf '[Match]\nName=baie.%s\n[Network]\nAddress=%s\nAddress=%s\nGateway=%s\nIPv6AcceptRA=yes\n' \
        "$v" "$a4" "$a6" "$gw" > "/etc/systemd/network/20-baie.$v.network"
}

reseau_pret() {   # reseau_pret <interface> <adresse> : appliquer, puis attendre l'adresse
    systemctl enable -q systemd-networkd && systemctl restart systemd-networkd
    for _ in $(seq 40); do ip -br addr show "$1" 2>/dev/null | grep -q "${2%/*}" && { annoncer; return 0; }; sleep 0.5; done
    echo "adresse ${2} absente de $1" >&2; return 1
}

# annoncer : ARP gratuit pour chaque adresse IPv4. Une instance REMPLACÉE garde son IP mais pas sa MAC
# (aléatoire) : ses voisins (le routeur, les clients…) ont l'ancienne en cache et envoient DANS LE VIDE
# jusqu'à ce que l'entrée expire — jusqu'à ~50 s (vécu : chaque bascule de région coupait tout ce
# temps-là). L'annonce met les caches à jour tout de suite — ce que font VRRP/keepalived en bascule.
annoncer() {
    ip -4 -o addr show scope global | while read -r _ i _ a _; do
        arping -q -U -c 2 -w 3 -I "${i%%@*}" "${a%/*}" &
    done
    wait || true
}

resolveur() { printf 'nameserver %s\n' "$1" > /etc/resolv.conf; }

# pare_feu <règles> : un security group (avec état) — ce qui est accepté en entrée, rien d'autre
pare_feu() {
    cat > /etc/nftables.conf <<EOF
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
$1
    }
}
EOF
    nft -c -f /etc/nftables.conf
    systemctl enable -q nftables
    systemctl reload nftables 2>/dev/null || systemctl start nftables
}

# cle_admin : la clé SSH de l'administrateur (déposée par Terraform), comme à la création chez un hébergeur
cle_admin() {
    [ -s /lab/admin.pub ] || return 0
    install -d -m 700 -o ubuntu -g ubuntu ~ubuntu/.ssh
    install -m 600 -o ubuntu -g ubuntu /lab/admin.pub ~ubuntu/.ssh/authorized_keys
}

# ------------------------------------------------------------------ Palier 3 : l'identité de service
# identite <rôle PKI> <nom> <groupe> <commande> : un certificat d'identité (24 h), délivré et RENOUVELÉ
# par OpenBao (agent, moteur PKI). Fichiers : /etc/identite/service.{crt,key,pem} et ca.pem ; <commande>
# est lancée à chaque nouvelle identité (recharger le service qui la présente).
# Au premier démarrage, le coffre n'a pas encore d'autorité (la couche plateforme vient APRÈS les
# machines) : une identité PROVISOIRE (le certificat autosigné de la machine) permet aux services de
# démarrer ; personne ne l'accepte — la vraie la remplace dès qu'elle arrive.
identite() {
    local role=$1 nom=$2 groupe=$3 commande=$4
    install -d -m 750 -o root -g "$groupe" /etc/identite
    # (le provisoire ne va PAS dans service.pem, le fichier de l'agent : « pkiCert » garde le certificat
    #  qu'il y trouve tant qu'il est valide — un provisoire de 10 ans n'y aurait jamais été remplacé. Vécu.)
    if [ ! -s /etc/identite/service.crt ]; then
        install -m 644 /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/identite/service.crt
        install -m 640 -g "$groupe" /etc/ssl/private/ssl-cert-snakeoil.key /etc/identite/service.key
        cat /etc/identite/service.key /etc/identite/service.crt > /etc/identite/combine.pem
        chmod 640 /etc/identite/combine.pem && chgrp "$groupe" /etc/identite/combine.pem
        install -m 644 /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/identite/ca.pem
    fi
    cat > /usr/local/sbin/identite-installer <<EOF2
#!/bin/sh
# lancé par l'agent à chaque identité rendue (nouvelle, ou renouvelée) : clé et certificat séparés
# (PostgreSQL, libpq, Prometheus les veulent ainsi), droits restreints, puis rechargement du service
set -e
cd /etc/identite
[ -s service.pem ] || exit 0          # (la CA peut arriver avant l'identité)
awk '/BEGIN.*PRIVATE KEY/,/END.*PRIVATE KEY/' service.pem > service.key.n
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' service.pem > service.crt.n
chgrp $groupe service.key.n service.pem && chmod 640 service.key.n service.pem && chmod 644 service.crt.n
mv service.key.n service.key && mv service.crt.n service.crt
cat service.key service.crt > combine.pem.n && chgrp $groupe combine.pem.n && chmod 640 combine.pem.n && mv combine.pem.n combine.pem   # (clé + certificat : HAProxy)
$commande
EOF2
    chmod 755 /usr/local/sbin/identite-installer
    install -d -m 700 /etc/bao-agent
    cat > /etc/bao-agent/identite.hcl <<EOF2
template {
  destination = "/etc/identite/service.pem"
  perms       = "0640"
  command     = "/usr/local/sbin/identite-installer"
  contents    = "{{ with pkiCert \"pki-services/issue/$role\" \"common_name=$nom\" \"ttl=24h\" }}{{ .Key }}{{ .Cert }}{{ end }}"
}
template {
  destination = "/etc/identite/ca.pem"
  perms       = "0644"
  command     = "/usr/local/sbin/identite-installer"
  contents    = "{{ with secret \"pki-services/cert/ca\" }}{{ .Data.certificate }}{{ end }}"
}
EOF2
}

# agent_openbao <rôle d'authentification> : l'agent OpenBao de la machine, qui s'authentifie avec le
# certificat de sa création. Il lit TOUS les fichiers de /etc/bao-agent/ (agent.hcl, identite.hcl…).
agent_openbao() {
    install -d -m 700 /etc/bao-agent
    install -m 600 /lab/tls/client.key /etc/bao-agent/client.key
    install -m 644 /lab/tls/client.crt /etc/bao-agent/client.crt
    install -m 644 /lab/tls/racine.crt /etc/bao-agent/racine.crt
    cat > /etc/bao-agent/agent.hcl <<EOF2
vault {
  address     = "https://coffre.marche.test:8200"
  ca_cert     = "/etc/bao-agent/racine.crt"
  client_cert = "/etc/bao-agent/client.crt"
  client_key  = "/etc/bao-agent/client.key"
}
auto_auth {
  method "cert" {
    config      = { name = "$1" }
    min_backoff = "2s"
    max_backoff = "10s"
  }
}
template_config { exit_on_retry_failure = false }
EOF2
    printf '[Unit]\nDescription=Agent OpenBao\nAfter=network-online.target\n[Service]\nExecStart=/usr/local/bin/bao agent -config=/etc/bao-agent/\nRestart=always\nRestartSec=5\n[Install]\nWantedBy=multi-user.target\n' \
        > /etc/systemd/system/bao-agent.service
    systemctl daemon-reload && systemctl enable -q bao-agent && systemctl restart bao-agent
}

# ------------------------------------------------------------------ Palier 3 : BBR partout
# Mesuré sur le lab : sur un chemin long qui perd des paquets (180 ms, 0,5 %), CUBIC plafonne à
# 4,6 Mbit/s, BBR atteint 42,6 ; sur un chemin sans perte mais au gros tampon, CUBIC fait monter la
# latence des AUTRES à 580 ms, BBR la garde à 125 ms. (Réglage propre à chaque machine : il vaut par
# espace de noms réseau.)
printf 'net.ipv4.tcp_congestion_control = bbr\n' > /etc/sysctl.d/80-bbr.conf
sysctl -q -p /etc/sysctl.d/80-bbr.conf 2>/dev/null || true
