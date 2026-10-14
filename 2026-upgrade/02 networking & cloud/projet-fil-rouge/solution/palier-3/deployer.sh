#!/usr/bin/env bash
# deployer.sh — déroule la solution du Palier 3 depuis l'hôte (celle du Palier 2, étendue : même dépôt, mêmes couches) : tout se passe sur la console
# (Terraform), l'hôte ne fait que copier le code et les identifiants du « compte » S3.
#   ./solution/palier-3/deployer.sh [fondations|regions|plateforme|trafic|tout]   (défaut : tout)
set -euo pipefail
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
ETAPE=${1:-tout}

# 1. AVANT toute machine : le registre délègue marche.test aux DEUX régions. Délégué après coup,
#    le domaine a déjà été demandé (générateur de trafic, CDN…) : « inexistant » reste en cache
#    chez les résolveurs pendant le TTL négatif du TLD. Et les clients font confiance à notre racine.
docker exec dns-racine registre deleguer marche.test ns.marche.test 198.51.100.253 ns1.marche.test 203.0.113.10 ns2.marche.test 192.0.2.100 >/dev/null
docker exec console cat /root/pki/racine.crt | docker exec -i client sh -c 'cat > /root/racine.crt'
docker cp ../palier-1/machines/client.sh client:/root/client.sh
docker exec client bash /root/client.sh >/dev/null

# 2. les identifiants du compte S3 chez le fournisseur → profil AWS « fournisseur » de la console
# (SEULEMENT cette section : réécrire tout le fichier effaçait le profil « audit » de la conformité —
#  vécu, et c'est la surveillance de conformité elle-même qui l'a signalé)
docker exec s3 cat /etc/s3/compte.env | awk -F= '
    BEGIN {print "[fournisseur]"}
    /AWS_ACCESS_KEY_ID/     {print "aws_access_key_id = " $2}
    /AWS_SECRET_ACCESS_KEY/ {print "aws_secret_access_key = " $2}
    END   {print ""}' \
  | docker exec -i console sh -c 'install -d -m 700 /root/.aws && f=/root/.aws/credentials && touch $f && sed -i "/^\[fournisseur\]/,/^$/d" $f \
        && { cat; cat $f; } > $f.n && mv $f.n $f && chmod 600 $f'

# 3. le code, dans le /root (persistant) de la console
# (l'état voulu de la flotte et la région primaire vivent sur la console : jamais écrasés par le code)
tar -cf - --exclude=.terraform --exclude='*.tfstate*' --exclude=.tmp --exclude='flotte.auto.tfvars.json' --exclude='bascule.auto.tfvars' . \
  | docker exec -i console sh -c 'rm -rf /root/p2.nouveau && mkdir -p /root/p2.nouveau && tar -xf - -C /root/p2.nouveau && mkdir -p /root/p2 && cp -r /root/p2.nouveau/. /root/p2/ && rm -rf /root/p2.nouveau && find /root/p2 -name "*.sh" -exec sed -i "s/\r$//" {} +'

# 4. le premier jour : bucket d'état, clés WireGuard, VPN de la console, init des couches
docker exec console bash /root/p2/bootstrap.sh

