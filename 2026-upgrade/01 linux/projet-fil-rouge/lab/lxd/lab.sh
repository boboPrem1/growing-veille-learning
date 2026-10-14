#!/usr/bin/env bash
# Pilotage du lab sur le VPS, avec LXD (ou Incus). À lancer SUR le VPS, par un utilisateur
# membre du groupe « lxd » (ou « incus-admin »). Même vocabulaire que ../docker/lab.sh.
#
#   ./lab.sh init                           prérequis + réseau privé 10.10.10.0/24 + profil « marche »
#   ./lab.sh up 1|3 [--vm]                  créer les machines du palier (--vm : VMs KVM au lieu de conteneurs)
#                                           (Palier 3 : 6 machines + le poste de contrôle Ansible « ctl »)
#   ./lab.sh shell <machine>                shell root dans la machine
#   ./lab.sh copier <fichier> <machine>:<chemin>
#   ./lab.sh ajouter-disque <machine> <nom> <taille>   (VM uniquement) ex. : web1 disque2 2GiB
#   ./lab.sh detruire <machine> | recreer <machine> [--vm]
#   ./lab.sh autoriser <cle.pub>            injecter une clé dans ~ubuntu/.ssh de toutes les machines
#                                           (comme un hébergeur à la création ; refait par « recreer »)
#   ./lab.sh ssh-config                     bloc ~/.ssh/config à coller sur VOTRE PC (rebond par le VPS)
#   ./lab.sh etat | down
#
# Garanties : ce script ne modifie NI le pare-feu, NI SSH, NI les services de l'hôte. Il crée
# uniquement un réseau LXD privé, un profil, des machines de lab et, sur demande, leurs volumes.
set -euo pipefail

if command -v incus >/dev/null 2>&1; then CLI=incus; elif command -v lxc >/dev/null 2>&1; then CLI=lxc
else echo "Ni LXD ni Incus : sudo snap install lxd && sudo usermod -aG lxd \$USER (puis se reconnecter)" >&2; exit 1; fi

RESEAU=marchenet
PROFIL=marche
IMAGE=ubuntu:24.04
[[ $CLI == incus ]] && IMAGE=images:ubuntu/24.04/cloud
declare -A IP=([ctl]=10.10.10.5 [lb1]=10.10.10.11 [lb2]=10.10.10.12 [web1]=10.10.10.21 [web2]=10.10.10.22 [db1]=10.10.10.31 [bak1]=10.10.10.41)
PALIER1=(web1)
PALIER3=(ctl lb1 lb2 web1 web2 db1 bak1)
CLE="$(dirname "$0")/.cle-autorisee.pub"     # la clé enregistrée par « autoriser »

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
existe() { $CLI info "$1" >/dev/null 2>&1; }

init() {
    if ! $CLI network list --format csv >/dev/null 2>&1; then
        echo "LXD n'est pas initialisé : lancement de « lxd init --auto » (stockage « dir », bridge par défaut)."
        if [[ $CLI == lxc ]]; then sudo lxd init --auto; else sudo incus admin init --auto; fi
    fi
    if ! $CLI network show "$RESEAU" >/dev/null 2>&1; then
        $CLI network create "$RESEAU" ipv4.address=10.10.10.1/24 ipv4.nat=true \
            ipv4.dhcp.ranges=10.10.10.200-10.10.10.250 ipv6.address=none
    fi
    if ! $CLI profile show "$PROFIL" >/dev/null 2>&1; then
        $CLI profile create "$PROFIL"
        $CLI profile device add "$PROFIL" eth0 nic network="$RESEAU" name=eth0
        $CLI profile set "$PROFIL" limits.memory=1GiB limits.cpu=1
    fi
    echo "✔ Réseau $RESEAU et profil $PROFIL prêts."
    if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
        cat <<EOF
⚠ ufw est actif sur l'hôte. S'il bloque le DHCP/DNS ou le NAT du lab, les machines n'auront
  ni IP ni Internet. Règles habituelles (à ajouter VOUS-MÊME, après les avoir lues) :
    sudo ufw allow in on $RESEAU
    sudo ufw route allow in on $RESEAU
    sudo ufw route allow out on $RESEAU
EOF
    fi
    if [ -e /dev/kvm ]; then echo "✔ /dev/kvm présent : les VMs (--vm) sont possibles."
    else echo "ℹ Pas de /dev/kvm : conteneurs uniquement (voir le guide pour le stockage et auditd)."; fi
}

