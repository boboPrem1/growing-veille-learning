#!/bin/sh
# Clés propres à cette machine, au premier démarrage (voir lab-cles.service).
set -e
ssh-keygen -A
# Le certificat « snakeoil » (PostgreSQL l'utilise par défaut). Pas make-ssl-cert : il passe par
# debconf, dont le verrou est souvent pris au démarrage — l'unité échouait une fois sur deux.
openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 -subj "/CN=$(hostname)" \
    -keyout /etc/ssl/private/ssl-cert-snakeoil.key -out /etc/ssl/certs/ssl-cert-snakeoil.pem 2>/dev/null
chown root:ssl-cert /etc/ssl/private/ssl-cert-snakeoil.key
chmod 640 /etc/ssl/private/ssl-cert-snakeoil.key
touch /var/lib/lab-cles-faites
