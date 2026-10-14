# 🧪 Le lab du projet fil rouge

Le projet se fait sur des **machines de lab jetables**, jamais sur une machine dont vous vous servez. Deux façons de les obtenir, avec **les mêmes noms et les mêmes adresses IP** : tout le projet fonctionne à l'identique dans les deux.

| Machine | IP | Palier | Rôle |
| --- | --- | --- | --- |
| `web1` | 10.10.10.21 | 1, 2, 3 | Serveur de l'application Marché |
| `web2` | 10.10.10.22 | 3 | Second serveur applicatif |
| `lb1`, `lb2` | 10.10.10.11, .12 | 3 | Répartiteurs de charge (HAProxy + keepalived) |
| `db1` | 10.10.10.31 | 3 | PostgreSQL |
| `bak1` | 10.10.10.41 | 3 | Serveur de sauvegarde (« hors site », via WireGuard) |
| *IP virtuelle* | 10.10.10.100 | 3 | Adresse publique du service, portée par lb1 ou lb2 |
| `ctl` | 10.10.10.5 | 3 | Poste de contrôle : Ansible, correcteur, injecteur de pannes |

---

## Option A — Sur votre VPS, avec LXD (recommandé)

Des **conteneurs système** LXD : de vrais Ubuntu 24.04 avec systemd, isolés sur un réseau privé du VPS. L'hôte n'est pas modifié (ni pare-feu, ni SSH, ni services).

### 1. Préparer (une fois, sur le VPS)

```bash
# Depuis votre PC : copier le dossier lab/lxd sur le VPS
scp -r lab/lxd vps:~/marche-lab
ssh vps
cd ~/marche-lab && chmod +x lab.sh

snap list lxd || sudo snap install lxd       # LXD est souvent déjà là sur Ubuntu Server
sudo usermod -aG lxd "$USER" && exit          # se reconnecter pour que le groupe s'applique (cours 01, M6)
ssh vps
cd ~/marche-lab && ./lab.sh init
```

`./lab.sh init` crée le réseau `marchenet` (10.10.10.0/24, NAT) et le profil `marche` (1 Go de RAM, 1 CPU par machine), puis vous dit :
- si **ufw** est actif sur l'hôte et risque de bloquer le DHCP/NAT du lab — il affiche les règles à ajouter, **à vous de décider** ;
- si **KVM** est disponible (`/dev/kvm`). Sans KVM : conteneurs uniquement, ce qui suffit pour presque tout (voir plus bas).

### 2. Créer les machines

```bash
./lab.sh up 1            # Paliers 1 et 2 : web1
./lab.sh up 3            # Palier 3 : les 6 machines + ctl
./lab.sh autoriser ~/cle-ctl.pub   # Palier 3 : la clé de ctl, déposée dans ~ubuntu/.ssh de chaque machine
./lab.sh etat
./lab.sh shell web1      # shell root dans web1 (votre « console de secours », hors SSH)
```

### 3. Se connecter depuis votre PC (rebond SSH par le VPS)

Les machines n'ont pas d'IP publique : on passe **par** le VPS avec `ProxyJump`. Après avoir créé votre compte et déposé votre clé dans web1 (étape 2 du Palier 1) :

```
# ~/.ssh/config sur votre PC  (./lab.sh ssh-config génère ce bloc)
Host vps
    HostName <IP ou nom de votre VPS>
    User <votre utilisateur sur le VPS>

Host web1
    HostName 10.10.10.21
    User <votre compte de lab>
    ProxyJump vps
```

```bash
ssh web1                                  # rebond transparent par le VPS
scp livraison/marche-1.0.0.tar.gz web1:   # copie de fichiers, même chemin
```

### 4. Voir le site depuis votre navigateur (tunnel SSH)

```bash
ssh -N -L 8080:10.10.10.21:80 vps          # laisser tourner, puis ouvrir http://localhost:8080
```

Le port 80 de web1 n'est **jamais** exposé sur Internet : le tunnel chiffré passe par votre connexion SSH au VPS. (Au Palier 3, visez l'IP virtuelle `10.10.10.100` à la place.)

### 5. Limites des conteneurs LXD (et solutions)

