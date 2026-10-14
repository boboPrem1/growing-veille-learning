#!/usr/bin/env bash
# Pilotage du lab local (Docker) du projet fil rouge Networking & Cloud.
#
#   ./lab.sh up [1|2|3]                    démarrer le palier (1 : l'Internet + vos 8 machines ;
#                                          2 et 3 : l'Internet seul — vos machines, c'est votre Terraform)
#   ./lab.sh passer-palier-2               supprimer les machines construites à la main au Palier 1
#                                          (et leurs réseaux) : Terraform les reconstruira
#   ./lab.sh etat                          machines, adresses, état systemd
#   ./lab.sh shell <machine>               shell root sur une machine (≈ la console série du fournisseur)
#   ./lab.sh copier <fichier> <machine>:<chemin>   déposer un fichier
#   ./lab.sh registre deleguer <domaine> <ns.> <ip> [...]   déclarer vos serveurs de noms au registre de « .test »
#   ./lab.sh registre voir
#   ./lab.sh detruire <machine>            supprimer une machine du Palier 1 ET ses données
#   ./lab.sh recreer <machine>             la recréer vierge
#   ./lab.sh identifiants                  (Paliers 2 et 3) les clés de votre compte S3 chez le fournisseur
#   ./lab.sh down                          tout arrêter (les données sont conservées)
set -euo pipefail
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1   # Git Bash (Windows) : ne pas réécrire les chemins /sys, /var…
mkdir -p ../../rendu
TOUS=(--profile p1 --profile p2 --profile p3)
VOS_MACHINES=(edge passerelle lb ns1 app1 app2 db stockage)

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
profil() { case "${1:-1}" in 1) echo p1 ;; 2) echo p2 ;; 3) echo p3 ;; *) usage ;; esac; }

attendre_systemd() {
    local m=$1 etat
    for _ in $(seq 1 90); do
        etat=$(docker exec "$m" systemctl is-system-running 2>/dev/null || true)
        [[ "$etat" == running || "$etat" == degraded ]] && { printf '  %-11s systemd %s\n' "$m" "$etat"; return; }
        sleep 1
    done
    echo "  $m : systemd ne démarre pas (docker logs $m)" >&2
}
# les machines du lab : celles de Compose, et celles que votre Terraform a créées (étiquette projet=marche)
machines() {
    { docker ps -a --filter "label=com.docker.compose.project=marche-cloud" --format '{{.Names}}'
      docker ps -a --filter "label=projet=marche" --format '{{.Names}}'; } | sort -u
}

# L'« AC publique du lab » et le certificat du service S3 du fournisseur : créés une fois, sur l'hôte.
# La racine entre dans l'image (magasin de confiance de toutes les machines) ; les clés, jamais.
preparer_ac() {
    [ -s internet/ac/ac.crt ] && [ -s internet/s3/s3.crt ] && return
    mkdir -p internet/ac internet/s3
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out internet/ac/ac.key 2>/dev/null
    openssl req -utf8 -x509 -new -key internet/ac/ac.key -days 3650 -subj "/O=Lab/CN=AC publique du lab" \
        -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out internet/ac/ac.crt
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out internet/s3/s3.key 2>/dev/null
    openssl req -new -key internet/s3/s3.key -subj "/CN=s3.fournisseur.test" -out internet/s3/s3.csr
    printf 'subjectAltName=DNS:s3.fournisseur.test,IP:203.0.113.30\nextendedKeyUsage=serverAuth\n' > internet/s3/s3.ext
    openssl x509 -req -in internet/s3/s3.csr -CA internet/ac/ac.crt -CAkey internet/ac/ac.key -CAcreateserial \
        -days 365 -extfile internet/s3/s3.ext -out internet/s3/s3.crt 2>/dev/null
    rm -f internet/s3/s3.csr internet/s3/s3.ext internet/ac/ac.srl
    echo "AC publique du lab créée (lab/docker/internet/ac/)."
}

case "${1:-}" in
    identifiants)
        echo "# Votre compte S3 chez le fournisseur (https://s3.fournisseur.test) :"
        docker exec s3 cat /etc/s3/compte.env ;;
    up)
        preparer_ac
        p=$(profil "${2:-1}")
        docker compose --profile "$p" up -d --build
        for m in $(docker compose --profile "$p" ps --services); do attendre_systemd "$m"; done
        if [ "$p" = p3 ]; then
            # La dorsale et le client gagnent une interface au Palier 3 : on les BRANCHE (sans les
            # recréer — un client recréé perd la racine de confiance que vous y avez installée).
            #  - la dorsale (TransAtlantique) : le lien de peering avec OuestNet ;
            #  - le client : il devient abonné de TogoNet, et tout son trafic passe par ce FAI.
            brancher() {  # brancher <machine> <réseau> <adresse> <interface>
                docker inspect -f '{{json .NetworkSettings.Networks}}' "$1" | grep -q "marche-cloud_$2" \
                    || docker network connect --ip "$3" --driver-opt "com.docker.network.endpoint.ifname=$4" "marche-cloud_$2" "$1"
            }
            brancher backbone interco 198.18.0.1 interco
            brancher client togonet 198.18.30.50 togonet
            docker exec backbone bash /lab/init.sh
            docker exec client sh -c 'mkdir -p /etc/lab && echo 198.18.30.1 > /etc/lab/fai && bash /lab/init.sh'
        fi ;;
    passer-palier-2)
        read -r -p "Supprimer vos 8 machines du Palier 1 (${VOS_MACHINES[*]}) et les réseaux pub et baie ? [oui/non] " rep
        [[ "$rep" == oui ]] || exit 0
        docker compose "${TOUS[@]}" rm -sf "${VOS_MACHINES[@]}"
        docker network rm marche-cloud_pub marche-cloud_baie 2>/dev/null || true
        echo "Fait. La console, sa PKI et sa clé SSH sont conservées. Suite : palier-2.md." ;;
    etat)
        machines | while read -r m; do
            [ "$(docker inspect -f '{{.State.Running}}' "$m")" = true ] || { printf '%-11s arrêtée\n' "$m"; continue; }
            printf '%-11s %-8s %s\n' "$m" "$(docker exec "$m" systemctl is-system-running 2>/dev/null || true)" \
                "$(docker exec "$m" ip -4 -br addr 2>/dev/null | awk '$1!="lo" && $3 {printf "%s=%s ", $1, $3}')"
        done ;;
    shell)   docker exec -it "${2:?machine ?}" bash -l ;;
    copier)  docker cp "${2:?fichier ?}" "${3:?machine:chemin ?}" ;;
    registre) shift; docker exec dns-racine registre "$@" ;;
    detruire)
        m=${2:?machine ?}
        read -r -p "Détruire $m et TOUTES ses données ? [oui/non] " rep
        [[ "$rep" == oui ]] || exit 0
        docker compose "${TOUS[@]}" rm -sf "$m" ;;
    recreer)
        m=${2:?machine ?}
        docker compose "${TOUS[@]}" up -d "$m" && attendre_systemd "$m" ;;
    down) machines | xargs -r docker stop -t 20 >/dev/null; echo "Lab arrêté." ;;
    *) usage ;;
esac
