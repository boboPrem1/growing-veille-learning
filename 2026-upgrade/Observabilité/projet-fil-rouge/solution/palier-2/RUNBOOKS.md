# Runbooks — Marché

Une section par alerte ; l'ancre correspond au `runbook_url` de la règle. Format : **ce que ça veut dire → impact → où regarder → causes probables → actions → escalade**.

Dashboards : *Marché — Vue d'ensemble* (`/d/marche-vue-ensemble`), *Marché — Services (RED)* (`/d/marche-services-red`), *Infrastructure — Conteneurs & sondes* (`/d/infra-conteneurs-sondes`), *Paiements — Détail* (`/d/paiements-detail`).

---

## CibleInjoignable

**Signifie :** Prometheus n'arrive plus à scraper une cible depuis 1 min (`up == 0`).
**Impact :** variable — le service peut être mort (impact client) ou seulement son `/metrics` (aveuglement).
**Regarder :** *Status → Target health* dans Prometheus (message d'erreur exact) ; sonde blackbox du même service ; logs du conteneur dans Loki `{container="<nom>"}`.
**Causes probables :** conteneur arrêté ou en boucle de redémarrage ; port changé ; réseau Docker.
**Actions :** `docker compose ps` ; `docker compose logs --tail 100 <service>` ; redémarrer le service ; si un déploiement vient d'avoir lieu (annotation `deploy`), rollback.
**Escalade :** équipe propriétaire du service si non résolu en 15 min.
⚠️ Avec le service discovery Docker, un conteneur **arrêté** disparaît des cibles : cette alerte ne part pas, c'est `SondeEnEchec` qui prend le relais.

## SondeEnEchec

**Signifie :** vu de l'extérieur, un endpoint ne répond pas correctement (code HTTP, corps sans `"status": "ok"`, port TCP fermé).
**Impact :** élevé — c'est ce que vivent les clients (ou ce que vivra le service qui dépend de la cible).
**Regarder :** *Infrastructure — Conteneurs & sondes*, state timeline ; `curl "localhost:9115/probe?target=<cible>&module=http_health&debug=true"` ; pour orders, `/healthz` renvoie `"database": "down"` si PostgreSQL est tombé.
**Causes probables :** service arrêté, dépendance (base) injoignable, surcharge (timeout 5 s).
**Actions :** identifier la cible, puis suivre `CibleInjoignable` / `PostgresIndisponible`.

## PostgresIndisponible

**Signifie :** postgres-exporter ne joint plus PostgreSQL (`pg_up == 0`).
**Impact :** critique — plus aucune commande possible (orders renvoie 500/502, le gateway 5xx).
**Regarder :** logs `{service="postgres"}` ; logs d'orders `{service="orders", level="error"}` ; sonde TCP `postgres:5432`.
**Causes probables :** conteneur arrêté, disque plein, trop de connexions (`pg_stat_database_numbackends`).
**Actions :** `docker compose up -d postgres` ; vérifier l'espace disque (`DisquePleinSous24h`) ; vérifier qu'orders se reconnecte (le pool rouvre les connexions).
**Note :** les alertes `TauxErreursEleve` et `AucuneCommandePayee` sont inhibées pendant cette panne : elles en sont la conséquence.

## TauxErreursEleve

**Signifie :** plus de 5 % des requêtes d'un service renvoient une 5xx depuis 2 min (avec au moins 0,1 req/s).
**Impact :** critique — des clients voient des erreurs.
**Regarder :** *Services (RED)* filtré sur le service : quelle **route** ? quel **code** (502 = dépendance, 503 = indisponible, 500 = bug) ? Puis les logs `{service="<service>", level="error"} | json`.
**Causes probables :** dépendance en panne (payments, base), bug après déploiement, surcharge.
**Actions :** remonter la chaîne : gateway 502 → orders ? orders 502 → payments ? Corriger au niveau le plus bas. Rollback si corrélé à un déploiement.

## LatenceP95Elevee

**Signifie :** 5 % des requêtes d'un service prennent plus d'une seconde depuis 3 min.
**Impact :** dégradé — les clients attendent, certains abandonnent.
**Regarder :** heatmap des durées (une seule bande qui monte ou deux populations ?) ; p95 du prestataire de paiement (*Paiements — Détail*) ; CPU du conteneur ; au Palier 3 : un exemplar → la trace.
**Causes probables :** dépendance lente (payments, requête SQL), CPU saturé, file d'attente (`http_requests_in_progress` qui monte).
**Actions :** identifier le maillon lent en comparant la latence de chaque service de la chaîne : le plus bas qui est lent est le coupable.

## AucuneCommandePayee

**Signifie :** aucune commande payée depuis 15 min, ou la métrique a disparu (orders arrêté).
**Impact :** critique — le chiffre d'affaires est à zéro. Le « silence » peut cacher une panne que les autres alertes ne voient pas (ex. le loadgen ou le front ne peuvent plus commander).
**Regarder :** *Services (RED)*, rangée métier : commandes par statut ; trafic entrant sur `POST /api/orders` ; logs d'orders.
**Causes probables :** orders arrêté, paiements tous refusés/en erreur, plus aucun trafic en entrée.
**Actions :** si le trafic entrant est nul, le problème est en amont (réseau, gateway, client) ; sinon suivre les erreurs de la chaîne.

## RefusPaiementAnormaux

**Signifie :** plus de 10 % des paiements refusés sur 15 min (normal : ~3 %).
**Impact :** métier — des clients ne peuvent pas payer (solde, fraude, problème du prestataire).
**Regarder :** *Paiements — Détail* : refus par moyen de paiement ; logs des refus (motif).
**Actions :** prévenir l'équipe paiements ; contacter le prestataire si un seul moyen est touché.

## ConteneurFuiteMemoire

**Signifie :** la mémoire d'un conteneur démarré depuis plus de 15 min croît de plus de 100 Ko/s en continu.
**Impact :** différé — le conteneur finira tué par l'OOM killer (redémarrage, erreurs pendant ce temps).
**Regarder :** *Infrastructure — Conteneurs & sondes* : mémoire du conteneur sur 1 h ; corréler avec le trafic (la croissance suit-elle les requêtes ?) et avec les déploiements.
**Actions :** court terme : redémarrer le conteneur (répit) ; fond : identifier le déploiement fautif, rollback, profilage (Pyroscope) pour trouver l'objet qui fuit.

## ConteneurCPUSature

**Signifie :** un conteneur Marché consomme plus de 0,8 cœur depuis 5 min.
**Impact :** en Python (GIL), un cœur saturé = toutes les requêtes du service ralentissent.
**Regarder :** CPU par conteneur ; latence du même service ; trafic (le CPU suit-il la charge ?).
**Actions :** si le CPU ne suit **pas** la charge : un traitement parasite (boucle, tâche de fond) → logs, profilage, redémarrage ; si oui : scaler le service.

## TempeteDeLogs (Grafana)

**Signifie :** un service émet plus de 300 lignes WARNING par minute.
**Impact :** coût d'ingestion Loki, risque de limites (429) qui feraient perdre **tous** les logs, signal noyé.
**Regarder :** *Infrastructure*, volume de logs par service ; `{service="<service>", level="warning"} | json` : quel message se répète ?
**Actions :** traiter la cause du message ; en urgence, filtrer ce message dans Alloy (`stage.drop`).

## PaiementsInjoignablesDansLesLogs (Grafana)

**Signifie :** orders a logué plus de 5 fois « service payments injoignable » en 2 min.
**Impact :** critique — toutes les commandes échouent en 502.
**Regarder :** sonde blackbox de payments ; logs de payments (a-t-il crashé ?).
**Actions :** relancer payments ; vérifier le réseau Docker.
