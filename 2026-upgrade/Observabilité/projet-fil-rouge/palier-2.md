# 🟡 Projet fil rouge — Palier 2 : être prévenu

> **Cours associé :** [02.md](../02.md) — **Durée indicative :** 12 à 20 h — **Prérequis :** Palier 1 validé

## Mission

L'équipe de Marché a adoré le dashboard… mais personne ne le regarde à 3 h du matin. Vous devez faire en sorte que **les pannes viennent à vous** : l'application expose enfin ce qui compte (latences, commandes, argent encaissé), chaque panne connue déclenche une alerte **testée** qui arrive à la bonne personne, et toute la configuration vit dans Git — plus un seul clic non reproductible. Enfin, l'équipe paiements doit avoir son espace, invisible des autres.

Vous travaillez toujours dans **votre** dépôt `marche-observable`.

---

## Étape 1 — Instrumenter Marché (cours : module 1)

Modifiez `app/common.py`, `app/orders.py` et `app/payments.py` — l'**instrumentation** seulement, jamais la logique métier.

**Métriques imposées** (noms, types et labels exacts : le correcteur et les règles en dépendent) :

| Métrique | Type | Labels | Où |
| --- | --- | --- | --- |
| `http_request_duration_seconds` | Histogram | `method`, `route` | les 3 services (middleware) |
| `http_requests_in_progress` | Gauge | — | les 3 services |
| `marche_build_info` | Gauge (= 1) | `version` (variable `SERVICE_VERSION`) | les 3 services |
| `marche_orders_total` | Counter | `payment_method`, `status` (`paid`, `payment_declined`, `payment_error`) | orders |
| `marche_revenue_xof_total` | Counter | `payment_method` — montant encaissé des commandes payées | orders |
| `marche_payment_provider_duration_seconds` | Histogram | `method`, `outcome` (`approved`, `declined`) | payments |

**Exigences :**
- [ ] Les buckets de `http_request_duration_seconds` contiennent `0.5` (futur objectif de latence, Palier 3).
- [ ] Les combinaisons connues de `marche_orders_total` et `marche_revenue_xof_total` sont initialisées à 0.
- [ ] Aucune série `*_created` exposée.
- [ ] `SERVICE_VERSION` vaut `1.1.0` pour les trois services.

<details><summary>🔎 Indice</summary>

Le middleware de `common.py` connaît déjà la méthode, la route (modèle) et la durée : il ne manque qu'une ligne pour observer l'histogramme. `prometheus_client.Gauge.track_inprogress()` est un gestionnaire de contexte. Pour les commandes, l'endroit naturel est la fonction qui fixe le statut final.
</details>

## Étape 2 — Exporters et service discovery (cours : modules 2 et 3)

- [ ] **cAdvisor** : métriques par conteneur Marché, cardinalité réduite (flags du cours).
- [ ] **postgres-exporter** : `pg_up == 1`.
- [ ] **Blackbox** : sonde les `/healthz` des 3 services **en exigeant `"status": "ok"`** dans le corps, une sonde TCP sur PostgreSQL, et Grafana (attention au piège du cours).
- [ ] Les 3 services **et** postgres-exporter sont découverts par **service discovery Docker** (labels `prometheus.scrape`, `prometheus.port`, `prometheus.job`) : plus aucune cible applicative dans `static_configs`.
- [ ] Le label `job` vaut **`app`** pour les 3 services (imposé), et le label `service` est conservé.

## Étape 3 — Règles (cours : modules 4 et 5)

**Recording rules** — au minimum, avec ces noms exacts :
- [ ] `service:http_requests:rate5m`
- [ ] `service:http_requests_errors:ratio_rate5m`
- [ ] `service:http_request_duration_seconds:p95_rate5m`

**Alertes** — au minimum celles-ci, chacune avec `severity`, `summary` et `runbook_url` :

