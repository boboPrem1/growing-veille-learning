#!/bin/bash
# pki.sh — sur la CONSOLE : la PKI de Marché.
#   racine (10 ans, clé qui NE QUITTE JAMAIS la console — « hors ligne »)
#     └─ intermédiaire « serveurs » (3 ans, limitée à *.marche.test par une contrainte de noms)
#          ├─ www.marche.test + marche.test   (90 jours)
#          └─ static.marche.test              (90 jours)
# Les serveurs reçoivent leur clé, leur certificat et l'intermédiaire ; les clients, la racine seule.
# Relançable : la racine et l'intermédiaire existants sont conservés, les feuilles réémises.
set -euo pipefail
P=/root/pki; install -d -m 700 "$P"; cd "$P"

# « openssl req -utf8 » partout : sans lui, le « é » de Marché dans -subj est lu octet par octet
# et encodé DEUX fois (le sujet devient « MarchÃ© »). Vérifié.
cle() { [ -f "$1" ] || (umask 077; openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1"); }

if [ ! -f racine.crt ]; then
    cle racine.key
    openssl req -utf8 -x509 -new -key racine.key -sha256 -days 3650 -out racine.crt \
        -subj "/O=Marché/CN=Marché — AC racine" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash"
fi
if [ ! -f intermediaire.crt ]; then
    cle intermediaire.key
    openssl req -utf8 -new -key intermediaire.key -out intermediaire.csr -subj "/O=Marché/CN=Marché — AC serveurs"
    cat > intermediaire.ext <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
nameConstraints=critical,permitted;DNS:marche.test,permitted;DNS:.marche.test
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
    openssl x509 -req -in intermediaire.csr -CA racine.crt -CAkey racine.key -CAcreateserial \
        -days 1095 -sha256 -extfile intermediaire.ext -out intermediaire.crt
fi

feuille() {   # feuille <nom> <SAN…>
    local n=$1; shift
    local san; san=$(printf 'DNS:%s,' "$@"); san=${san%,}
    cle "$n.key"
    openssl req -utf8 -new -key "$n.key" -out "$n.csr" -subj "/CN=$1"
    printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=%s\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid\n' "$san" > "$n.ext"
    openssl x509 -req -in "$n.csr" -CA intermediaire.crt -CAkey intermediaire.key -CAcreateserial \
        -days 90 -sha256 -extfile "$n.ext" -out "$n.crt"
    # ce que le serveur présente : SA feuille PUIS l'intermédiaire (jamais la racine : le client l'a déjà)
    cat "$n.crt" intermediaire.crt > "$n.chaine.crt"
    openssl verify -CAfile racine.crt -untrusted intermediaire.crt "$n.crt" >/dev/null
}
feuille www www.marche.test marche.test
feuille static static.marche.test
echo "PKI prête dans $P :"; ls "$P"
