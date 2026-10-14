# Solutions de référence — à ouvrir APRÈS avoir fini un palier

Chaque dossier est une stack **complète et autonome** (application + observabilité), construite et testée de bout en bout en septembre 2026 (Docker Desktop 29 / WSL2, Windows 11). Toutes partagent le nom de projet Compose `marche` : on passe d'un palier au suivant **par-dessus** le précédent, comme l'apprenant.

| Palier | Lancer | Grafana | `verify.py` |
| --- | --- | --- | --- |
| 1 | `cd palier-1 && docker compose up -d --build`, puis datasources et import de `grafana/dashboards/marche-vue-ensemble.json` dans l'UI | http://localhost:3000 — `admin` / `marche-admin` | 9/9 |
| 2 | `cd palier-2 && docker compose up -d --build --remove-orphans && python scripts/grafana_rbac.py` | http://localhost:3000 — `admin` / `marche-admin` | 24/24 |
| 3 | créer les secrets (`secrets/README.md`), `docker compose up -d --build --remove-orphans` | https://localhost:8443 — `admin` / contenu de `secrets/grafana_admin_password.txt` | 40/40 |

Le parcours complet a été rejoué de zéro (`docker compose down -v`) : Palier 1 non configuré → 1/9 (le correcteur détecte bien les manques), configuré → 9/9 ; migration vers le Palier 2 → 24/24 ; migration vers le Palier 3 → 40/40.

## Ce que contient chaque solution

