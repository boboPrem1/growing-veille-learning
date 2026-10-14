#!/usr/bin/env bash
# Pilotage du lab LOCAL (Docker). Même vocabulaire que ../lxd/lab.sh (lab sur le VPS).
#
#   ./lab.sh up 1|3                         démarrer le lab du palier (1 = web1, 3 = 6 machines + ctl)
#   ./lab.sh shell <machine>                ouvrir un shell root (≈ lxc exec <machine> bash)
#   ./lab.sh copier <fichier> <machine>:<chemin>   déposer un fichier (≈ lxc file push)
#   ./lab.sh ajouter-disque <machine> <nom> <taille>   ex. : web1 disque2 2G  → /dev/disk/lab/disque2
#   ./lab.sh detruire <machine>             supprimer une machine ET ses données (plan de reprise)
#   ./lab.sh recreer <machine>              la recréer vierge
#   ./lab.sh autoriser <cle.pub>            injecter une clé dans ~ubuntu/.ssh de toutes les machines
#                                           (comme un hébergeur à la création ; refait par « recreer »)
#   ./lab.sh etat                           machines, IP, état systemd
#   ./lab.sh down                           tout arrêter (les données sont conservées)
set -euo pipefail
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1   # Git Bash (Windows) : ne pas réécrire les chemins /sys, /var…

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
CLE=.cle-autorisee.pub      # la clé enregistrée par « autoriser »

# Ce que fait cloud-init chez un hébergeur : la clé publique fournie à la création de la
# machine est déposée dans le compte par défaut (ubuntu, sudo sans mot de passe).
injecter_cle() {
    local m=$1
    [ -s "$CLE" ] || return 0
    docker exec -i "$m" bash -c 'install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
        cat > /home/ubuntu/.ssh/authorized_keys; chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
        chmod 600 /home/ubuntu/.ssh/authorized_keys' < "$CLE"
    echo "  $m : clé autorisée pour ubuntu"
}

# Le noyau (celui de Docker) est partagé par tous les conteneurs : avant de supprimer une
# machine, on désactive ses volumes LVM et on détache ses loops, sinon ils restent orphelins.
liberer_disques() {
    docker exec "$1" bash -c 'command -v vgs >/dev/null || exit 0
        for vg in $(vgs --noheadings -o vg_name); do
            for d in $(lvs --noheadings -o lv_dm_path "$vg"); do umount -l "$d" 2>/dev/null; done
            vgchange -an "$vg"
        done
        losetup -D' >/dev/null 2>&1 || true
}

attendre_systemd() {
    local m=$1
    for _ in $(seq 1 60); do
        etat=$(docker exec "$m" systemctl is-system-running 2>/dev/null || true)
        [[ "$etat" == running || "$etat" == degraded ]] && { echo "  $m : systemd $etat"; return; }
        sleep 1
    done
    echo "  $m : systemd ne démarre pas (voir docker logs $m)" >&2
}

case "${1:-}" in
    up)
        palier=${2:-1}
        [[ "$palier" == 1 || "$palier" == 2 ]] && profil=p1 || profil=p3
        docker compose --profile "$profil" up -d --build
        for m in $(docker compose --profile "$profil" ps --services); do attendre_systemd "$m"; injecter_cle "$m"; done ;;
    autoriser)
        cp "${2:?clé publique ?}" "$CLE"
        for m in $(docker compose --profile p3 ps --services); do injecter_cle "$m"; done ;;
    shell)
        docker exec -it "${2:?machine ?}" bash -l ;;
    copier)
        src=${2:?fichier ?}; dst=${3:?machine:chemin ?}
        docker cp "$src" "$dst" ;;
    ajouter-disque)
        m=${2:?machine ?}; nom=${3:?nom ?}; taille=${4:?taille ?}
        docker exec "$m" bash -c "mkdir -p /var/lib/lab/disques && truncate -s $taille /var/lib/lab/disques/$nom.img && /usr/local/sbin/lab-disques" ;;
    detruire)
        m=${2:?machine ?}
        read -r -p "Détruire $m et TOUTES ses données ? [oui/non] " rep
        [[ "$rep" == oui ]] || exit 0
        liberer_disques "$m"
        docker compose --profile p3 rm -sf "$m" ;;
    recreer)
        m=${2:?machine ?}
        docker compose --profile p3 up -d "$m" && attendre_systemd "$m" && injecter_cle "$m" ;;
    etat)
        docker ps --filter "label=com.docker.compose.project=marche-lab" \
            --format '{{.Names}}' | sort | while read -r m; do
            ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$m")
            printf '%-6s %-13s %s\n' "$m" "$ip" "$(docker exec "$m" systemctl is-system-running 2>/dev/null || true)"
        done ;;
    down)
        docker compose --profile p3 stop ;;
    *) usage ;;
esac
