#!/bin/bash
# registre — le registre du TLD « test. » : c'est ici qu'un domaine est délégué à ses
# serveurs de noms (enregistrements NS dans la zone parente) avec leur adresse (glue).
#
#   registre deleguer <domaine> <ns1.nom.> <ip> [<ns2.nom.> <ip>]   (re)définir la délégation
#   registre retirer <domaine>
#   registre voir
set -euo pipefail
D=/var/lib/registre/delegations.db
Z=/var/lib/registre/test.zone

regenerer() {
    {
        printf '$TTL 86400\n'
        # dernier champ : le TTL NÉGATIF du TLD — tout nom demandé AVANT la délégation de son domaine
        # reste « inexistant » dans les caches pendant cette durée (5 min ici ; bien plus chez un vrai TLD)
        printf 'test.          IN SOA ns.tld.test. hostmaster.tld.test. ( %s 1800 900 604800 300 )\n' "$(date +%s)"
        printf 'test.          IN NS  ns.tld.test.\n'
        printf 'ns.tld.test.   IN A   192.0.2.54\n'
        printf 'a.racine.test. IN A   192.0.2.53\n'
        printf '; --- les services du fournisseur (hors de vos VPC) ---\n'
        printf 's3.fournisseur.test. IN A 203.0.113.30\n'
        printf '; --- délégations (registre) ---\n'
        cat "$D"
    } > "$Z.tmp"
    chown bind:bind "$Z.tmp"; mv "$Z.tmp" "$Z"
    ! systemctl is-active -q named || rndc reload test. IN tld >/dev/null
}

case "${1:-}" in
    --regenerer) regenerer ;;
    deleguer)
        dom=${2:?domaine ?}; dom=${dom%.}.
        [[ $dom == *.test. ]] || { echo "Ce registre ne gère que « .test »" >&2; exit 1; }
        shift 2; [ $# -ge 2 ] && [ $(($# % 2)) -eq 0 ] || { echo "usage : registre deleguer <domaine> <ns.> <ip> [<ns.> <ip>]" >&2; exit 1; }
        grep -Ev "^$dom |.$dom " "$D" > "$D.tmp" || true
        while [ $# -gt 0 ]; do
            ns=${1%.}.; ip=$2; shift 2
            printf '%s 86400 IN NS %s\n' "$dom" "$ns" >> "$D.tmp"
            # glue : seulement si le serveur de noms est DANS le domaine délégué
            [[ $ns == *".$dom" ]] && printf '%s 86400 IN A %s\n' "$ns" "$ip" >> "$D.tmp"
        done
        mv "$D.tmp" "$D"; regenerer
        echo "Délégation de $dom enregistrée :"; grep -E "^$dom |\.$dom " "$D" ;;
    retirer)
        dom=${2:?domaine ?}; dom=${dom%.}.
        grep -Ev "^$dom |\.$dom " "$D" > "$D.tmp" || true; mv "$D.tmp" "$D"; regenerer ;;
    voir) cat "$D" ;;
    *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
