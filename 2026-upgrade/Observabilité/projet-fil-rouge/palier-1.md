# 🟢 Projet fil rouge — Palier 1 : voir

> **Cours associé :** [01.md](../01.md) — **Durée indicative :** 6 à 10 h — **Prérequis :** avoir lu le [README du projet](README.md)

## Mission

Marché tourne, mais personne ne sait **ce qu'il fait**. Vous déployez une première stack d'observabilité auto-hébergée, vous construisez le tableau de bord de l'équipe, puis vous menez une **enquête** : dix questions sur le comportement de Marché, auxquelles vous répondez uniquement avec des requêtes.

## Point de départ

```bash
cp -r starter ~/marche-observable && cd ~/marche-observable
git init && git add . && git commit -m "Point de départ : application Marché"
docker compose up -d --build
curl -s localhost:8000/api/products
curl -s localhost:8000/metrics | grep http_requests_total
docker logs --tail 3 marche-payments
```

Prenez 10 minutes pour **explorer** avant de construire : lisez `app/common.py`, regardez les logs de chaque service, repérez les champs JSON, lisez le `/metrics` de chaque service.

---

## Étape 1 — Métriques (cours : modules 3 à 5)

Ajoutez à `docker-compose.yml` **Prometheus** et **Node Exporter**, puis configurez `prometheus/prometheus.yml`.

**Exigences :**
- [ ] Versions épinglées (aucun `latest`), volumes nommés pour les données.
- [ ] Prometheus scrape : lui-même, Node Exporter, et les **trois** services de Marché.
- [ ] Chaque série des services porte un label **`service`** valant `gateway`, `orders` ou `payments` (label imposé).
- [ ] Rétention de 15 jours ; rechargement à chaud possible (`/-/reload`).
- [ ] `promtool check config` passe.
- [ ] Toutes les cibles sont **UP** dans *Status → Target health*.

<details><summary>🔎 Indice 1</summary>

Les services écoutent sur 8000, 8001 et 8002, dans le réseau Compose : `gateway:8000`, etc. Un seul job suffit ; un label peut être ajouté **par groupe de cibles** dans `static_configs`.
</details>

<details><summary>🔎 Indice 2</summary>

```yaml
  - job_name: marche
    static_configs:
      - targets: ["gateway:8000"]
        labels: { service: gateway }
```
</details>

## Étape 2 — Premières requêtes (cours : module 6)

Dans l'UI de Prometheus, écrivez et gardez dans un fichier `requetes.md` :
- [ ] le débit de requêtes par service ;
- [ ] le taux d'erreurs 5xx du gateway (ratio entre 0 et 1) ;
- [ ] le nombre de cibles DOWN, qui vaut **0** (et pas « vide ») quand tout va bien ;
- [ ] l'utilisation CPU, mémoire et disque de l'hôte (en %).

## Étape 3 — Logs (cours : module 8)

Ajoutez **Loki** et **Grafana Alloy**.

