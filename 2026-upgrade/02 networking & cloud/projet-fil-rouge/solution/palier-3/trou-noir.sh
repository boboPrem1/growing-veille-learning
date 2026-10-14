#!/usr/bin/env bash
# trou-noir.sh — sous attaque volumétrique (DDoS), faire JETER le trafic vers une adresse par notre
# transitaire, à sa frontière, avant qu'il ne sature notre lien (RTBH, Remote Triggered Black Hole).
#   ./trou-noir.sh <europe|lome> activer <adresse>     annoncer <adresse>/32 avec 65010:666
#   ./trou-noir.sh <europe|lome> lever    <adresse>
# Le prix : l'adresse devient INJOIGNABLE pour tout le monde — l'attaquant a gagné sur cette adresse,
# mais le reste de la région respire. On bascule le service ailleurs (anycast, DNS), puis on lève.
set -euo pipefail
export MSYS_NO_PATHCONV=1
p=$([ "${1:?région ?}" = europe ] && echo passerelle || echo passerelle-lome)
ip=${3:?adresse ?}
case ${2:?activer|lever ?} in
    activer) docker exec "$p" vtysh -c 'configure terminal' -c "ip prefix-list TROU-NOIR seq 10 permit $ip/32" \
                 -c 'router bgp 64500' -c 'address-family ipv4 unicast' -c "network $ip/32" ;;
    lever)   docker exec "$p" vtysh -c 'configure terminal' -c 'router bgp 64500' -c 'address-family ipv4 unicast' -c "no network $ip/32" \
                 -c 'exit-address-family' -c 'exit' -c "no ip prefix-list TROU-NOIR seq 10 permit $ip/32" ;;
esac
docker exec "$p" vtysh -c "show ip bgp neighbors $([ "$1" = europe ] && echo 203.0.113.1 || echo 192.0.2.1) advertised-routes" | grep -E "$ip|Total"
