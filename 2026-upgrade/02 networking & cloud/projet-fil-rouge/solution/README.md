# Solutions de référence

> À ouvrir **après** avoir terminé un palier, correcteur au vert : pour comparer, pas pour recopier. D'autres solutions sont justes ; le correcteur ne juge que le résultat.

| Palier | Contenu | Lancer (depuis l'hôte, lab démarré) |
| --- | --- | --- |
| [palier-1/](palier-1/) | un script par machine (`machines/`), le déployeur, le rendu (plan d'adressage, correspondances cloud) | `./solution/palier-1/deployer.sh` (≈ 1 min) |
| [palier-2/](palier-2/) | trois couches Terraform (`terraform/regions`, `plateforme`, `trafic`) et un module d'instance, les rôles (*user data*, `roles/`), `bootstrap.sh`, et les outils d'exploitation : `pipeline.sh` (bleu/vert), `autoscaler.sh`, `basculer.sh` (perte de région), `restaurer.sh` (PITR) ; le rendu (runbook, mesures) | `./solution/palier-2/deployer.sh` (≈ 2 min ; après `lab.sh passer-palier-2` et `lab.sh up 2`) |
| [palier-3/](palier-3/) | le dépôt du Palier 2, étendu : une quatrième couche `terraform/fondations` (landing zone), FRR/BGP, anycast, BFD, Suricata et SD-WAN dans le rôle `passerelle`, les identités de service (`identite`, `agent_openbao` dans `roles/commun.sh`) et les sidecars mTLS, SLO et FinOps dans `roles/supervision.sh` ; les outils `trou-noir.sh` (RTBH), `cspm.sh` (conformité continue), `capacite.sh` (le coude) ; le rendu (runbook, mesures, revue Well-Architected, un game day réellement joué : « l'IXP disparaît ») | `./solution/palier-3/deployer.sh` (≈ 4 min depuis le Palier 2 ; après `lab.sh up 3`) |

Les scripts sont **relançables** : chacun réécrit ses fichiers et recharge ses services. Les secrets du lab sont tirés au hasard au premier passage (`solution/palier-1/.secrets/`, hors dépôt).

## Ce que la construction de ces solutions a appris

Chacun de ces points a fait échouer une première version de la solution, du lab ou du correcteur.

**Le lab**
- Un réseau Docker `bridge` « internal » jette, dans la VM de Docker, tout paquet dont la destination sort du sous-réseau : aucun conteneur ne peut y servir de routeur. Réseaux `macvlan` isolés.
- Clés d'hôte SSH et certificat « snakeoil » générés pendant `docker build` : identiques sur toutes les machines. Les générer au premier démarrage — sans `make-ssl-cert` (verrou debconf pris au démarrage) et sans ordonner l'unité avant `ssh.socket` (cycle d'ordonnancement, tâche abandonnée au hasard).
- Le délai « océan » appliqué à toute une interface ralentit aussi le routeur du FAI lui-même : filtrer par préfixe source (`tc` `prio` + `u32`).

**Réseau**
- `traceroute` (UDP par défaut) s'arrête à `* * *` devant un pare-feu en `policy drop` : `-I`. Et une seule sonde par saut (`-q1`) donne des résultats instables : le noyau limite le débit de ses ICMP « time exceeded ».
- Publier un AAAA sans ouvrir l'IPv6 partout : l'application (libpq, sans Happy Eyeballs) reste bloquée au démarrage.
- `listen_addresses` avec une adresse IPv6 explicite : adresse encore *tentative* (DAD) au démarrage de PostgreSQL, qui continue sans elle, en silence. `'*'`.
- ACL sans état : les retours (base → applications, et Internet → base pour les mises à jour) se déclarent.
- Trou noir MTU : il ne touche qu'un sens ; `ping -M do` depuis le client passe, et `tracepath` annonce « pmtu 1500 » — il faut mesurer depuis l'émetteur des gros paquets.

**DNS**
- unbound répond NXDOMAIN à tout `.test` sans interroger personne (RFC 6761) : `local-zone: "test." nodefault`.
- `cp -a` d'une zone sauvegardée puis `rndc reload` : BIND juge le fichier inchangé (date de la sauvegarde) et ne recharge rien.
- mawk (l'awk d'Ubuntu) ne connaît pas les intervalles `{8,}` : un script d'incrément de numéro de série échouait en silence.
- Un résolveur garde aussi les échecs en cache (SERVFAIL, NXDOMAIN) : après une délégation réparée, vider aussi ceux-là.

**TLS, HTTP, cache**
- `openssl req -subj` sans `-utf8` : « Marché » encodé deux fois.
- nginx 1.24 (Ubuntu 24.04) : pas de `http2 on;` (1.25.1) ; pas de `/var/cache/nginx` créé par le paquet.
- `httpx` (Python) n'utilise pas le magasin de certificats du système (certifi) : `curl` accepte le site, le générateur de trafic le refuse.
- Mesurer un CDN avec `time_total` inclut la résolution DNS — qui, TTL expiré, retraverse l'océan : mesurer `time_total − time_namelookup`.

**Correcteurs et pannes**
- Une annonce ARP gratuite isolée ne suffit pas à simuler un conflit d'adresse : la vraie machine reprend la main à la requête ARP suivante.
- Une panne qui prend « le premier fichier de zone » de `named.conf` casse la vue **interne**, pas l'externe.

**Palier 2** (les pièges de la solution sont dans [palier-2.md](../palier-2.md#pièges-rencontrés-en-construisant-la-solution) ; ici, ceux du lab et du correcteur)
- Docker 29 donne une adresse MAC **aléatoire** à chaque conteneur : toute instance remplacée laisse ses voisins écrire à l'ancienne. Toute la solution s'annonce par ARP gratuit au démarrage.
- Terraform suit l'**identifiant** de l'image : reconstruire l'image du lab remplace toutes les instances au `apply` suivant (voulu : c'est l'immuabilité).
- `docker pause` simule la perte d'une région mieux que `docker stop` : plus un paquet, plus une écriture, et Terraform, qui voit encore les conteneurs, peut les remplacer — y compris gelés (`docker rm -f`).
- Le test de verrou du correcteur retirait, après coup, **n'importe quel** verrou — y compris le verrou orphelin d'une panne injectée, qu'il « réparait » ainsi. Il ne touche plus qu'au sien, et signale un verrou déjà posé.
- Un critère « commande créée = 201 » échouait au hasard : le service de paiement refuse une commande sur vingt (402, une réponse **métier**, la commande est enregistrée).
- L'hôte n'a pas forcément `jq` : le correcteur l'exécute sur la console.
- Mesurer la supervision juste après une mise à l'échelle tombait dans la fenêtre de rafraîchissement de sa découverte DNS (15 s) : attendre la convergence avant de conclure.
- Réduire un groupe **sans** dépublier d'abord : 1 requête perdue sur 234 (déjà partie vers l'instance qui s'éteint). Le correcteur réduit comme il le demande : dépublier, attendre, éteindre.
- La restauration d'essai « à T−2 min », lancée 2 minutes après un tout premier déploiement, visait un instant **antérieur à la première sauvegarde complète** : 0 commande restaurée (vécu à la validation finale depuis zéro). Aucune restauration ne remonte avant la première sauvegarde. Le correcteur attend désormais qu'elle ait plus de 2 minutes.

**Palier 3** (les pièges de la solution sont dans [palier-3.md](../palier-3.md#pièges-rencontrés-en-construisant-la-solution) ; ici, ceux du lab et du correcteur)
- Recréer le `client` (pour le déplacer chez TogoNet) effaçait son magasin de certificats : le lab le **branche** sur le nouveau réseau (`docker network connect`) au lieu de le recréer, et change seulement sa route par défaut.
- Un conteneur qui sert de circuit dédié ne connaît que ses deux réseaux : il jetait tout le reste. Routage **par interface d'entrée** (ce qui entre d'un côté ressort de l'autre).
- Un fournisseur qui filtre les préfixes reçus cache ce qu'on lui envoie : `soft-reconfiguration inbound` chez les fournisseurs du lab, pour que le correcteur lise ce que **vous** annoncez (`received-routes`), fuites comprises.
- Le routeur du circuit ne répond pas aux traceroutes (il ne connaît pas vos VPC) : le correcteur lit le chemin sur la passerelle (`ip route get`).
- Le correcteur **rejoue le Palier 2** : quatre critères changent volontairement (le chemin inter-régions passe par le circuit, `www` devient anycast, le répartiteur a besoin du coffre). Le rejeu a trouvé un vrai défaut : le secours DNS de Lomé mort depuis l'arrivée du circuit.
- Un compteur `grep -c … || echo 0` rend « 0 » **deux fois** quand rien ne correspond (grep écrit 0, puis échoue) : la comparaison qui suit plante. `grep -c …; true`.
- Tester les pannes pendant que le correcteur tourne fausse les deux ; et modifier un script bash **pendant** qu'il s'exécute peut le corrompre (bash lit la suite du fichier au fil de l'eau).
