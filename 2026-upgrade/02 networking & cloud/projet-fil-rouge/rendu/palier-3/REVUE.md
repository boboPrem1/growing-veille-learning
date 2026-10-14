# Revue d'architecture — Marché, fin du Palier 3

Revue selon les six piliers du *Well-Architected Framework*. Pour chacun : ce qui est en place **et prouvé** (par `verifier.sh 3` ou une mesure de MESURES.md), puis les risques qui restent, classés. Une revue qui ne trouve rien n'a pas cherché.

Légende des risques : 🔴 élevé (à traiter avant d'accueillir plus de trafic), 🟠 moyen (ce trimestre), 🟢 accepté (documenté, avec sa raison).

## 1. Excellence opérationnelle

**En place.** Tout est code, en quatre couches (fondations, régions, plateforme, trafic), avec un état chez le fournisseur, versionné et verrouillé. Un plan relu est le plan appliqué (`plan -out`). Les déploiements sont bleu/vert avec retour automatique. Il y a un runbook par incident, et chaque procédure a été jouée au moins une fois. La supervision est hors de la région qu'elle surveille. `panne.sh` rejoue les pannes connues.

**Risques.**
- 🟠 Les procédures RTBH et « identité compromise » sont manuelles. Une erreur de frappe dans `trou-noir.sh` peut couper la mauvaise adresse. → Les faire passer par le pipeline (revue, puis application).
- 🟠 Pas d'alerte « une session BGP de moins » ni « BFD down ». Aujourd'hui, la perte du circuit se voit à la latence, pas à une alerte. → Exporter l'état de FRR (`frr_exporter`) et alerter.
- 🟢 Le jeton racine d'OpenBao sert à la couche `plateforme`. Dans le lab, c'est accepté. En production : une authentification de Terraform par rôle, et le jeton racine révoqué après l'initialisation.

## 2. Sécurité

**En place.**
- Zero Trust entre les services : identités de 24 h, mTLS partout (répartiteur → application, supervision → application, application → base), autorisation par identité. Une identité forgée est refusée, et la base refuse le clair et les connexions sans certificat.
- Des comptes de base temporaires et révocables.
- Un IDS/IPS en ligne sur les deux régions, avec un blocage chirurgical (DNS `ANY`) et une exception étroite pour le scanner autorisé.
- RTBH contre les attaques volumétriques.
- Une landing zone : un compte isolé par équipe, un audit en lecture seule, et une conformité continue (8 règles) qui a déjà attrapé deux dérives réelles.

**Risques.**
- 🔴 **Les sidecars ne consultent pas la CRL** : révoquer un certificat ne le bloque pas, seule son expiration (≤ 24 h) le fait. → `ssl_crl` dans nginx et `crl-file` dans HAProxy, alimentés par l'agent OpenBao (`pki-services/crl`). Autre option : raccourcir les identités à 1 h.
- 🟠 Le fournisseur n'accepte que des politiques « Allow ». Aucune SCP « Deny » ne protège les ressources critiques contre un « Allow » accordé plus tard par erreur. Seule la règle CSPM `droits_illimites` le détecte, après coup (5 min). → Chez un vrai fournisseur : des SCP.
- 🟠 Les clés racine du compte (exception `admin-*`) font tourner Terraform. → Un rôle de déploiement borné, et les clés racine au coffre.
- 🟢 Suricata en `bypass` : une panne de l'IPS laisse tout passer. C'est un choix de disponibilité, documenté dans le runbook.

## 3. Fiabilité

**En place.**
- Deux régions. L'anycast bascule en 2,7 s et revient en 1,9 s, sans dépendre des caches DNS.
- Un circuit dédié avec BFD, et un secours VPN épinglé sur Internet (3 commandes en échec à la coupure).
- La réplication de la base entre les régions, avec un PITR prouvé par une restauration d'essai.
- Trois fournisseurs en amont (transit A, transit B, IXP).
- Une résilience en périphérie : le CDN sert sa copie quand l'origine tombe.

**Risques.**
- 🔴 **Une seule base primaire** (Europe) pour les écritures. Si l'Europe disparaît, la bascule est manuelle (`basculer.sh`, RTO mesuré 27 s une fois décidée), et la décision est humaine. → Détecter et proposer la bascule automatiquement ; la décision reste humaine tant que le risque de « deux primaires » n'est pas traité par un arbitre.
- 🟠 Réplication **asynchrone** : RPO = le retard (0,1 s mesuré), pas zéro. Accepté pour des commandes, à revoir pour des paiements.
- 🟠 La supervision est **une seule machine** (à Lomé). Si Lomé disparaît, plus personne ne sonne. → Une supervision légère en Europe, qui surveille celle de Lomé.
- 🟢 Un seul circuit : sa coupure dégrade (tout passe par le VPN à 18 Mbit/s mis en forme), elle ne coupe pas.

## 4. Efficacité des performances

**En place.**
- BBR sur les émetteurs : ×9 sur un chemin qui perd des paquets, et la latence des autres divisée par 4,6 sur un tampon profond.
- Le SD-WAN envoie le volumineux par le tunnel et laisse le circuit à l'interactif.
- La QoS (HTB + fq_codel) sur le tunnel : p95 à 123 ms sous charge.
- Le CDN à Lomé.
- La capacité est mesurée : coude à 20 commandes/s pour 2 instances, conforme à la loi de Little.

**Risques.**
- 🟠 Le coude est fixé par le **pool de connexions × la durée d'une commande** (~1 s, dont les allers-retours vers la base d'Europe). Ajouter des instances ajoute des connexions à la base. → Lire le catalogue sur la réplique locale et rendre le paiement asynchrone (W ÷ 2 double la capacité, sans une machine de plus).
- 🟢 Chaque écriture traverse l'intercontinental (111 ms). C'est inhérent à une primaire unique, et accepté.

