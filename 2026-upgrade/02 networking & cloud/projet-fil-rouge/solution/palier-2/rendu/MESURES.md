# Mesures — RTO et RPO de Marché (Palier 2)

**Méthode.** Sur `client` (Lomé), une sonde passe une commande toutes les 0,2 s via `https://www.marche.test` et journalise l'heure, le code HTTP et l'identifiant de la commande. RTO = durée pendant laquelle la sonde échoue. RPO = nombre de commandes **confirmées (201)** par la sonde et **absentes** de la base après l'incident.

| Incident | RTO mesuré | RPO mesuré | Remarques |
| --- | --- | --- | --- |
| Restauration à un instant (PITR) | **34 à 38 s** (arrêt des applications → 4 applications rétablies) | tout ce qui suit l'instant choisi (par construction) ; la précision est la seconde | 3 accidents rejoués : `DELETE`, `DROP TABLE`, `UPDATE` massif |
| Perte de la région Europe | **27 s** de coupure (dont 5 s de « détection » simulée ; promotion 15 s) | **0** commande confirmée perdue | réplication asynchrone à 0,12 s de retard : le RPO théorique est ce retard |
| Rétablissement de l'Europe | **0** échec | 0 | l'ancienne primaire est écartée avant le dégel |
| Retour planifié en Europe | **16 s** | **0** (prouvé par comparaison de LSN) | remplacement des deux passerelles |
| Panne du répartiteur de Lomé | **22 s** vers l'Europe, **29 s** pour revenir | 0 | GSLB `ifportup`, TTL 30 s |

## Avant / après les correctifs

| Perte de la région Europe | RTO | RPO |
| --- | --- | --- |
| Première mesure | 140 s | 0 |
| + bornes TCP côté application | 51 s | 0 |
| + ARP gratuit au démarrage des instances | **27 s** | 0 |

| Retour planifié | RTO | RPO |
| --- | --- | --- |
| Sans vérification du LSN | 34 s | **129 commandes perdues** |
| Avec vérification du LSN | **16 s** | **0** |

## Déploiements, mise à l'échelle, qualité de service

| Opération | Mesure | Erreurs vues par un client |
| --- | --- | --- |
| Déploiement bleu/vert de la version 1.1.0, deux régions (`pipeline.sh`) | 202 s au total (Europe puis Lomé) ; p95 observé 368 ms (Europe, vu de Lomé), 20 ms (Lomé) | **0** sur 164 commandes |
| Version 1.2.0 « fonctionnelle mais lente » (+800 ms) | tests de fumée **passés** ; observation : p95 = 1 037 ms > 500 ms → **retour automatique** ; p95 après retour : 18 ms | aucune perte ; ~60 s de lenteur |
| Bascule de la couche `trafic` (plan + apply) | 6 s (contre ~30 s quand le DNS était dans la couche `plateforme`) | — |
| Mise à l'échelle : `RPS` 2 → 20 à Lomé (`autoscaler.sh`, cible 4 req/s/instance) | 22 req/s mesurés → 6 instances en une évaluation ; charge ensuite ≈ 4 req/s par instance (3,55 à 4,37) ; répartiteur **non remplacé** | **0** sur 525 commandes (agrandir puis réduire) |
| Réduction | 3 évaluations d'affilée avant de retirer **une** instance ; dépubliée 15 s avant d'être éteinte | **0** (sans dépublier d'abord : 1 requête perdue sur 234 — une requête déjà partie vers l'instance qui s'éteint) |
| Panne du répartiteur de Lomé | GSLB (serveur) : 3 s pour basculer, 6 s pour revenir ; client : jusqu'au TTL de 30 s de plus | — |

**Le lien intercontinental** (câble : 20 Mbit/s par sens, tampon de 1 200 paquets chez l'opérateur). Poignée de main TCP d'une application de Lomé vers la base d'Europe, pendant 8 téléchargements en parallèle Europe → Lomé :

| Configuration de `wg0` | Au repos (p50 / p95) | Sous charge (p50 / p95) |
| --- | --- | --- |
| rien (la file se forme chez l'opérateur) | 122 / 122 ms | **514 / 753 ms** |
| HTB à 18 Mbit/s + FIFO | 122 / 339 ms | **706 / 1 032 ms** (pire : la file a changé de place) |
| HTB à 18 Mbit/s + **fq_codel** | 122 / 122 ms | **122 / 123 ms** |

## Limites connues

- **Le coffre (OpenBao) n'existe qu'en Europe.** Pendant la perte de l'Europe, les comptes temporaires de Lomé ne sont plus renouvelés : ils restent valides jusqu'à leur expiration (au plus 1 h). Au-delà, Lomé ne peut plus écrire. En production : réplication du coffre (Vault Enterprise DR, ou un coffre restauré dans l'autre région à partir d'instantanés Raft).
- **Le stockage objet (`marche-statique`) n'existe qu'en Europe** : sans l'Europe, les images ne sont plus servies (sauf depuis le cache du CDN). En production : réplication inter-régions des buckets.
- **Les sauvegardes s'arrêtent pendant la bascule** : la base promue doit lire leur secret dans le coffre, qui est en Europe.
- La réplication est **asynchrone** : une transaction confirmée dans les ~0,1 s précédant une perte **brutale** peut être perdue. `synchronous_commit = remote_apply` supprimerait ce risque, au prix de 120 ms par écriture (l'aller-retour Europe ↔ Lomé).