- **palier-1/** — `prometheus/`, `loki/`, `alloy/`, dashboard exporté (format « partage » avec `__inputs`, car les datasources sont créées à la main à ce palier). Utilise l'application de `../../starter/app`.
- **palier-2/** — application instrumentée (`app/`), règles + tests `promtool`, Alertmanager + template, blackbox, service discovery Docker, pipeline Alloy, provisioning Grafana complet (datasources, 4 dashboards dans 3 dossiers, alertes Loki), scripts RBAC et annotation, [ALERTING.md](palier-2/ALERTING.md), [RUNBOOKS.md](palier-2/RUNBOOKS.md), [INCIDENTS.md](palier-2/INCIDENTS.md).
- **palier-3/** — OpenTelemetry, Collector, Tempo 3, Mimir 3, Prometheus HA ×2, Alertmanager ×2, SLO Sloth + dashboard, Caddy HTTPS, réseaux segmentés, secrets, proxy de socket, masquage des téléphones, `scripts/validate.sh` + workflow CI, [SLO.md](palier-3/SLO.md), [SECURITE.md](palier-3/SECURITE.md), [RUNBOOKS.md](palier-3/RUNBOOKS.md).

## Les pièges rencontrés en construisant ces solutions

Tous réels, tous reproduits. Ils sont aussi signalés (🪤) dans les cours.

| # | Palier | Symptôme | Cause | Correctif |
| --- | --- | --- | --- | --- |
| 1 | 1 | `/metrics` répond 307 | `app.mount("/metrics", …)` dans Starlette redirige vers `/metrics/` | Une vraie route, avec négociation OpenMetrics (`choose_encoder`) |
| 2 | 1 | Séries `*_created` parasites | Comportement par défaut de `prometheus-client` | `PROMETHEUS_DISABLE_CREATED_SERIES=True` |
| 3 | 1 | Node Exporter ne démarre pas | Docker Desktop refuse le montage `rslave` | `/:/host:ro` au lab |
| 4 | 1 | Aucun point de montage `/` | Sous Docker Desktop, les données Docker sont sous `/var/lib` | `mountpoint=~"/|/var/lib"` |
| 5 | 1 | Loki rejette des logs `timestamp too old`, streams sans labels | La règle `keep` dans `discovery.relabel` n'empêche pas `loki.source.docker` de lire les autres conteneurs | Filtrer dans `discovery.docker` (`filter { name = "label" … }`) |
| 6 | 1 | `avg_over_time(… unwrap …)` renvoie 271 séries | Chaque champ extrait par `\| json` devient un label | Toujours `… by (label)` |
| 7 | 1 | Erreur de template LogQL | `atoi` n'existe pas dans les templates Loki | `hasPrefix "5" .status` |
| 8 | 2 | Grafana redémarre en boucle (« data source not found ») | Datasources créées à la main au Palier 1, mêmes noms, uid aléatoires | `deleteDatasources` dans le fichier de provisioning |
| 9 | 2 | Sonde Grafana en échec | `/api/health` de Grafana n'a pas de champ `status` | Module `http_2xx` pour cette cible via `__param_module` |
| 10 | 2 | Une alerte critique du gateway n'arrive qu'à l'astreinte | Avec `continue: true`, le receiver racine n'est plus utilisé | Route « attrape-tout » explicite en fin d'arbre |
| 11 | 2 | `CibleInjoignable` muette quand payments est arrêté | Docker SD : le conteneur arrêté disparaît, `up` n'existe plus | Sonde blackbox (et/ou `absent()`) |
| 12 | 2 | `ConteneurFuiteMemoire` en *pending* après chaque redémarrage | La mémoire monte normalement au démarrage | Garde `time() - container_start_time_seconds > 900` |
| 13 | 2 | Ratio d'erreurs « No data » au lieu de 0 % | Numérateur vide quand il n'y a aucune 5xx | `(erreurs or total * 0) / total` |
| 14 | 2 | Test `promtool` qui échoue alors que la règle est juste | Un point par heure : la série disparaît entre deux points (lookback 5 min) | Intervalle de test ≤ 1 min |
| 15 | 2 | Ruler Loki : toutes les règles en erreur « appender not ready » | WAL du ruler dans un dossier relatif non inscriptible | `ruler.wal.dir: /loki/ruler-wal` |
| 16 | 2 | Remote write du ruler Loki refusé (404) | Récepteur non activé | `--web.enable-remote-write-receiver` sur Prometheus |
| 17 | 3 | Mot de passe Grafana refusé après migration | `GF_SECURITY_ADMIN_PASSWORD(__FILE)` n'est lu qu'à la création de la base | `grafana cli admin reset-admin-password` |
| 18 | 3 | Mimir rejette tout le remote write (`err-mimir-label-invalid`) | L'OTel Collector expose des labels UTF-8 (`server.address`) | `metric_name_validation_scheme: legacy` + `metric_name_escaping_scheme: underscores` |
| 19 | 3 | Notifications en double avec la paire HA | `__replica__` est transmis aux Alertmanager | `alert_relabel_configs` : `labeldrop` `__replica__` |
| 20 | 3 | SLO de disponibilité invisible (ni burn rate ni budget) | Sans 5xx, `sum(rate(… 5xx …))` est vide | `… or vector(0)` dans `error_query` |
| 21 | 3 | Tempo refuse de démarrer | Processeur `local-blocks` supprimé dans Tempo 3 | Le retirer |
| 22 | 3 | TraceQL sur `span.db.system.name` ne trouve rien | L'instrumentation psycopg émet encore l'ancien `db.system` | Vérifier les attributs réellement émis |
| 23 | 3 | Scripts en échec TLS | Certificat de la CA locale Caddy | Option `--insecure` explicite (lab uniquement) |
| 24 | 2 | 9 e-mails pour une seule panne de payments | Les séries `probe_success` n'ont pas de label `service` : l'inhibition `equal: [service]` ne s'applique jamais | Relabeling qui extrait `service` de l'URL sondée |
| 25 | 2 | `CibleInjoignable` sur orders alors que c'est la base qui est tombée | Les requêtes bloquées sur le pool de connexions occupent tous les threads, `/metrics` compris | À connaître : un scrape en échec peut être un symptôme de saturation |

Les mesures de détection des 8 scénarios de panne (8/8 détectés, délais de 1,5 à 9,6 min) sont dans [palier-2/INCIDENTS.md](palier-2/INCIDENTS.md).

## Notes

- Les `secrets/*.txt` du Palier 3 contiennent des mots de passe **de lab** ; ils sont ignorés par Git.
- Les dashboards ont été générés puis vérifiés automatiquement : chaque requête de chaque panel renvoie des données (hors panels d'erreurs en l'absence d'erreurs).
- Votre solution peut légitimement différer (noms d'alertes supplémentaires, autres seuils, autre découpage des dashboards) tant que les critères imposés et `verify.py` sont respectés.