| Besoin | Conteneur LXD | Solution |
| --- | --- | --- |
| systemd, services, cron, SSH, nginx, PostgreSQL, ufw, nftables, fail2ban, HAProxy, keepalived | ✅ | — |
| WireGuard (Palier 3) | ✅ si le module est chargé sur l'hôte | `sudo modprobe wireguard` sur le VPS (seule action sur l'hôte, sans effet sur ses services) |
| Disque supplémentaire, LVM (Palier 2) | ❌ | `./lab.sh up 1 --vm` (VM KVM) puis `./lab.sh ajouter-disque web1 disque2 2GiB` ; sans KVM : lab local (option B) pour cette étape |
| auditd (Palier 2) | ❌ (audit noyau partagé) | VM KVM, ou lab local non plus : étape notée « sur VM seulement » |
| eBPF / bpftrace (Palier 3) | ❌ | Sur une VM, ou sur le VPS lui-même en **lecture seule** (bpftrace n'altère rien) |

Commandes utiles : `./lab.sh detruire web2` puis `./lab.sh recreer web2` (plan de reprise, Palier 3 : la clé enregistrée par `autoriser` est réinjectée), `./lab.sh down` (tout arrêter).

Au Palier 3, le projet Ansible doit être sur `ctl` : `git clone` de votre dépôt dans `ctl`, ou `lxc file push -r ansible/ ctl/home/<vous>/`.

---

## Option B — En local, avec Docker (sans VPS, ou en complément)

Des conteneurs Docker **privilégiés** exécutant systemd : chaque conteneur se comporte comme un serveur Ubuntu 24.04. Testé avec Docker Desktop (Windows 11 / WSL2) et Docker Engine sous Linux.

```bash
cd lab/docker
./lab.sh up 1                       # construit l'image et démarre web1
./lab.sh shell web1                 # shell root
./lab.sh ajouter-disque web1 disque2 2G    # « disque » secondaire → /dev/disk/lab/disque2 (Palier 2)
./lab.sh copier ../../livraison/marche-1.0.0.tar.gz web1:/root/
./lab.sh up 3                       # Palier 3 : les 6 machines + ctl (le dossier du projet y est monté dans /srv/projet)
./lab.sh autoriser cle-ctl.pub      # la clé publique de VOTRE compte sur ctl → ~ubuntu/.ssh de chaque machine
```

| Accès | Commande |
| --- | --- |
| SSH vers web1 | `ssh -p 2221 moi@127.0.0.1` (web2 : 2222, lb1 : 2211, lb2 : 2212, db1 : 2231, bak1 : 2241, ctl : 2205) |
| Site de web1 | http://127.0.0.1:8080 |

Particularités du lab local, à connaître pour ne pas perdre de temps :
- 🪤 `/etc/hosts` et `/etc/resolv.conf` sont des **montages** gérés par Docker : `sed -i` échoue (`Device or resource busy`), car il remplace le fichier au lieu de le réécrire. Éditez-les avec `nano`, ou réécrivez-les en place.
- LVM fonctionne sur les disques du lab (fichiers loop), mais sans udev : le lab règle `udev_sync = 0` dans `/etc/lvm/lvm.conf` au démarrage.
- `auditd` ne fonctionne pas (audit noyau partagé avec l'hôte) : sautez ce point, ou faites-le sur une VM.
- 🪤 **Le noyau est celui de Docker, partagé par tous les conteneurs.** Des volumes LVM restent actifs d'un démarrage du conteneur à l'autre (le lab recrée leurs nœuds avec `vgmknodes`), et `./lab.sh detruire` les désactive avant de supprimer la machine. Le noyau WSL2 de Docker Desktop n'a pas `dm-snapshot` : pas d'instantanés LVM ici (faites-les sur une VM).
- 🪤 **`systemctl restart nftables`** (qui fait `nft flush ruleset`) efface aussi les règles NAT que Docker pose dans le conteneur pour son DNS (127.0.0.11) : plus aucune résolution de noms jusqu'au redémarrage de la machine (`docker restart web1`). Utilisez `systemctl reload nftables` — c'est aussi la bonne pratique en production (voir le cours 02, M13).
- 🪤 **Palier 3 : `ansible.cfg` ignoré dans `/srv/projet`.** Le dossier monté depuis Windows apparaît accessible en écriture à tous, et Ansible refuse alors d'y lire `ansible.cfg`. `export ANSIBLE_CONFIG=$PWD/ansible.cfg`, ou travaillez sur une copie dans votre home.
- 🪤 **Clés d'hôte SSH** : générées pendant la construction de l'image, elles seraient **identiques sur toutes les machines** (et une machine recréée garderait la même clé). L'image les supprime et chaque machine génère les siennes à son premier démarrage (`lab-cles-ssh.service`), comme cloud-init chez un hébergeur. Première version de cette unité : ordonnée avant `ssh.socket`, elle créait un cycle que systemd cassait en abandonnant une tâche au hasard — une machine sur trois démarrait sans clés (`systemd-analyze verify` le montre).
- ⚠️ Ne poussez jamais de `sysctl` `kernel.*` depuis un conteneur privilégié : c'est le noyau de l'hôte (la VM de Docker) que vous modifieriez. Les réglages `net.*` sont propres au conteneur.
- `privileged: true` donne beaucoup de pouvoir aux conteneurs : ce lab est fait pour votre poste, pas pour un serveur partagé.
