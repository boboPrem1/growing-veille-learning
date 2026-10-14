# Solutions de référence

> À ouvrir **après** avoir terminé un palier, correcteur au vert : pour comparer, pas pour recopier. Il existe d'autres solutions justes ; le correcteur, lui, ne juge que le résultat.

| Palier | Contenu | Lancer |
| --- | --- | --- |
| [palier-1/](palier-1/) | `provision.sh` + `fichiers/` (unités, site nginx, scripts, cron, logrotate, SSH) | sur web1 vierge, en root : `ADMIN=moi ADMIN_PASSWORD=… ADMIN_PUBKEY=/root/moi.pub ARCHIVE=/root/marche-1.0.0.tar.gz ./provision.sh` |
| [palier-2/](palier-2/) | `provision.sh` + `fichiers/` (`marchectl`, unité modèle durcie, timers, nftables, fail2ban + filtre maison, TLS…) | sur web1 au Palier 1 : `DISQUE=/dev/disk/lab/disque2 ADMIN=moi DEPLOY_PUBKEY=… ARCHIVE=…/marche-1.1.0.tar.gz ./provision.sh` |
| [palier-3/ansible/](palier-3/ansible/) | inventaire, coffre (en clair ici pour être lu), 9 rôles, `site.yml` | sur ctl, copié dans votre home (pas de dossier accessible en écriture à tous) : `ansible-vault encrypt group_vars/all/vault.yml`, puis `ansible-playbook site.yml` |

Les scripts de provisionnement sont **relançables** (chaque étape vérifie l'état avant d'agir) : c'est la marche qui mène à Ansible.

## Ce que la construction de ces solutions a appris

Chacun de ces points a fait échouer une première version de la solution ou du correcteur. Plusieurs contredisent ce qu'on lit couramment.

**Bash**
- `tr -dc … </dev/urandom | head -c 24` sous `pipefail` : le script s'arrête sans message (SIGPIPE, code 141).
- `tar -tzf | head -1` échouait une fois sur quelques-unes ; `if tar -tzf | grep -q '\.\./'` pouvait être **faux quand grep avait trouvé**. Même famille : `nft list ruleset | grep -q` dans le correcteur, `yes oui | commande`, `logrotate -d | grep -qi error`.
- Sans `set -E`, le `trap ERR` ne se déclenche pas dans les fonctions.
- `$USER` n'existe pas sous `docker exec` (ni toujours sous cron/systemd) : `set -u` arrête le script.
- Remplacer un script **pendant** qu'il s'exécute est dangereux : bash le lit au fil de l'eau.

**Système**
- Un administrateur sans mot de passe ne peut pas utiliser `sudo`, même avec une clé SSH parfaite.
- sudo 1.9 (Ubuntu 22.04/24.04) **ignore** une ligne invalide de `sudoers.d` au lieu de tout bloquer — sauf pour la règle cassée. Sur sudo 1.8, tout est bloqué.
- `postgresql.service` n'est qu'une enveloppe : l'arrêter ne garantit pas que l'instance est arrêtée.
- `systemctl restart nftables` exécute `nft flush ruleset` : les bannissements de fail2ban disparaissent (dans Docker, le DNS du conteneur aussi). `reload`.
- `ufw insert 1 deny 80/tcp` est ignoré en silence s'il existe `allow 80/tcp`.
- `server_tokens off;` ne vaut que dans le bloc `server` où il est écrit.
- Le client OpenSSL d'Ubuntu 24.04 refuse TLS 1.1 de lui-même : un test « TLS 1.1 refusé » sans `@SECLEVEL=0` ne teste pas le serveur.
- `openssl s_client` n'a pas de délai d'attente : sur un port en DROP, il attend ~2 minutes. `timeout 5`.
- Le filtre fail2ban `nginx-botsearch` ne reconnaît que 9 des 42 sondes du journal du 14 septembre.
- `systemd-delta` ne signale pas les drop-in d'une **instance** d'unité modèle (`marche@gateway.service.d/`) : `systemctl show -p DropInPaths` le fait.

**Stockage et sauvegardes**
- `lvextend` sans `-r` : le volume grandit, pas le système de fichiers.
- Lab Docker : des clés d'hôte SSH générées pendant `docker build` sont identiques sur toutes les machines ; les générer au premier démarrage, sans ordonner l'unité avant `ssh.socket` (cycle d'ordonnancement, tâche abandonnée au hasard).
- Lab Docker : sans udev, LVM ne crée pas ses nœuds ; des LV restés actifs dans le noyau partagé n'ont plus de nœuds au redémarrage du conteneur (`vgmknodes`) ; les montages `fstab` attendent un périphérique que systemd ne suit pas.
- `pg_dump | restic backup --stdin` enregistre un instantané tronqué si `pg_dump` meurt.
- Une base reconstruite, sauvegardée avant sa restauration, devient « le dernier instantané ». Et elle n'est pas vide (le trafic y écrit déjà) : un garde-fou « base vide » a laissé passer 22 commandes contre 73 000. Comparer au volume du dernier instantané (étiquette restic).

**Ansible**
- `password_hash` sans sel fixe : `changed` à chaque exécution.
- `/etc/hosts` dans un conteneur Docker est un montage : `unsafe_writes: true`.
- `ansible.cfg` ignoré dans un dossier accessible en écriture à tous.
- `ansible-vault encrypt --vault-password-file …` quand `ansible.cfg` déclare déjà `vault_password_file` : « vault-ids default,default are available ».
- Un nom de tâche qui contient « : » doit être entre guillemets (YAML).
- `--limit` exclut le `localhost` implicite : le play de la PKI saute sans prévenir (`-l 'localhost:…'`).
- `--limit` sur une machine dont le rôle lit des faits d'une autre (clés WireGuard) : il faut les deux.

**Haute disponibilité**
- keepalived avec `script "/usr/bin/pidof haproxy"` : sur Ubuntu 24.04, `pidof` est un lien vers `killall5` ; avec `enable_script_security`, keepalived lance la cible et le contrôle échoue toujours — les deux répartiteurs en `FAULT`, aucune IP virtuelle.

**Réseau et base**
- Une ligne retirée de `pg_hba.conf` ne coupe pas les connexions déjà ouvertes (pool) : un test de port ne voit rien, il faut une nouvelle connexion authentifiée.
- `vrrp_track_process` ne fonctionne pas en conteneur ; `vrrp_script` à `interval 1`, `fall 1` : 1 à 2 requêtes perdues sur 60 (13 à `interval 2`, `fall 2`).

**Correcteurs**
- Un critère négatif (« aucun X ») passe sur une machine vierge : il faut d'abord exiger que l'objet existe.
- Le correcteur perturbe ce qu'il mesure (il tue un service, déploie une version cassée) : les mesures de santé se font **avant** toute intervention, et un healthcheck qui échoue pendant ces tests a raison.