# Ce que fait cloud-init chez un hébergeur : la clé fournie à la création est déposée dans
# le compte par défaut (ubuntu, sudo sans mot de passe).
injecter_cle() {
    local m=$1
    [ -s "$CLE" ] || return 0
    $CLI exec "$m" -- install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
    $CLI file push "$CLE" "$m/home/ubuntu/.ssh/authorized_keys" --uid 1000 --gid 1000 --mode 0600
    echo "  $m : clé autorisée pour ubuntu"
}

creer() {
    local m=$1 vm=${2:-}
    existe "$m" && { echo "  $m existe déjà"; return; }
    $CLI init "$IMAGE" "$m" -p default -p "$PROFIL" ${vm:+--vm}
    $CLI config device override "$m" eth0 ipv4.address="${IP[$m]}"
    $CLI start "$m"
    echo -n "  $m : démarrage"
    for _ in $(seq 1 90); do
        etat=$($CLI exec "$m" -- systemctl is-system-running 2>/dev/null || true)
        [[ $etat == running || $etat == degraded ]] && { echo " → $etat (${IP[$m]})"; injecter_cle "$m"; return; }
        echo -n "."; sleep 2
    done
    echo " → délai dépassé, voir : $CLI console $m --show-log"
}

case "${1:-}" in
    init) init ;;
    up)
        palier=${2:-1}; vm=""; [[ "${3:-}" == --vm ]] && vm=1
        [[ -n $vm && ! -e /dev/kvm ]] && { echo "--vm demandé mais /dev/kvm absent" >&2; exit 1; }
        if [[ $palier == 3 ]]; then machines=("${PALIER3[@]}"); else machines=("${PALIER1[@]}"); fi
        for m in "${machines[@]}"; do creer "$m" "$vm"; done ;;
    shell) $CLI exec "${2:?machine ?}" -- bash -l ;;
    copier)
        src=${2:?fichier ?}; dst=${3:?machine:chemin ?}
        $CLI file push "$src" "${dst%%:*}${dst#*:}" ;;
    ajouter-disque)
        m=${2:?machine ?}; nom=${3:?nom ?}; taille=${4:?taille ?}
        [[ $($CLI info "$m" | awk '/^Type:/{print $2}') == virtual-machine ]] \
            || { echo "Disque bloc : VM uniquement (machine créée avec --vm). Voir le guide." >&2; exit 1; }
        $CLI storage volume create default "$m-$nom" --type=block size="$taille"
        $CLI storage volume attach default "$m-$nom" "$m"
        echo "✔ Dans $m : lsblk (nouveau disque, souvent /dev/sdb)" ;;
    detruire)
        m=${2:?machine ?}
        read -r -p "Détruire $m et TOUTES ses données ? [oui/non] " rep
        [[ $rep == oui ]] && $CLI delete --force "$m" ;;
    recreer) creer "${2:?machine ?}" "$([[ "${3:-}" == --vm ]] && echo 1)" ;;
    autoriser)
        cp "${2:?clé publique ?}" "$CLE"
        for m in "${PALIER3[@]}"; do existe "$m" && injecter_cle "$m"; done ;;
    ssh-config)
        vps_user=$(whoami); vps_host=$(hostname -f)
        echo "# ~/.ssh/config sur VOTRE PC — remplacez HostName du VPS si besoin (IP publique ou nom DNS)"
        echo "Host vps"; echo "    HostName $vps_host"; echo "    User $vps_user"; echo
        for m in "${PALIER3[@]}"; do
            printf 'Host %s\n    HostName %s\n    User VOTRE_UTILISATEUR_DE_LAB\n    ProxyJump vps\n\n' "$m" "${IP[$m]}"
        done ;;
    etat) $CLI list -c ns4tS --format table ;;
    down) for m in "${PALIER3[@]}"; do existe "$m" && $CLI stop "$m" --force 2>/dev/null || true; done ;;
    *) usage ;;
esac
