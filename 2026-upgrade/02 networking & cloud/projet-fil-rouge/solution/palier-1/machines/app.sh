#!/bin/bash
# app1 / app2 — les serveurs d'application (VLAN 20). Le gateway écoute sur le réseau (port 8000)
# pour le répartiteur ; orders et payments restent sur 127.0.0.1.
# usage : app.sh <n° 1|2> <mot de passe de la base>   (+ /root/marche-app.env déposé à côté)
set -euo pipefail
n=${1:?1 ou 2}; MDP=${2:?mot de passe}
bash /root/vlan.sh 20 $((10 + n)) $((10 + n))

cat > /etc/marche/marche.env <<EOF
# le NOM de la base (DNS interne), pas son adresse : on peut la déplacer sans toucher aux applications
DATABASE_URL=postgresql://marche:$MDP@db.marche.test:5432/marche
ORDERS_URL=http://127.0.0.1:8001
PAYMENTS_URL=http://127.0.0.1:8002
LISTEN_HOST=127.0.0.1
EOF
printf 'LISTEN_HOST=0.0.0.0\n' > /etc/marche/gateway.env
# identifiants S3 de l'application (utilisateur IAM « marche-app », moindre privilège)
install -m 640 -o root -g marche /root/marche-app.env /etc/marche/s3.env
chown root:marche /etc/marche/*.env && chmod 640 /etc/marche/*.env

cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet sg {
    chain entree {
        type filter hook input priority filter; policy drop;
        ct state invalid drop
        ct state established,related accept
        iif lo accept
        icmp type { echo-request, destination-unreachable, time-exceeded } accept
        meta l4proto ipv6-icmp accept
        ip saddr 10.0.1.10 tcp dport 8000 accept          # le répartiteur, et lui seul
        ip saddr 10.99.0.0/24 tcp dport 22 accept          # administration (VPN)
    }
}
EOF
nft -c -f /etc/nftables.conf && systemctl enable -q nftables && { systemctl reload nftables 2>/dev/null || systemctl start nftables; }
systemctl enable -q marche.target
systemctl restart marche.target
# Les trois services démarrent en parallèle ; orders doit en plus joindre la base : on attend
# qu'une vraie commande passe de bout en bout (gateway → orders → payments → PostgreSQL).
for _ in $(seq 60); do
    curl -sf -o /dev/null -m 5 -X POST -H 'Content-Type: application/json' \
         -d '{"product_id":1,"quantity":1,"payment_method":"card"}' http://127.0.0.1:8000/api/orders \
      && { echo "app$n prête (commande de test passée jusqu'à la base)"; exit 0; }
    sleep 1
done
echo "app$n : aucune commande ne passe au bout d'une minute (journalctl -u 'marche@*')" >&2
exit 1