**Exigences :**
- [ ] Alloy collecte les logs des conteneurs **du projet Marché uniquement** (aucun log d'autres projets Docker de votre machine).
- [ ] Chaque stream porte les labels **`service`** (nom du service Compose) et **`container`** (labels imposés).
- [ ] Aucun label à forte cardinalité (pas de `order_id`, `path`, `trace_id`… en label).
- [ ] Rétention Loki de 7 jours, **réellement appliquée**.
- [ ] Dans Explore, `{service="payments"} | json | msg="paiement refusé"` renvoie des lignes.

<details><summary>🔎 Indice</summary>

Le label Docker Compose `com.docker.compose.service` contient le nom du service ; `com.docker.compose.project` le nom du projet. Relisez le 🪤 du module 3.6 sur l'endroit où filtrer.
</details>

## Étape 4 — Le dashboard de l'équipe (cours : module 9)

Connectez Prometheus et Loki à Grafana (via l'UI à ce palier), puis créez le dashboard **« Marché — Vue d'ensemble »** (le titre doit contenir « Marché »).

**Exigences — au minimum :**
- [ ] Une rangée **Application** : débit par service, réponses du gateway par code HTTP (couleurs : 2xx vert, 4xx orange, 5xx rouge), taux d'erreur 5xx du gateway (stat avec seuils), nombre de cibles DOWN.
- [ ] Une rangée **Hôte** (méthode USE) : CPU, mémoire, disque des données Docker, avec unités et seuils.
- [ ] Une rangée **Logs** : volume de lignes WARNING/ERROR par service (depuis Loki) et un panel **Logs** des erreurs applicatives.
- [ ] Toutes les requêtes de taux utilisent `$__rate_interval` (métriques) ou `$__auto` (logs).
- [ ] Le dashboard est exporté en JSON dans votre dépôt : `grafana/marche-vue-ensemble.json`.

## Étape 5 — L'enquête

Créez `ENQUETE.md`. Pour **chaque** question : la requête (PromQL ou LogQL), le résultat, et une phrase d'interprétation. Laissez tourner Marché au moins une heure avant de répondre aux questions « sur la dernière heure ».

1. **Trafic** — Quel est le débit moyen de requêtes reçues par le gateway sur la dernière heure ? Quelle route en reçoit le plus ?
2. **Refus de paiement** — Quelle proportion des `POST /api/orders` se termine en 402 ? Est-ce cohérent avec le comportement documenté de payments ?
3. **Requêtes invalides** — Quelle proportion de requêtes reçoit un 422 ? D'où viennent-elles (lisez `loadgen.py`) ? Faut-il alerter dessus ?
4. **Latence depuis les logs** — Le gateway n'expose pas encore d'histogramme. Calculez quand même le **95ᵉ centile** de la durée des `POST /api/orders` sur 5 minutes, à partir des logs.
5. **Chiffre d'affaires** — Combien de francs CFA ont été encaissés sur la dernière heure ? (indice : les logs de payments)
6. **Hôte** — Combien de cœurs, quelle mémoire totale, quel uptime pour la machine qui héberge Marché ? Qu'est-ce que cette « machine » dans votre cas (serveur, VM Docker Desktop…) ?
7. **Coût** — Combien de séries actives dans Prometheus ? Quel job en produit le plus ? Combien de lignes de log par seconde Marché envoie-t-il à Loki, par service ?
8. **Incident simulé n°1** — Lancez `python chaos.py scenario paiement-instable`, attendez 5 minutes, puis `python chaos.py reset`. Sur votre dashboard : quels services renvoient des 5xx, avec quels codes ? Dans quel **ordre** l'erreur se propage-t-elle ? Quel message de log d'orders l'explique ?
9. **Incident simulé n°2** — `python chaos.py scenario paiement-hors-ligne` pendant 3 minutes. Que devient `up` pour payments ? Quels codes voit le client ? Remettez d'aplomb.
10. **Incident simulé n°3** — `python chaos.py scenario tempete-de-logs` pendant 3 minutes. De combien le débit de logs d'orders est-il multiplié ? Quelle requête le montre le mieux ? Pourquoi est-ce un problème même si le service répond normalement ?

<details><summary>🔎 Indices pour l'enquête</summary>

- Q2 : un ratio de deux `sum(increase(...[1h]))` filtrés sur `route` et `status`.
- Q4 : `quantile_over_time(0.95, … | json | route="/api/orders" | unwrap duration_ms [5m])` — n'oubliez pas le `by` (piège du module 8.6).
- Q5 : `sum_over_time(… | unwrap amount [1h])` sur les lignes « paiement accepté ».
- Q9 : avec une configuration statique, une cible arrêtée reste déclarée… Comparez avec ce qui se passera au Palier 2.
</details>

---

## Livrables

```
marche-observable/
├── docker-compose.yml         # app + prometheus, node-exporter, loki, alloy, grafana
├── prometheus/prometheus.yml
├── loki/loki-config.yaml
├── alloy/config.alloy
├── grafana/marche-vue-ensemble.json
├── requetes.md                # étape 2
└── ENQUETE.md                 # étape 5
```

## Critères d'acceptation

**Automatiques** — `python verify/verify.py --palier 1 --password <mdp>` entièrement vert :

| Critère vérifié |
| --- |
| Grafana répond, datasources Prometheus et Loki opérationnelles |
| Toutes les cibles UP, Node Exporter scrapé, les 3 services scrapés (label `service`) |
| Logs des 3 services dans Loki avec le label `service`, aucun log d'un autre projet |
| Un dashboard « Marché » d'au moins 6 panels, avec métriques, logs et `rate()` |

**Manuels** (auto-évaluation, ou relecture par un pair) :

| Critère | ✔ |
| --- | --- |
| Aucune image en `latest` ; `promtool check config` passe | |
| La rétention Loki est effective (compacteur configuré) | |
| Toutes les réponses de l'enquête ont requête + résultat + interprétation | |
| Q4 et Q5 utilisent `unwrap` avec une agrégation correcte | |
| Q8 identifie l'ordre de propagation payments (503) → orders (502) → gateway (502) | |
| Q9 explique pourquoi `up` vaut 0 pour payments | |
| Le dashboard est lisible par quelqu'un qui ne l'a pas construit (titres = questions, unités, seuils) | |

## Pièges rencontrés en construisant la solution

Ces pièges ont tous été rencontrés **pour de vrai** en préparant ce projet (voir aussi [solution/README.md](solution/README.md), à lire après) :

- Docker Desktop refuse `rslave` dans le volume de Node Exporter.
- Sous Docker Desktop, pas de point de montage `/` : les données Docker sont sous `/var/lib`.
- Filtrer les conteneurs avec une règle `keep` dans Alloy ne suffit pas.
- Grafana → `localhost:9090` ne fonctionne pas.

---

Palier validé ? Comparez avec [solution/palier-1](solution/palier-1/), puis passez au [Palier 2](palier-2.md).
