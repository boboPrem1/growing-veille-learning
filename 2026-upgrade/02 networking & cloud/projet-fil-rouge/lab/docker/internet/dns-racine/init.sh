#!/bin/bash
# Les serveurs DNS « de l'Internet » du lab, sur une seule machine :
#   192.0.2.53  a.racine.test : la RACINE « . » (comme a.root-servers.net)
#   192.0.2.54  ns.tld.test   : le TLD « test. » et son REGISTRE (les délégations des domaines)
#   192.0.2.35  le résolveur récursif du FAI de Lomé (utilisé par client et console)
set -e
ip addr replace 192.0.2.54/24 dev internet
ip addr replace 192.0.2.35/24 dev internet
ip route replace default via 192.0.2.1
printf 'nameserver 127.0.0.1\n' > /etc/resolv.conf 2>/dev/null || true

install -m 644 /lab/named.conf /etc/bind/named.conf
install -m 644 /lab/racine.zone /etc/bind/racine.zone
install -d -o bind -g bind /var/lib/registre
[ -f /var/lib/registre/delegations.db ] || install -o bind -g bind -m 644 /dev/null /var/lib/registre/delegations.db
install -m 755 /lab/registre.sh /usr/local/sbin/registre
/usr/local/sbin/registre --regenerer
systemctl enable --now named

rm -f /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf /etc/unbound/unbound.conf.d/remote-control.conf
install -m 644 /lab/unbound-fai.conf /etc/unbound/unbound.conf.d/fai.conf
install -m 644 /lab/racine.hints /etc/unbound/racine.hints
systemctl enable --now unbound