## 5. Optimisation des coûts

**En place.**
- Des étiquettes FinOps sur chaque machine, vérifiées en continu.
- Le coût d'une commande est calculé en permanence (0,0887 €), avec trois postes.
- L'autoscaler réduit, en dépubliant avant d'éteindre.
- La landing zone rattache chaque ressource à un compte, donc à une équipe.

**Risques.**
- 🟠 86 % du coût est **fixe** (la plateforme). Au trafic actuel, c'est lui qui fait le prix d'une commande, pas les instances. → Revoir le dimensionnement de la plateforme avant d'optimiser les instances.
- 🟢 Les prix du modèle sont fictifs. La méthode (coût par unité métier) est ce qui compte ; les prix se remplacent par ceux du fournisseur.

## 6. Durabilité

**En place.** L'autoscaler éteint ce qui ne sert pas. BBR n'émet pas plus que le débit du goulot : moins de retransmissions et de paquets perdus pour rien. Le CDN sert près des clients (moins de trafic intercontinental). Le volumineux passe par le lien partagé plutôt que de justifier un circuit plus gros.

**Risques.**
- 🟠 Deux régions complètes tournent en permanence pour un trafic qui tiendrait dans une seule (2 instances suffisent à 20 commandes/s). → Réduire la région de secours à son minimum (la réplique, les répartiteurs, 1 instance) et compter sur l'autoscaler en cas de bascule, en mesurant le RTO que ça coûte.
- 🟢 La mesure de l'énergie n'est pas faite (le lab n'y donne pas accès). En production : les rapports d'empreinte carbone du fournisseur, par compte.

## Ce qu'on fait ensuite, dans l'ordre

1. 🔴 Faire consulter la CRL aux sidecars (sécurité), ou passer les identités à 1 h.
2. 🔴 Automatiser la **détection** de la perte de la primaire, puis proposer la bascule (fiabilité).
3. 🟠 Superviser le routage : sessions BGP, BFD, préfixes annoncés (opérations).
4. 🟠 Lire le catalogue sur la réplique locale (performance **et** coûts : la capacité double sans une machine de plus).
5. 🟠 Mettre une seconde supervision en Europe.
