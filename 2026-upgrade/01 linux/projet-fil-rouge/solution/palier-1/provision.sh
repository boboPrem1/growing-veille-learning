#!/bin/bash
# Solution de référence — Palier 1 : mise en service de web1.
# C'est la suite des commandes du cahier des charges, dans l'ordre, rendue RELANÇABLE
# (idempotente) : chaque étape vérifie l'état avant d'agir.
#
# Usage (en root sur web1, depuis le dossier qui contient fichiers/) :
#   ADMIN=moi ADMIN_PASSWORD='…' ADMIN_PUBKEY=/root/moi.pub ARCHIVE=/root/marche-1.0.0.tar.gz ./provision.sh
set -euo pipefail

ADMIN=${ADMIN:?variable ADMIN requise : votre nom de compte}
ADMIN_PASSWORD=${ADMIN_PASSWORD:?variable ADMIN_PASSWORD requise : mot de passe pour sudo}
ADMIN_PUBKEY=${ADMIN_PUBKEY:?variable ADMIN_PUBKEY (fichier .pub) requise}
ARCHIVE=${ARCHIVE:?variable ARCHIVE (marche-X.Y.Z.tar.gz) requise}
ICI=$(cd "$(dirname "$0")" && pwd)
F="$ICI/fichiers"

etape() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "À lancer en root" >&2; exit 1; }

etape "1. Identité de la machine"
hostnamectl set-hostname web1
timedatectl set-timezone Africa/Lome

etape "2. Compte d'administration $ADMIN (sudo, clé SSH)"
id -u "$ADMIN" >/dev/null 2>&1 || useradd -m -s /bin/bash "$ADMIN"
usermod -aG sudo "$ADMIN"
# La clé sert à SE CONNECTER (mot de passe SSH désactivé à l'étape 11) ; le mot de passe
# sert uniquement à sudo. Sans lui, sudo est inutilisable.
echo "$ADMIN:$ADMIN_PASSWORD" | chpasswd
install -d -m 700 -o "$ADMIN" -g "$ADMIN" "/home/$ADMIN/.ssh"
install -m 600 -o "$ADMIN" -g "$ADMIN" "$ADMIN_PUBKEY" "/home/$ADMIN/.ssh/authorized_keys"

etape "3. Équipe et compte de service"
getent group devs >/dev/null || groupadd devs
for u in awa koffi; do
    id -u "$u" >/dev/null 2>&1 || useradd -m -s /bin/bash "$u"
    usermod -aG devs "$u"
done
# Compte système : pas de shell de connexion, pas de mot de passe, home = /opt/marche
id -u marche >/dev/null 2>&1 || useradd --system --home-dir /opt/marche --shell /usr/sbin/nologin marche

etape "4. Paquets"
apt-get update -q
apt-get install -y -q python3-venv postgresql nginx curl

etape "5. Arborescence et permissions"
install -d -m 750 -o root   -g marche /opt/marche
install -d -m 750 -o marche -g marche /var/lib/marche
install -d -m 750 -o root   -g devs   /var/log/marche
install -d -m 750 -o root   -g marche /etc/marche
for f in health.log backup.log cron.log; do
    [ -e "/var/log/marche/$f" ] || install -m 640 -o root -g devs /dev/null "/var/log/marche/$f"
done

etape "6. Base de données"
if [ ! -f /etc/marche/marche.env ]; then
    # Pas de « tr < /dev/urandom | head » : tr reçoit SIGPIPE et, avec pipefail, le script
    # s'arrête sans un mot. head lit un nombre fini d'octets : aucun SIGPIPE.
    mdp=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -q -c "CREATE ROLE marche LOGIN PASSWORD '$mdp'"
    runuser -u postgres -- createdb -O marche marche
    install -m 640 -o root -g marche /dev/null /etc/marche/marche.env
    echo "DATABASE_URL=postgresql://marche:$mdp@127.0.0.1:5432/marche" > /etc/marche/marche.env
fi

etape "7. Déploiement de l'application ($ARCHIVE)"
rm -rf /opt/marche/app
install -d -m 755 -o root -g root /opt/marche/app
tar -xzf "$ARCHIVE" -C /opt/marche/app --strip-components=1 --no-same-owner
chmod -R u=rwX,go=rX /opt/marche/app          # code lisible par le service, modifiable par root seul
[ -x /opt/marche/venv/bin/python ] || python3 -m venv /opt/marche/venv
/opt/marche/venv/bin/pip install -q -r /opt/marche/app/requirements.txt
chmod -R go-w /opt/marche/venv

etape "8. Services systemd"
install -m 644 "$F"/systemd/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now marche-payments marche-orders marche-gateway
sleep 3

etape "9. nginx (reverse proxy)"
install -m 644 "$F/nginx/marche" /etc/nginx/sites-available/marche
ln -sfn /etc/nginx/sites-available/marche /etc/nginx/sites-enabled/marche
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
systemctl enable --now marche-loadgen

etape "10. Supervision, sauvegarde, rotation des logs"
install -m 755 "$F/bin/marche-healthcheck" /usr/local/bin/marche-healthcheck
install -m 750 "$F/bin/marche-backup" /usr/local/bin/marche-backup
install -m 644 "$F/cron.d/marche" /etc/cron.d/marche
install -m 644 "$F/logrotate.d/marche" /etc/logrotate.d/marche
# (grep sans -q : il lit TOUTE la sortie. Avec -q, il s'arrête au premier « error », logrotate
#  meurt de SIGPIPE, pipefail rend le pipeline faux… et l'erreur passe inaperçue)
if logrotate -d /etc/logrotate.d/marche 2>&1 | grep -i error >/dev/null; then
    echo "logrotate : configuration invalide" >&2; exit 1
fi
/usr/local/bin/marche-healthcheck
/usr/local/bin/marche-backup

etape "11. SSH : clé uniquement, pas de root"
install -m 644 "$F/sshd_config.d/10-marche.conf" /etc/ssh/sshd_config.d/10-marche.conf
sshd -t
systemctl reload ssh

etape "12. Pare-feu : SSH et HTTP seulement"
ufw allow 22/tcp
ufw allow 80/tcp
ufw status | grep -q "Status: active" || ufw --force enable
ufw status verbose

printf '\n\033[32m✔ web1 est en service : curl http://127.0.0.1/api/products\033[0m\n'