# PowerDNS stocke ses zones dans SQLite : UN écrivain à la fois. Plusieurs écritures simultanées
# vers le même serveur échouent (« database is locked », sans attendre) — la couche trafic s'applique
# une ressource à la fois (vécu au premier déploiement depuis zéro : 4 enregistrements par serveur).
parallelisme() { [ "$1" = trafic ] && echo -parallelism=1; true; }
couche() {   # couche <nom> : plan puis apply du plan ENREGISTRÉ (ce qui a été relu est ce qui s'applique)
    # pipefail : sans lui, « | tail -3 » rendait le code de tail — un apply en échec passait pour réussi (vécu)
    docker exec console bash -c "set -o pipefail; cd /root/p2/terraform/$1 && terraform plan -input=false -no-color -out=plan.bin >/tmp/plan-$1.log 2>&1 \
        && terraform apply -input=false -no-color $(parallelisme $1) plan.bin 2>&1 | tail -3" \
        || { docker exec console tail -30 "/tmp/plan-$1.log"; exit 1; }
}
# la landing zone d'abord : les comptes, leurs identités, les garde-fous communs (Palier 3)
case $ETAPE in fondations|tout) echo "== couche fondations"; couche fondations
    # un second passage : le S3 du lab ne garde pas les étiquettes données À LA CRÉATION d'un bucket,
    # le passage suivant les pose (vécu : dérive de la couche au premier déploiement depuis zéro)
    couche fondations >/dev/null
    # la surveillance de conformité (CSPM), sur la console — le poste de la sécurité — avec l'identité
    # d'AUDIT que la landing zone vient de créer (lecture seule), toutes les 5 minutes ; ses résultats
    # sont des métriques, lues par la supervision par le VPN (le node exporter n'écoute QUE sur wg0)
    docker exec console bash -c 'cd /root/p2/terraform/fondations && o=$(terraform output -json audit)
        f=/root/.aws/credentials; sed -i "/^\[audit\]/,/^$/d" $f
        printf "\n[audit]\naws_access_key_id = %s\naws_secret_access_key = %s\n\n" "$(echo "$o" | jq -r .access_key)" "$(echo "$o" | jq -r .secret_key)" >> $f
        install -m 755 /root/p2/cspm.sh /usr/local/sbin/cspm && install -d /var/lib/prometheus/node-exporter
        printf "[Unit]\nDescription=Surveillance de conformité (CSPM)\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/cspm\n" > /etc/systemd/system/cspm.service
        printf "[Unit]\nDescription=CSPM toutes les 5 minutes\n[Timer]\nOnBootSec=30\nOnUnitActiveSec=300\n[Install]\nWantedBy=timers.target\n" > /etc/systemd/system/cspm.timer
        sed -i "s|^ARGS=.*|ARGS=\"--web.listen-address=10.99.0.2:9100 --collector.textfile.directory=/var/lib/prometheus/node-exporter\"|" /etc/default/prometheus-node-exporter
        systemctl daemon-reload && systemctl enable -q --now prometheus-node-exporter cspm.timer && systemctl restart prometheus-node-exporter && systemctl start cspm'
    ;; esac
case $ETAPE in regions|tout) echo "== couche regions"; couche regions ;; esac
# le jeton racine d'OpenBao (créé à son initialisation, sur « coffre ») : pour la couche plateforme.
# (Un humain le récupérerait par SSH, via le VPN : ssh ubuntu@10.0.3.30 sudo cat /var/lib/bao/init.json)
for _ in $(seq 60); do docker exec coffre test -s /var/lib/bao/init.json 2>/dev/null && break; sleep 2; done   # (coffre peut être en train de démarrer)
# … et DESCELLÉ, joignable depuis la console par le VPN : sinon, la couche plateforme expire (vécu,
# quand toutes les machines — coffre compris — venaient d'être remplacées)
for _ in $(seq 90); do docker exec console curl -sf -m 3 --cacert /root/pki/racine.crt --resolve coffre.marche.test:8200:10.0.3.30 https://coffre.marche.test:8200/v1/sys/health >/dev/null 2>&1 && break; sleep 2; done
docker exec coffre cat /var/lib/bao/init.json | docker exec -i console sh -c 'umask 077; cat > /root/cles/bao-init.json'
case $ETAPE in plateforme|tout) echo "== couche plateforme"; couche plateforme
    # un jeton garde les politiques de SA création : les agents authentifiés avant une nouvelle politique
    # (Palier 3 : les identités de service) ne l'auraient qu'à leur prochaine authentification (1 h)
    for m in $(docker ps --filter label=projet=marche --format '{{.Names}} {{.Label "role"}}' | awk '$2 ~ /^(app|db|lb|supervision)$/ {print $1}'); do
        docker exec "$m" systemctl restart bao-agent 2>/dev/null || true
    done ;; esac
case $ETAPE in trafic|tout) echo "== couche trafic"; couche trafic ;; esac

# le rendu (runbook, mesures) : les documents de la solution, sans écraser ceux de l'apprenant
R=../../rendu/palier-3; mkdir -p "$R"
for f in rendu/*.md trou-noir.sh; do [ -e "$f" ] && { [ -e "$R/$(basename "$f")" ] || cp "$f" "$R/"; }; done

echo "Palier 3 déployé ($ETAPE)."
