# 🟢 Projet fil rouge Linux — Palier 1 : mettre un serveur en service

> **Cours associé :** [01.md](../01.md) — **Durée indicative :** 8 à 12 h — **Machine :** `web1` (voir [lab/README.md](lab/README.md))

## Mission

La jeune équipe de **Marché** (plateforme de commande en ligne : catalogue, commandes, paiements mobile money et carte, prix en francs CFA) a une application Python qui tourne… sur le portable d'un développeur. Vous recevez un serveur Ubuntu 24.04 vierge, `web1`, et une archive de livraison. À la fin de ce palier, Marché tourne **proprement** sur `web1` : comptes et droits corrects, services supervisés et redémarrés automatiquement, reverse proxy, pare-feu, sauvegardes quotidiennes, accès par clé SSH uniquement. Puis vous menez une **enquête** sur les logs, et vous réparez des pannes.

## L'application

Trois services Python ([app/](app/)) et une base PostgreSQL :

```mermaid
flowchart LR
    C[Clients] -->|:80| N[nginx]
    N -->|127.0.0.1:8000| G[gateway]
    G -->|:8001| O[orders]
    O --> P[(PostgreSQL<br/>base marche)]
    O -->|:8002| PA[payments]
    L[loadgen] -.->|trafic simulé| N
```

