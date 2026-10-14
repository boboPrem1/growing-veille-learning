#!/bin/bash
# Solution de référence — Palier 2 : fiabiliser et durcir web1 (part d'un web1 au Palier 1).
# Relançable : chaque étape vérifie l'état avant d'agir.
#
# Usage (root, sur web1, depuis ce dossier) :
#   DISQUE=/dev/disk/lab/disque2 ADMIN=moi DEPLOY_PUBKEY=/root/deploy.pub \
#   ARCHIVE=/root/marche-1.1.0.tar.gz ./provision.sh
#   (DISQUE : sur une VM LXD, souvent /dev/sdb ; « lsblk » pour le trouver)
set -Eeuo pipefail
trap 'echo "ÉCHEC ligne $LINENO : $BASH_COMMAND" >&2' ERR

DISQUE=${DISQUE:?variable DISQUE requise : le disque vierge pour LVM}
ADMIN=${ADMIN:?variable ADMIN requise : votre compte d administration}
DEPLOY_PUBKEY=${DEPLOY_PUBKEY:?variable DEPLOY_PUBKEY requise : clé publique du compte deploy}
ARCHIVE=${ARCHIVE:?variable ARCHIVE requise : marche-X.Y.Z.tar.gz à déployer}
F="$(cd "$(dirname "$0")" && pwd)/fichiers"
etape() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "À lancer en root" >&2; exit 1; }

etape "1. Paquets"
apt-get update -q
apt-get install -y -q lvm2 acl nftables fail2ban rsync
# Lab Docker : pas d'udev, LVM doit créer lui-même les nœuds /dev (sans effet ailleurs)
[ -x /usr/local/sbin/lab-disques ] && /usr/local/sbin/lab-disques >/dev/null

etape "2. Stockage : LVM sur $DISQUE"
if ! vgs vg_marche >/dev/null 2>&1; then
    [ -z "$(blkid -o value -s TYPE "$DISQUE" 2>/dev/null)" ] || { echo "$DISQUE n'est pas vierge : refus" >&2; exit 1; }
    pvcreate -q "$DISQUE"
    vgcreate -q vg_marche "$DISQUE"
    lvcreate -q -y -L 1G   -n lv_pgdata  vg_marche
    lvcreate -q -y -L 400M -n lv_backups vg_marche
    mkfs.ext4 -q -L pgdata  /dev/vg_marche/lv_pgdata
    mkfs.ext4 -q -L backups /dev/vg_marche/lv_backups
fi

monter() {   # monter <lv> <point> <options> : migre le contenu existant, déclare dans fstab par UUID
    local lv=$1 point=$2 opts=$3 uuid
    uuid=$(blkid -o value -s UUID "/dev/vg_marche/$lv")
    mountpoint -q "$point" && return 0
    mkdir -p /mnt/migration "$point"
    mountpoint -q /mnt/migration && umount /mnt/migration     # reprise après un échec
    mount "/dev/vg_marche/$lv" /mnt/migration
    rsync -aHAX --delete --exclude lost+found "$point"/ /mnt/migration/
    umount /mnt/migration
    grep -q "$uuid" /etc/fstab || echo "UUID=$uuid  $point  ext4  $opts  0  2" >> /etc/fstab
    systemctl daemon-reload
    mount "$point"
}
systemctl stop marche.target marche-gateway marche-orders marche-payments marche-loadgen 2>/dev/null || true
# postgresql.service n'est qu'une ENVELOPPE sur Ubuntu/Debian : « stop postgresql » rend la main
# avant la fin de l'arrêt de l'instance réelle. On arrête l'instance et on le vérifie.
systemctl stop postgresql 'postgresql@*'
pg_lsclusters --no-header | awk '$4 != "down" {exit 1}' || { echo "PostgreSQL tourne encore : refus de copier" >&2; exit 1; }
monter lv_pgdata  /var/lib/postgresql defaults
monter lv_backups /var/backups/marche defaults,nofail
findmnt --verify >/dev/null
systemctl start postgresql
chown root:root /var/backups/marche && chmod 750 /var/backups/marche

etape "3. Agrandir le volume des sauvegardes à chaud (+200 Mo)"
taille=$(lvs --noheadings --units m -o lv_size vg_marche/lv_backups | tr -dc '0-9.' | cut -d. -f1)
[ "$taille" -ge 600 ] || lvextend -q -r -L +200M vg_marche/lv_backups
df -h /var/backups/marche | tail -1

