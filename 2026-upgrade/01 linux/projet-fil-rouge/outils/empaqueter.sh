#!/usr/bin/env bash
# Fabrique l'archive de livraison de Marché : livraison/marche-<version>.tar.gz
# (un dossier racine marche-<version>/ contenant le code et un fichier VERSION).
#
#   ./outils/empaqueter.sh 1.0.0             version normale
#   ./outils/empaqueter.sh 1.2.0 --cassee    version qui plante au démarrage (Palier 2 : retour arrière)
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage : $0 <version> [--cassee]}
cassee=${2:-}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

racine="$tmp/marche-$version"
mkdir -p "$racine" livraison
cp app/*.py app/requirements.txt "$racine/"
echo "$version" > "$racine/VERSION"
if [[ $cassee == --cassee ]]; then
    # Simule une régression réelle : une dépendance oubliée, qui fait planter le gateway au démarrage
    sed -i '0,/^import /s//import module_oublie_par_le_developpeur  # régression volontaire\nimport /' "$racine/gateway.py"
fi
tar -czf "livraison/marche-$version.tar.gz" -C "$tmp" "marche-$version"
# Empreinte avec le NOM SEUL du fichier : « sha256sum -c » fonctionne depuis le dossier de l'archive
(cd livraison && sha256sum "marche-$version.tar.gz" | tee "marche-$version.tar.gz.sha256")
