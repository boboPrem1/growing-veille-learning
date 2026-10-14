#!/bin/bash
# Rattache chaque image de /var/lib/lab/disques/ à un périphérique loop et publie un lien
# stable /dev/disk/lab/<nom> (l'équivalent d'un /dev/sdb sur une vraie machine).
set -euo pipefail
mkdir -p /var/lib/lab/disques /dev/disk/lab
for img in /var/lib/lab/disques/*.img; do
    [ -e "$img" ] || continue
    nom=$(basename "$img" .img)
    dev=$(losetup -j "$img" | cut -d: -f1)
    [ -n "$dev" ] || dev=$(losetup -f --show "$img")
    ln -sfn "$dev" "/dev/disk/lab/$nom"
    echo "$nom -> $dev"
done
# Sans udev (conteneur), LVM doit créer lui-même les nœuds /dev : on le lui dit.
if [ -f /etc/lvm/lvm.conf ] && ! grep -q "^\s*udev_sync = 0" /etc/lvm/lvm.conf; then
    sed -i 's/^\s*# udev_sync = 1/\tudev_sync = 0/; s/^\s*# udev_rules = 1/\tudev_rules = 0/' /etc/lvm/lvm.conf
fi
command -v vgchange >/dev/null && vgchange -ay >/dev/null 2>&1 || true
# Le noyau est celui de Docker, partagé : des LV déjà actifs au démarrage précédent le sont
# encore, et vgchange ne recrée pas leurs nœuds dans le /dev tout neuf du conteneur.
command -v vgmknodes >/dev/null && vgmknodes >/dev/null 2>&1 || true
# systemd ne suit pas les périphériques quand il tourne dans un conteneur : les montages
# de /etc/fstab portant sur des disques attendraient indéfiniment. On les monte ici, avant
# local-fs.target ; systemd constate ensuite qu'ils sont déjà montés. (Lab Docker uniquement.)
mount -a 2>&1 | sed 's/^/lab-disques: /' || true