etape "4. Comptes : deploy, groupe ssh-autorises, audit, partage"
getent group ssh-autorises >/dev/null || groupadd ssh-autorises
id -u deploy >/dev/null 2>&1 || useradd -m -s /bin/bash deploy
id -u audit  >/dev/null 2>&1 || useradd -m -s /bin/bash audit
usermod -aG ssh-autorises "$ADMIN"; usermod -aG ssh-autorises deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
install -m 600 -o deploy -g deploy "$DEPLOY_PUBKEY" /home/deploy/.ssh/authorized_keys
install -m 440 "$F/sudoers.d/marche-deploy" /etc/sudoers.d/marche-deploy
visudo -c -q
# Dossier partagé de l'équipe : SGID (le groupe devs se propage) + ACL par défaut pour audit
install -d -m 2770 -o root -g devs /srv/partage
setfacl -m u:audit:rx /srv/partage && setfacl -d -m u:audit:rx /srv/partage
# audit lit les journaux de Marché sans être dans devs
setfacl -m u:audit:rx /var/log/marche && setfacl -d -m u:audit:r /var/log/marche
setfacl -m u:audit:r /var/log/marche/*.log

etape "5. Certificat TLS (auto-signé, lab)"
if [ ! -f /etc/ssl/private/marche.key ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=web1" \
        -addext "subjectAltName=DNS:web1,DNS:localhost,IP:127.0.0.1,IP:10.10.10.21" \
        -keyout /etc/ssl/private/marche.key -out /etc/ssl/certs/marche.crt 2>/dev/null
    chmod 600 /etc/ssl/private/marche.key
fi

etape "6. Déploiement par versions + unités modèles"
install -m 700 "$F/sbin/marchectl" /usr/local/sbin/marchectl
install -m 755 "$F/bin/marche-healthcheck" /usr/local/bin/marche-healthcheck
install -m 750 "$F/bin/marche-backup" /usr/local/bin/marche-backup
install -d -m 755 /opt/marche/releases
# Retrait des unités du Palier 1, remplacées par le modèle marche@ et marche.target
for u in marche-gateway marche-orders marche-payments; do
    systemctl disable --now "$u" 2>/dev/null || true
    rm -f "/etc/systemd/system/$u.service"
done
rm -f /etc/cron.d/marche
install -m 644 "$F"/systemd/* /etc/systemd/system/
systemctl daemon-reload
# Première bascule : l'ancien dossier app/ du Palier 1 devient une version (pour pouvoir y revenir)
if [ ! -L /opt/marche/current ] && [ -d /opt/marche/app ]; then
    v=$(cat /opt/marche/app/VERSION)
    mv /opt/marche/app "/opt/marche/releases/$v"
    mv /opt/marche/venv "/opt/marche/releases/$v/venv"
    ln -sfn "/opt/marche/releases/$v" /opt/marche/current
fi

etape "7. nginx en HTTPS"
install -m 644 "$F/nginx/marche" /etc/nginx/sites-available/marche
nginx -t
systemctl reload nginx
systemctl enable --now marche.target

etape "8. Déployer $ARCHIVE avec marchectl"
v=$(basename "$ARCHIVE" .tar.gz); v=${v#marche-}
if [ ! -d "/opt/marche/releases/$v" ]; then /usr/local/sbin/marchectl deploy "$ARCHIVE"; fi
/usr/local/sbin/marchectl status

etape "9. Planification par timers systemd"
systemctl enable --now marche-backup.timer marche-healthcheck.timer
systemctl start marche-backup.service
systemctl list-timers 'marche*' --no-pager

etape "10. Journald, SSH, fail2ban"
install -d /etc/systemd/journald.conf.d
install -m 644 "$F/journald.conf.d/marche.conf" /etc/systemd/journald.conf.d/marche.conf
systemctl restart systemd-journald
install -m 644 "$F/sshd_config.d/10-marche.conf" /etc/ssh/sshd_config.d/10-marche.conf
sshd -t
systemctl reload ssh
install -m 644 "$F/fail2ban/filter.d/marche-sondes.conf" /etc/fail2ban/filter.d/marche-sondes.conf
install -m 644 "$F/fail2ban/jail.local" /etc/fail2ban/jail.local
fail2ban-client -t >/dev/null
systemctl enable fail2ban && systemctl restart fail2ban

etape "11. Pare-feu : ufw → nftables"
ufw --force disable >/dev/null 2>&1 || true
systemctl disable ufw 2>/dev/null || true
install -m 755 "$F/nftables.conf" /etc/nftables.conf
nft -c -f /etc/nftables.conf
systemctl enable nftables && systemctl restart nftables
# « restart » (et non reload) vide TOUT le pare-feu : l'unité fait « nft flush ruleset » à
# l'arrêt. Les tables de fail2ban disparaissent aussi : on le relance pour qu'il les recrée.
# Ensuite, pour appliquer une modification de /etc/nftables.conf : systemctl reload nftables.
systemctl restart fail2ban
nft list tables

etape "12. auditd (machines virtuelles uniquement)"
if apt-get install -y -q auditd >/dev/null 2>&1 && auditctl -s >/dev/null 2>&1; then
    install -m 640 "$F/audit/marche.rules" /etc/audit/rules.d/marche.rules
    augenrules --load
else
    apt-get purge -y -q auditd >/dev/null 2>&1 || true     # ne pas laisser une unité en échec
    echo "auditd indisponible (conteneur) : étape à réaliser sur une VM"
fi

printf '\n\033[32m✔ Palier 2 appliqué : marchectl status\033[0m\n'