| Service | Lancement | Écoute | Variables utiles |
| --- | --- | --- | --- |
| gateway | `python gateway.py` | 127.0.0.1:8000 | `ORDERS_URL` (défaut http://127.0.0.1:8001) |
| orders | `python orders.py` | 127.0.0.1:8001 | **`DATABASE_URL`** (`postgresql://utilisateur:motdepasse@127.0.0.1:5432/base`), `PAYMENTS_URL` |
| payments | `python payments.py` | 127.0.0.1:8002 | — |
| loadgen | `python loadgen.py` | — | `GATEWAY_URL` (défaut http://127.0.0.1), `RPS` |

Chaque service a un `/healthz`, écrit ses logs en JSON sur la sortie standard, et lit `SERVICE_NAME` pour se nommer. Dépendances Python : `requirements.txt`, à installer dans un **environnement virtuel** (`python3 -m venv`). Les endpoints `/admin/…` servent à injecter des pannes : ils ne doivent **jamais** être accessibles de l'extérieur.

## Livraison

Sur votre PC, dans ce dossier :

```bash
./outils/empaqueter.sh 1.0.0        # → livraison/marche-1.0.0.tar.gz (+ son empreinte .sha256)
```

---

## Étapes

Tout le travail se fait **à la main**, avec les commandes du cours. Tenez un journal `NOTES.md` des commandes passées : ce sera votre runbook. Les noms indiqués **en gras** sont imposés (le correcteur les vérifie).

### 1. Prise en main (cours : M0, M1, M16)
- [ ] Nom de machine **`web1`**, fuseau horaire **`Africa/Lome`** (`hostnamectl`, `timedatectl`).
- [ ] Relevez dans `NOTES.md` : distribution et version, noyau, RAM, disque, IP.

### 2. Votre accès (cours : M5, M6, M18)
- [ ] Un compte d'administration **personnel** (pas `ubuntu`), membre de `sudo`, avec un **mot de passe** (il ne sert qu'à `sudo`).
- [ ] Votre clé publique dans son `authorized_keys`, avec les bonnes permissions ; connexion depuis votre PC par `ssh web1` (rebond par le VPS, voir le guide du lab).
- [ ] SSH : **root interdit**, **mots de passe refusés** — par un fichier dans `/etc/ssh/sshd_config.d/`, validé par `sshd -t`, vérifié par `sshd -T`. Gardez une session ouverte pendant la manipulation.

### 3. Comptes et équipe (cours : M6)
- [ ] Groupe **`devs`** avec les utilisateurs **`awa`** et **`koffi`**.
- [ ] Compte de service **`marche`** : compte *système*, **sans shell de connexion**, home **`/opt/marche`**.

### 4. Paquets (cours : M8)
- [ ] Installer ce qu'il faut : Python (environnements virtuels), PostgreSQL, nginx. Rien de superflu.

### 5. Arborescence et permissions (cours : M5)
| Chemin | Propriétaire | Droits | Pourquoi |
| --- | --- | --- | --- |
| `/opt/marche` | root:marche | 750 | le service peut entrer, personne d'autre |
| `/opt/marche/app` | root | lisible, **non modifiable** par `marche` | un service compromis ne doit pas pouvoir réécrire son code |
| `/opt/marche/venv` | root | idem | |
| `/var/lib/marche` | marche:marche | 750 | données du service |
| `/var/log/marche` | root:devs | 750 | l'équipe lit les journaux de supervision |
| `/etc/marche/marche.env` | root:marche | 640 | **le secret** : `DATABASE_URL` avec mot de passe |

### 6. Base de données
- [ ] Rôle PostgreSQL **`marche`** avec mot de passe, base **`marche`** qui lui appartient. `DATABASE_URL` dans `/etc/marche/marche.env`.

### 7. Déploiement (cours : M3, M14)
- [ ] Copier l'archive, vérifier son empreinte (`sha256sum -c`), **inspecter avant d'extraire** (`tar -tzf`), extraire dans `/opt/marche/app`, créer le venv, installer les dépendances.

### 8. Services systemd (cours : M16)
- [ ] Quatre unités **`marche-gateway`**, **`marche-orders`**, **`marche-payments`**, **`marche-loadgen`** : utilisateur `marche`, secret via `EnvironmentFile`, `Restart=on-failure`, dépendances cohérentes (orders après PostgreSQL), **activées au démarrage**.
- [ ] Prouvez le redémarrage automatique : `systemctl kill -s SIGKILL marche-orders`, puis `systemctl status`.

### 9. nginx (cours : M16, M17)
- [ ] Site **`marche`** (reverse proxy vers 127.0.0.1:8000), site par défaut retiré, journal **`/var/log/nginx/marche.access.log`**, **`/admin/` refusé (403)**. `nginx -t` avant tout rechargement.

### 10. Pare-feu (cours : M20)
- [ ] ufw actif, **uniquement 22/tcp et 80/tcp**. Dans le bon ordre.

### 11. Supervision et sauvegarde (cours : M11, M13, M14, M15, M19)
- [ ] **`/usr/local/bin/marche-healthcheck`** : teste les 3 `/healthz` et la page produits via nginx, journalise dans `/var/log/marche/health.log`, sort en **code non nul** si un composant est KO (même si c'est le dernier testé).
- [ ] **`/usr/local/bin/marche-backup`** : `pg_dump` compressé dans **`/var/backups/marche/marche-<horodatage>.sql.gz`**, jamais de fichier à moitié écrit sous un nom valide, **7 sauvegardes au plus**, non lisibles par tous, journal dans `/var/log/marche/backup.log`, code non nul en cas d'échec.
- [ ] **`/etc/cron.d/marche`** : healthcheck **toutes les 5 minutes**, backup **quotidien**, en root, sortie conservée dans un log.
- [ ] **`/etc/logrotate.d/marche`** pour `/var/log/marche/*.log`, validé par `logrotate -d`.
- [ ] Restauration testée : recréez une base `marche_test` à partir d'une sauvegarde et comptez les commandes.

<details><summary>🔎 Indices</summary>

- `set -euo pipefail` et un pipe `pg_dump | gzip` : qui détecte l'échec de `pg_dump` ? Écrivez dans un `.tmp`, renommez en cas de succès.
- Dans `/etc/cron.d/`, une colonne de plus : l'utilisateur.
- `runuser -u postgres -- pg_dump marche` depuis root, sans mot de passe (authentification `peer`).
</details>

---

## Enquête

### A. Journée du 14 septembre (données fournies)

Le fichier [donnees/marche.access.log.gz](donnees/marche.access.log.gz) contient une journée de logs nginx de Marché en production (format *combined*). Copiez-le sur `web1` et répondez **avec les outils du cours** (`zcat`, `grep`, `awk`, `cut`, `sort`, `uniq`, `wc`…), dans un fichier `REPONSES.txt`, une ligne par question, au format **`Qn=valeur`**. Notez aussi chaque commande dans `NOTES.md`.

| # | Question | Format |
| --- | --- | --- |
| Q1 | Combien de requêtes au total ? | nombre |
| Q2 | Combien d'adresses IP distinctes ? | nombre |
| Q3 | Quelle IP a fait le plus de requêtes ? | IP |
| Q4 | Quelle **heure** de la journée compte le plus de réponses 5xx ? | HH |
| Q5 | Un incident a produit des 502 en rafale : heure du **premier** et du **dernier** 502 | `HH:MM:SS-HH:MM:SS` |
| Q6 | Une IP a sondé des chemins sensibles (config, pages d'admin…) : laquelle, à quelle heure, combien de chemins **distincts** ? | `IP;HH;n` |
| Q7 | Volume total servi, en **Mio** (arrondi à l'unité inférieure) | nombre |
| Q8 | Heure de pointe (le plus de requêtes) | HH |
| Q9 | Le modèle de téléphone le plus représenté dans les User-Agent | texte |
| Q10 | Part des `POST /api/orders` refusés pour paiement (402), en %, 1 décimale | nombre |

🪤 La question 6 a un piège : l'IP qui cumule le plus de 404 n'est pas forcément un scanner…

### B. Votre VPS (données réelles, questions ouvertes)

Sur le **VPS lui-même**, en lecture seule (`journalctl`, `grep`, `awk` ; ne modifiez rien) :
1. Combien de tentatives de connexion SSH **échouées** sur les 7 derniers jours ?
2. Les 10 IP sources les plus actives, et les 10 noms d'utilisateur les plus essayés. Qu'en déduisez-vous sur les attaquants ?
3. Une de ces tentatives a-t-elle réussi ? Comment en être **sûr** ?
4. Quelles mesures du cours (M18, M20) réduisent ce bruit ? Lesquelles sont déjà en place sur votre VPS ?

Rédigez la synthèse dans `NOTES.md`. (Pas de correction automatique : c'est votre serveur.)

---

## Pannes

`outils/panne.sh` injecte des pannes réalistes. Copiez-le sur `web1`, puis `sudo ./panne.sh liste 1`.

1. **Entraînement** : injectez chaque panne du Palier 1, une par une. Pour chacune, notez dans `INCIDENTS.md` : **symptôme observé** (côté client), **commandes de diagnostic**, **cause racine**, **correction**, **comment l'éviter**. Corrigez à la main, puis relancez le correcteur.
2. **Manche finale** : `sudo ./panne.sh aveugle 1 3` — trois pannes au hasard, sans indice. Tout remettre en état (correcteur à 100 %) et documenter les trois causes **avant** `sudo ./panne.sh revele`.

⚠️ `panne.sh cle-ssh` vous coupe l'accès SSH par clé : c'est le moment d'utiliser la console de secours (`./lab.sh shell web1`).

---

## Critères d'acceptation

**Automatiques** — sur `web1`, en root :

```bash
sudo ./verifier.sh 1 --reponses REPONSES.txt
```

58 critères : identité, accès SSH, comptes, permissions, services, nginx, pare-feu, cron **réellement exécuté** (attendre 10 minutes après la mise en place), sauvegarde valide et rotation, logrotate, et les 10 réponses de l'enquête.

**Manuels :**

| Critère | ✔ |
| --- | --- |
| Depuis votre PC : `ssh web1` fonctionne par clé ; `ssh -o PubkeyAuthentication=no web1` est refusé | |
| Depuis votre PC (tunnel) : la page produits s'affiche ; `/admin/chaos` renvoie 403 | |
| `sudo` fonctionne pour votre compte (avec son mot de passe) | |
| Après un redémarrage de web1, tout revient seul (services, nginx, pare-feu) | |
| La restauration dans `marche_test` est documentée, avec le nombre de commandes | |
| `INCIDENTS.md` : les 9 pannes d'entraînement + la manche finale, causes racines justes | |
| `NOTES.md` permet à quelqu'un d'autre de refaire le serveur de zéro | |

## Pièges rencontrés en construisant la solution

Tous vécus en testant ce palier :
- Un admin **sans mot de passe** ne peut pas utiliser `sudo`, même avec une clé SSH parfaite.
- `tr -dc … < /dev/urandom | head -c 24` dans un script en `set -euo pipefail` : le script s'arrête **sans message** (SIGPIPE).
- Le journal de cron écrit `CMD ( /usr/local/bin/…)` avec l'espacement de la ligne d'origine : un `grep` trop précis ne trouve rien.
- `ufw insert 1 deny 80/tcp` est **ignoré** s'il existe déjà `allow 80/tcp` : ufw refuse deux règles de même correspondance.

---

Palier validé ? Comparez avec [solution/palier-1](solution/palier-1/), puis passez au [Palier 2](palier-2.md).