| Alerte | Sévérité | Détecte |
| --- | --- | --- |
| `CibleInjoignable` | critical | une cible qui ne répond plus au scrape |
| `SondeEnEchec` | critical | un endpoint en échec vu de l'extérieur |
| `PostgresIndisponible` | critical | la base injoignable |
| `TauxErreursEleve` | critical | > 5 % de 5xx sur un service (avec un trafic minimal) |
| `LatenceP95Elevee` | warning | p95 d'un service > 1 s |
| `AucuneCommandePayee` | critical | 0 commande payée en 10 min, **y compris** si la série a disparu |
| `ConteneurCPUSature` | warning | un conteneur Marché consomme > 0,8 cœur |
| `ConteneurFuiteMemoire` | warning | une mémoire qui croît continûment, **sans** faux positif au redémarrage |

**Tests :**
- [ ] `prometheus/tests/*.yml` teste au moins `CibleInjoignable`, `TauxErreursEleve` (cas positif **et** cas d'un service sain), `AucuneCommandePayee`, et la valeur d'une recording rule.
- [ ] `promtool test rules` passe.

## Étape 4 — Alertmanager (cours : module 6)

- [ ] E-mails via **Mailpit** (UI sur http://localhost:8025).
- [ ] Routage : `critical` → `astreinte@marche.local` **et** l'équipe ; alertes des services `payments`/`orders` → `paiements@marche.local` ; tout le reste → `equipe@marche.local`.
- [ ] Au moins deux inhibitions justifiées (ex. : une cible injoignable masque ses erreurs et sa latence ; PostgreSQL tombé masque les erreurs applicatives).
- [ ] Un template : objet lisible (statut, nombre d'alertes, nom, service) et lien vers le runbook.
- [ ] Dans `ALERTING.md`, la sortie de `amtool config routes test` pour 4 cas représentatifs.

## Étape 5 — Logs, niveau 2 (cours : modules 7 et 10)

- [ ] Pipeline Alloy : `level` promu en label **pour les 3 services seulement** ; les logs d'accès de `/healthz` sont jetés.
- [ ] Une alerte Grafana **sur les logs** `TempeteDeLogs` : un service émet plus de 300 lignes WARNING par minute.
- [ ] Une alerte Grafana sur les logs `PaiementsInjoignablesDansLesLogs` (orders ne joint plus payments).

## Étape 6 — Tout en code (cours : modules 8 et 9)

- [ ] Datasources provisionnées avec les uid **`prometheus`**, **`loki`**, **`alertmanager`** (imposés).
- [ ] Dashboards provisionnés depuis `grafana/dashboards/<Dossier>/`, modifications UI interdites :
  - **Application / Marché — Vue d'ensemble** : celui du Palier 1, migré vers les uid fixes ;
  - **Application / Marché — Services (RED)** : variables `service` puis `route` (chaînées, multi, All), une **row répétée par service** (Rate, Errors, Duration p50/p95/p99), une **heatmap** des durées, un tableau des **versions déployées** (transformation), une rangée **métier** (CA encaissé sur 1 h, commandes par statut, p95 du prestataire par moyen), annotations **déploiements** (tag `deploy`) et **alertes Prometheus** ;
  - **Infrastructure / Conteneurs & sondes** : state timeline des sondes, CPU/mémoire/réseau par conteneur (variable), PostgreSQL, volume de logs par service ;
  - **Paiements / Paiements — Détail** : p50/p95 du prestataire, paiements par résultat, logs des refus mis en forme avec `line_format`.
- [ ] Alerting Grafana (règles, contact point, politique) provisionné par fichiers.
- [ ] Un `docker compose down -v && docker compose up -d` redonne **exactement** la même Grafana, sans aucun clic.

🪤 Au premier démarrage avec provisioning, Grafana peut refuser de démarrer à cause des datasources créées à la main au Palier 1 : relisez le module 9.2 du cours.

## Étape 7 — Accès (cours : module 11)

Écrivez `scripts/grafana_rbac.py` (ou `.sh`), **idempotent** :
- [ ] Utilisateurs `awa` (Viewer) et `koffi` (Editor), membres de l'équipe `equipe-paiements` ; `yao` (Viewer) hors équipe.
- [ ] Dossier « Paiements » accessible **uniquement** à `equipe-paiements` (et aux admins). Prouvez que `yao` ne voit pas le dashboard.
- [ ] Compte de service `ci-dashboards` (Editor) et son jeton.
- [ ] `scripts/annotate_deploy.py <service> <version>` pose une annotation `deploy` avec ce jeton. Utilisez-le quand vous redéployez avec `SERVICE_VERSION` à `1.1.0`.

## Étape 8 — La preuve : exercices d'incident

Pour **chaque** scénario, lancez-le, notez **quelle alerte** le détecte, **en combien de temps**, **quel e-mail** arrive et **à qui**, puis remettez d'aplomb (`python chaos.py reset`). Consignez tout dans `INCIDENTS.md`.

| Scénario | Alerte attendue (à vous de le vérifier) | Détecté ? | Délai | Destinataires |
| --- | --- | --- | --- | --- |
| `paiement-instable` | | | | |
| `paiement-lent` | | | | |
| `paiement-hors-ligne` | | | | |
| `base-hors-ligne` | | | | |
| `base-lente` | | | | |
| `fuite-memoire` (≥ 20 min) | | | | |
| `cpu-sature` | | | | |
| `tempete-de-logs` | | | | |

**Questions à traiter dans `INCIDENTS.md` :**
1. Avec `paiement-hors-ligne`, `CibleInjoignable` se déclenche-t-elle pour payments ? Pourquoi (comparez avec votre réponse à la Q9 du Palier 1) ? Qu'est-ce qui vous a sauvé ?
2. Avec `base-hors-ligne`, combien d'e-mails avez-vous reçus ? Vos inhibitions ont-elles fonctionné ? Qu'avez-vous ajusté ?
3. Un scénario n'a-t-il déclenché **aucune** alerte ? Écrivez celle qui manquait, testez-la, rejouez le scénario.

## Étape 9 — Runbooks

`RUNBOOKS.md` : une section par alerte **critical** (ancre = le `runbook_url`), avec : ce que signifie l'alerte, l'impact client, les dashboards et requêtes à regarder en premier, les causes probables, les actions de remédiation, qui prévenir.

---

## Livrables

```
marche-observable/
├── app/                                  # instrumentée
├── docker-compose.yml
├── prometheus/{prometheus.yml, rules/, tests/}
├── alertmanager/{alertmanager.yml, templates/}
├── blackbox/blackbox.yml
├── alloy/config.alloy
├── loki/loki-config.yaml
├── grafana/{provisioning/, dashboards/}
├── scripts/{grafana_rbac.py, annotate_deploy.py}
├── ALERTING.md   INCIDENTS.md   RUNBOOKS.md
```

## Critères d'acceptation

**Automatiques** — `python verify/verify.py --palier 2 --password <mdp>` (depuis le dossier `projet-fil-rouge/`) entièrement vert. En plus des critères du Palier 1 :

| Critère vérifié |
| --- |
| Datasources provisionnées avec uid fixes ; ≥ 2 dashboards provisionnés ; un dashboard avec variable de requête et annotation |
| Histogramme de latence sur les 3 services ; métriques métier présentes |
| ≥ 3 recording rules bien nommées ; ≥ 6 alertes complètes ; Prometheus relié à Alertmanager |
| cAdvisor, Blackbox (≥ 3 sondes), postgres-exporter (`pg_up == 1`) ; service discovery Docker |
| Label `level` dans Loki ; alerte Grafana sur Loki provisionnée par fichier |
| Une équipe avec membres et un dossier réservé à une équipe |

**Manuels :**

| Critère | ✔ |
| --- | --- |
| `promtool test rules` et `amtool check-config` passent | |
| Aucun label à cardinalité illimitée (vérifiez *TSDB status*) | |
| `down -v` puis `up -d` redonne la même Grafana sans clic | |
| Les 8 scénarios sont documentés ; au moins 7 détectés **par une alerte** | |
| La question 1 de l'étape 8 est correctement expliquée | |
| Chaque alerte critical a son runbook, à l'ancre de son `runbook_url` | |
| Une annotation de déploiement apparaît sur le dashboard RED | |

---

Palier validé ? Comparez avec [solution/palier-2](solution/palier-2/) (et lisez [solution/README.md](solution/README.md)), puis passez au [Palier 3](palier-3.md).
