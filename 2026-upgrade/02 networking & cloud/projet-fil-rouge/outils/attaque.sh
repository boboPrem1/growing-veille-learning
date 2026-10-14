#!/usr/bin/env bash
# attaque.sh — des attaques (bénignes, mais réalistes) lancées depuis le client de Lomé, pour éprouver
# votre IDS/IPS et votre supervision (Palier 3). À lancer SUR L'HÔTE du lab.
#
#   ./outils/attaque.sh balayage <adresse>   tentatives de connexion sur 200 ports (reconnaissance)
#   ./outils/attaque.sh ssh <adresse>        recherche d'un SSH ouvert, depuis Internet
#   ./outils/attaque.sh dns-any <adresse>    requêtes DNS « ANY » (le moteur des attaques par amplification)
#
# Ce que vous devez voir : l'alerte (eve.json de Suricata, puis le pager de la supervision) ; pour
# « dns-any », le BLOCAGE — et aucune gêne pour les clients ordinaires pendant ce temps.
set -euo pipefail
export MSYS_NO_PATHCONV=1
cible=${2:?adresse visée ?}
case ${1:-} in
    balayage)
        docker exec client bash -c "for p in \$(seq 20 219); do (timeout 1 bash -c \"</dev/tcp/$cible/\$p\" 2>/dev/null && echo \"ouvert : \$p\") & done; wait" || true ;;
    ssh)
        docker exec client bash -c "for i in 1 2 3 4 5; do timeout 2 bash -c '</dev/tcp/$cible/22' 2>/dev/null && echo 'SSH ouvert !'; sleep 0.5; done" || true ;;
    dns-any)
        # (en UDP, comme une vraie amplification : l'attaquant usurpe l'adresse de sa victime, ce que
        #  la poignée de main de TCP interdit — une requête ANY en TCP n'amplifie rien pour lui)
        docker exec client bash -c "n=0; for i in \$(seq 10); do dig +notcp +ignore +time=1 +tries=1 @$cible marche.test ANY 2>/dev/null | grep -q 'status: NOERROR' && n=\$((n + 1)); done; \
            echo \"requêtes ANY qui ont obtenu une réponse : \$n / 10\"; \
            echo \"requête ordinaire pendant l'attaque : \$(dig +time=2 +tries=1 +short @$cible www.marche.test A)\"" ;;
    *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
echo "attaque « $1 » terminée"
