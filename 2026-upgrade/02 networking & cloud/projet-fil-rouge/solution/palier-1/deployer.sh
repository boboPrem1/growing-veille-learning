#!/usr/bin/env bash
# deployer.sh — déroule la solution de référence du Palier 1 sur le lab Docker, depuis l'hôte.
# Relançable. Les secrets du lab sont tirés au hasard au premier passage et gardés dans .secrets/
# (hors dépôt). Chaque étape = un script de machines/, copié puis exécuté sur la machine.
set -euo pipefail
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
M=machines
T=.tmp; mkdir -p "$T" .secrets; trap 'rm -rf "$T"' EXIT

# (openssl rand, pas « tr -dc … < /dev/urandom | head » : sous pipefail, SIGPIPE — voir le projet Linux)
secret() { [ -s ".secrets/$1" ] || openssl rand -hex 12 > ".secrets/$1"; cat ".secrets/$1"; }
MDP_DB=$(secret db)
MDP_S3=$(secret s3-admin)

pousser() { for f in "${@:2}"; do docker cp "$f" "$1:/root/$(basename "$f")"; done; }
lancer()  { local m=$1 s=$2; shift 2; pousser "$m" "$M/$s"; docker exec "$m" bash "/root/$s" "$@"; }
depuis()  { docker exec "$1" cat "$2" > "$T/$3"; }      # depuis <machine> <fichier> <nom local>

echo "== passerelle";   lancer passerelle passerelle.sh | tail -1
echo "== ns1";          lancer ns1 ns1.sh
echo "== registre";     docker exec dns-racine registre deleguer marche.test ns1.marche.test 203.0.113.10 | tail -2
echo "== db";           pousser db "$M/vlan.sh"; lancer db db.sh "$MDP_DB"
echo "== stockage";     pousser stockage "$M/vlan.sh"; lancer stockage stockage.sh "$MDP_S3"
depuis stockage /root/marche-app.env marche-app.env
for n in 1 2; do
    echo "== app$n";    pousser "app$n" "$M/vlan.sh" "$T/marche-app.env"; lancer "app$n" app.sh "$n" "$MDP_DB"
done
echo "== PKI (console)"; lancer console pki.sh | tail -1
docker exec console sh -c 'cat /root/pki/www.key /root/pki/www.chaine.crt' > "$T/www.pem"
docker exec console sh -c 'cat /root/pki/static.key /root/pki/static.chaine.crt' > "$T/static.pem"
depuis console /root/pki/racine.crt racine.crt
echo "== lb";           pousser lb "$T/www.pem"; lancer lb lb.sh
echo "== edge";         pousser edge "$T/static.pem" "$T/racine.crt"; lancer edge edge.sh
echo "== client";       pousser client "$T/racine.crt"; lancer client client.sh

echo "== VPN d'administration"
lancer console console.sh "$(docker exec passerelle cat /etc/wireguard/public.key)" | tail -1
depuis console /etc/wireguard/public.key console.pub
docker cp "$T/console.pub" passerelle:/etc/wireguard/console.pub
lancer passerelle passerelle.sh | tail -1
depuis console /root/.ssh/id_ed25519.pub admin.pub
for m in passerelle lb ns1 app1 app2 db stockage; do     # comme une clé fournie à la création
    docker exec -i "$m" sh -c 'install -d -m 700 -o ubuntu -g ubuntu ~ubuntu/.ssh
        cat > ~ubuntu/.ssh/authorized_keys; chown ubuntu:ubuntu ~ubuntu/.ssh/authorized_keys
        chmod 600 ~ubuntu/.ssh/authorized_keys' < "$T/admin.pub"
done
echo "== rendu (documents de la solution + capture de la poignée de main)"
R=../../rendu/palier-1; mkdir -p "$R"
for f in rendu/*.md; do [ -e "$R/$(basename "$f")" ] || cp "$f" "$R/"; done
docker exec console bash -c 'install -d /srv/rendu/palier-1
    timeout 20 tcpdump -i internet -c 30 -w /srv/rendu/palier-1/poignee.pcap "host 203.0.113.10 and tcp port 443" 2>/dev/null &
    sleep 2
    curl -s --cacert /root/pki/racine.crt -o /dev/null https://www.marche.test/api/products
    wait'
echo "Solution du Palier 1 déployée."
