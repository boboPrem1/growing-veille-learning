# Runbook — Marché, Palier 2

Trois procédures d'incident, dans l'ordre où on les exécute. Chacune est scriptée (`solution/palier-2/`), mais doit se comprendre sans le script : c'est ce document qu'on lit à 3 h du matin.

## 1. Restaurer la base à un instant (erreur humaine : `DELETE` sans `WHERE`, `DROP TABLE`…)

> La réplique ne sert à rien ici : elle a rejoué l'erreur en 0,1 s. Seules les **sauvegardes + WAL archivés** remontent le temps.

Script : `./solution/palier-2/restaurer.sh 'AAAA-MM-JJ HH:MM:SS+00'` (un instant **avant** l'erreur).

| # | Action | Pourquoi |
| --- | --- | --- |
| 1 | Arrêter les applications (`marche.target`, `bao-agent`) | Elles écriraient pendant la restauration |
| 2 | `systemctl stop postgresql@16-main` puis `pgbackrest --stanza=marche --delta --type=time --target=… --target-action=promote restore`, puis démarrer | `postgresql` n'est qu'une coquille ; la base rejoue les WAL jusqu'à l'instant, puis est promue (nouvelle *timeline*) |
| 3 | `ALTER SYSTEM RESET recovery_target_time, recovery_target_action, restore_command` | pgBackRest laisse la cible dans `postgresql.auto.conf` ; `pg_basebackup` la recopierait sur la réplique, qui se promouvrait à son tour : **deux primaires** |
| 4 | Relancer le rôle de la base (recrée le slot de réplication) | Une restauration ne ramène pas les slots |
| 5 | Reconstruire la réplique (supprimer `standby.signal`, relancer son rôle → `pg_basebackup`) | Elle a suivi l'erreur et ne peut pas rejoindre la nouvelle timeline seule |
| 6 | `bao lease revoke -prefix base/creds/app` | Base et coffre ne sont plus d'accord : les comptes créés après l'instant ont disparu, ceux supprimés après sont **revenus** |
| 7 | Redémarrer les agents OpenBao | Ils redemandent des comptes, puis redémarrent les applications |

La révocation doit **réussir même si le compte n'existe plus** (`DO … IF EXISTS`), sinon le bail reste bloqué pour toujours, et elle doit **couper les sessions** (`pg_terminate_backend`) : `DROP ROLE` ne ferme pas les connexions déjà ouvertes.

## 2. Perdre une région (Europe) et basculer

Script : `./solution/palier-2/basculer.sh sinistre|basculer|retablir|revenir|etat`. La région primaire est une **variable Terraform** (`region_primaire`), rangée dans `terraform/regions/bascule.auto.tfvars` : un déploiement ultérieur ne rebascule pas en douce.

**Ce qui tient tout seul** : le GSLB (PowerDNS `ifportup`) envoie les clients à Lomé ; ns2 sert les deux vues ; le résolveur de Lomé interroge ns2 d'abord. **Le site reste lisible.** Les écritures échouent : la primaire est en Europe.

**Basculer** : `terraform apply -var region_primaire=lome -target='module.machine["db-lome"]' -target='module.machine["passerelle-lome"]'`.
- `-target` : réservé aux urgences. Planifier des machines d'une région injoignable n'a aucun sens.
- db-lome est promue ; le résolveur de Lomé fait pointer `db.marche.test` vers `10.1.0.70`.
- Les applications gardent leurs comptes temporaires (ils existent dans la réplique : les rôles sont répliqués) jusqu'à leur expiration (1 h) — **le coffre, lui, est resté en Europe** : c'est la limite de cette architecture (voir MESURES.md).

## 3. Rétablir, puis revenir

**Rétablir — dans CET ordre** :
1. `terraform apply` (complet, `region_primaire=lome`) **pendant que l'Europe est encore gelée** : l'ancienne primaire est remplacée, et reconstruite en réplique de Lomé. Ses écritures d'après la coupure (qu'aucun client n'a vues confirmées) sont abandonnées.
2. **Ensuite seulement**, dégeler le reste de la région. Dans l'autre ordre, l'ancienne primaire se réveille en se croyant primaire : les applications d'Europe y écrivent, Lomé aussi → **deux histoires divergentes**.
3. Attendre l'état `streaming` (pas seulement « connectée » : pendant la copie, l'état est `backup`).

**Revenir en Europe (planifié, sans perte)** :
1. Vérifier que la réplique d'Europe est en `streaming` — sinon, **annuler**.
2. Arrêter proprement la primaire de Lomé : elle envoie ses derniers WAL avant de s'arrêter.
3. **Prouver** que la réplique a tout reçu : `pg_last_wal_receive_lsn()` sur l'Europe **au-delà** du `Latest checkpoint location` de `pg_controldata` sur Lomé. Sinon, redémarrer Lomé et annuler.
4. `terraform apply -var region_primaire=europe`.

L'étape 3 n'est pas théorique : sans elle, une réplique silencieusement bloquée depuis 60 s a été promue, et **129 commandes confirmées** ont été perdues.

## 4. Déployer une version, suivre la charge

**Déployer** : `./solution/palier-2/pipeline.sh deployer <version> --approuve` (sans `--approuve` : il s'arrête sur le plan enregistré, à relire). Région par région, l'Europe d'abord (moins de trafic : la région « canari »). La nouvelle version démarre dans la couleur **inactive** ; elle ne reçoit du trafic client qu'après ses tests de fumée ; l'ancienne reste debout jusqu'à la fin de l'observation. Régression de l'objectif (0 erreur, p95 < 500 ms) → **retour automatique** ; la version fautive reste déployée hors service, pour analyse (`pipeline.sh retirer <région> --approuve` ensuite).

**Revenir en arrière à la main** : `pipeline.sh retour <région>` — quelques secondes, tant que l'ancienne couleur a des instances.

**Suivre la charge** : `./solution/palier-2/autoscaler.sh boucle` (ou `evaluer`, une fois). Agrandir : instances d'abord, publication ensuite. Réduire : **dépublier** (variable `retrait`), attendre 15 s, éteindre.

**Si le pipeline refuse un plan (« POLITIQUE »)** : ce n'est pas un bug du pipeline. Quelque chose d'autre a changé — du code non relu, une dérive. `terraform plan` dans la couche concernée, comprendre, corriger, recommencer.

## Ce qui a failli nous tuer (et les garde-fous)

| Symptôme | Cause | Garde-fou |
| --- | --- | --- |
| 30 à 50 s de coupure après chaque remplacement de machine | MAC aléatoire à chaque instance ; les voisins gardent l'ancienne en cache ARP | ARP gratuit au démarrage (`annoncer`), comme VRRP |
| Service bloqué des minutes quand la base disparaît | Un pair gelé ne répond rien, pas même un refus : TCP retransmet longtemps | `tcp_user_timeout`, keepalives, `connect_timeout` (clients et serveur) |
| `pg_basebackup` bloqué pour toujours | Même cause, sur la copie | Mêmes bornes + plusieurs essais |
| Quelques 500 après un redémarrage de la base | Le pool prête des connexions mortes | `check=ConnectionPool.check_connection` |
| Révocations en échec permanent | PostgreSQL 16 : le créateur n'a que l'option ADMIN | `GRANT … TO bao` dans la révocation |
| Archivage bloqué (`[045]` : WAL déjà présent, contenu différent) | Une réplique en retard promue : sa copie du dernier segment diffère de celle archivée par l'autre | Garde du point 3 ; en réparation, marquer le segment `.done` (le dépôt fait foi) |
