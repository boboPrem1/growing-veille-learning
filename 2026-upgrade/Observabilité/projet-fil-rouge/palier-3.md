# 🔴 Projet fil rouge — Palier 3 : comprendre et tenir

> **Cours associé :** [03.md](../03.md) — **Durée indicative :** 20 à 30 h + l'épreuve finale — **Prérequis :** Palier 2 validé, 8 Go de RAM libres

## Mission

Marché grandit. Les alertes sonnent, mais diagnostiquer prend encore trop longtemps : « c'est lent… mais où ? ». La direction veut un engagement de qualité de service chiffré. L'audit de sécurité a trouvé Prometheus ouvert sur le réseau et des numéros de téléphone de clients dans les logs. Et si la machine de Prometheus tombe, plus personne n'est prévenu.

Vous devez : **tracer** chaque requête de bout en bout et relier tous les signaux ; **tenir** (stockage long terme, haute disponibilité, méta-monitoring) ; **piloter par les SLO** ; **sécuriser** ; **automatiser** la validation. Puis vous passerez l'**épreuve finale**.

---

## Étape 1 — Tracer Marché (cours : modules 1 à 4)

**Application** (instrumentation uniquement) :
- [ ] Traces OpenTelemetry pour les 3 services : spans serveur (FastAPI), client (httpx) et SQL (psycopg), propagation W3C ; `/healthz` et `/metrics` exclus.
- [ ] Un span manuel **`prestataire.debit`** dans payments, avec les attributs `payment.method`, `payment.amount_xof`, `payment.outcome` ; un refus est un **événement**, pas une erreur.
- [ ] `trace_id` et `span_id` dans **chaque** ligne de log JSON émise pendant une requête.
- [ ] Un **exemplar** `trace_id` sur chaque observation de `http_request_duration_seconds`.
- [ ] Configuration du SDK par variables d'environnement standard (`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_SAMPLER`, `OTEL_RESOURCE_ATTRIBUTES` avec `deployment.environment.name=lab`) ; `SERVICE_VERSION` passe à `1.2.0`.

**Infrastructure :**
- [ ] Un **OpenTelemetry Collector** (processeurs `memory_limiter`, `resource`, `batch`), seul destinataire des applications, qui exporte vers Tempo.
- [ ] **Tempo 3** en monolithique, avec le metrics-generator (`service-graphs`, `span-metrics`) qui écrit dans Mimir (étape 3).

<details><summary>🔎 Indice</summary>

Le SDK doit être configuré **avant** l'ouverture du pool de connexions et la création des clients httpx. Tout le reste de l'instrumentation tient dans `common.py`.
</details>

## Étape 2 — Corréler (cours : module 5)

- [ ] Datasource **Tempo** (uid imposé : `tempo`) avec traces → logs, traces → métriques, service map et node graph.
- [ ] Alloy place `trace_id` en **structured metadata** ; la datasource Loki a un *derived field* vers Tempo.
- [ ] Datasource Prometheus : exemplars → Tempo ; Prometheus lancé avec le stockage des exemplars.
- [ ] Le panel « Duration » du dashboard RED affiche les exemplars.
- [ ] Démonstration écrite (`CORRELATION.md`, avec captures) : partir d'un pic de latence, cliquer un exemplar, ouvrir la trace, sauter aux logs du span, revenir aux métriques du service.

## Étape 3 — Tenir la charge et les pannes (cours : modules 7 et 8)

- [ ] **Mimir** (monolithique, uid de datasource imposé : `mimir`) reçoit le `remote_write` des Prometheus et du metrics-generator de Tempo ; exemplars acceptés.
- [ ] **Deux** Prometheus (`prometheus-a`, `prometheus-b`), **une seule** configuration, dédoublonnés dans Mimir (`cluster` / `__replica__`) — prouvez-le : `up{job="node"}` doit renvoyer **une** série dans Mimir.
- [ ] **Deux** Alertmanager en cluster ; chaque Prometheus notifie les deux ; **aucune notification en double** (prouvez-le avec Mailpit).
- [ ] Alerte **Watchdog** routée vers un receiver dédié (dead man's switch, receiver vide accepté au lab, commentaire expliquant la cible réelle).
- [ ] Méta-monitoring : Loki, Tempo, Mimir, Alloy, le Collector, Grafana et les deux Prometheus sont scrapés ; alertes `RemoteWriteEnEchec`, `AlertmanagerClusterDegrade`, `CollectorRefuseDesSpans`.
- [ ] La rétention locale des Prometheus passe à 2 jours : le long terme est dans Mimir.

## Étape 4 — Piloter par les SLO (cours : module 10)

- [ ] `slo/marche-gateway.yml` (Sloth) : **disponibilité 99,5 %** (hors `/healthz`, 5xx = mauvais) et **latence 99 % < 500 ms**, sur 30 jours, avec alertes page (critical) et ticket (warning).
- [ ] Les règles générées sont versionnées dans `prometheus/rules/` et chargées par les deux Prometheus.
- [ ] Dashboard **SLO / Marché — SLO du parcours client** (uid `marche-slo`) : objectif, SLI sur 30 j, budget restant, burn rate actuel et par fenêtre (5 min, 1 h, 6 h), depuis **Mimir**.
- [ ] `SLO.md` : pourquoi ces objectifs, budget en minutes par mois, **politique de budget d'erreur** (que fait l'équipe à 50 %, 25 %, 0 %).

## Étape 5 — Sécuriser (cours : module 12)

**Avant de commencer**, l'équipe métier ajoute (sans vous prévenir…) le numéro de téléphone du client dans les logs de payments. Collez ceci dans `payments.py`, juste avant le `if declined:`, et ajoutez `"customer_phone": phone` aux `extra` des deux `log.warning` / `log.info` :

```python
    phone = f"+228 9{req.order_id % 10} {req.order_id % 100:02d} {(req.order_id * 7) % 100:02d} {(req.order_id * 13) % 100:02d}"
```

Exigences :
- [ ] **Seul** Grafana est accessible depuis l'hôte, en **HTTPS** sur `https://localhost:8443` (reverse proxy) ; l'application (8000-8002) et Mailpit (8025, sur 127.0.0.1) restent accessibles pour `chaos.py` et le lab.
- [ ] Réseaux segmentés : la stack d'observabilité sur un réseau `internal: true`.
- [ ] Prometheus protégé par authentification (UI, API, reload) ; tout ce qui l'interroge s'authentifie.
- [ ] **Aucun** mot de passe en clair dans le dépôt ni dans le compose : secrets Docker, `*.txt` dans `.gitignore`, `secrets/README.md` expliquant comment les créer.
- [ ] Accès anonyme Grafana désactivé, cookies sécurisés.
- [ ] Plus aucun conteneur ne monte le socket Docker directement, sauf un **proxy en lecture seule**.
- [ ] Les numéros de téléphone sont **masqués dans Loki** (`+228 95 ** ** 65`). Dans `SECURITE.md`, expliquez pourquoi ce masquage ne suffit pas et ce qu'il faudrait faire en plus.

🪤 En migrant, vous découvrirez qu'une variable d'environnement de Grafana… ne fait rien. Relisez le module 12.5 du cours.

## Étape 6 — Automatiser (cours : module 13)

- [ ] `scripts/validate.sh` : **tous** les contrôles du tableau du module 13.2 (dont les tests unitaires, la cohérence Sloth et une assertion sur l'arbre de routage).
- [ ] `.github/workflows/observabilite-ci.yml` : validation sur chaque PR, déploiement (même simulé) + annotation Grafana sur `main`.
- [ ] Faites échouer volontairement la CI trois fois (règle invalide, test d'alerte cassé, dashboard avec `${DS_PROMETHEUS}`) et vérifiez qu'elle bloque.

## Étape 7 — Diagnostiquer par les traces

Pour chacun de ces scénarios, **sans regarder `chaos.py` ni le code**, retrouvez la cause avec la stack uniquement, et consignez dans `DIAGNOSTICS.md` le chemin suivi (alerte → dashboard → requête TraceQL → span → logs) et la requête TraceQL décisive :

- [ ] `base-lente` (le span SQL fautif et sa requête)
- [ ] `paiement-lent` (où le temps est-il **vraiment** perdu dans payments ? Le span `prestataire.debit` est-il lent ?)
- [ ] `paiement-instable` (quel pourcentage de traces sont en erreur, et à quel endroit l'erreur naît-elle ?)
- [ ] `cpu-sature` (pourquoi les traces d'orders ralentissent-elles alors qu'aucun span enfant n'est lent ?)

---

## Livrables

```
marche-observable/
├── app/                                 # + OpenTelemetry
├── docker-compose.yml                   # réseaux, secrets, HA, proxy de socket
├── prometheus/{prometheus.yml, web-config.yml, rules/ (dont SLO générées), tests/}
├── alertmanager/   otel-collector/   tempo/   mimir/   loki/   alloy/   blackbox/   caddy/
├── slo/marche-gateway.yml
├── grafana/{provisioning/, dashboards/}  # + dossier SLO
├── secrets/README.md   .gitignore
├── scripts/validate.sh
├── .github/workflows/observabilite-ci.yml
└── CORRELATION.md   SLO.md   SECURITE.md   DIAGNOSTICS.md
```

## Critères d'acceptation

**Automatiques** — depuis le dossier `projet-fil-rouge/` :

```bash
python verify/verify.py --palier 3 --url https://localhost:8443 --password <mdp> --repo ~/marche-observable
```

entièrement vert (critères des Paliers 1 et 2 inclus), notamment :

| Critère vérifié |
| --- |
| HTTPS, anonyme désactivé ; Prometheus, Loki, Alertmanager, Tempo, Mimir et OTLP non exposés |
| Traces des 3 services, dont une qui les traverse tous ; logs avec `trace_id` ; exemplars stockés |
| Corrélations configurées (exemplars, traces → logs, logs → traces) ; service graph |
| Long terme interrogeable ; paire HA dédoublonnée ; cluster Alertmanager ; Watchdog |
| SLI enregistrés et alertes multi-burn-rate ; aucun téléphone non masqué ; méta-monitoring |
| CI présente (promtool, amtool) ; secrets hors du dépôt |

**Manuels :**

| Critère | ✔ |
| --- | --- |
| `./scripts/validate.sh` passe ; la CI a bien bloqué les 3 erreurs volontaires | |
| Aucune notification en double pendant un incident (Mailpit) | |
| Arrêter `prometheus-a` : les données continuent d'arriver dans Mimir, `CibleInjoignable` part (depuis b) | |
| `CORRELATION.md` montre les 4 sauts en captures | |
| `SLO.md` contient une politique de budget chiffrée | |
| `DIAGNOSTICS.md` : 4 causes justes, chacune avec sa requête TraceQL | |

---

## Épreuve finale — Game day

C'est l'épreuve qui **confirme la maîtrise du cursus**. Elle se fait sur votre stack complète du Palier 3, trafic en cours depuis au moins 30 minutes.

### Règles

1. Vous jouez **5 manches** : 3 manches simples (`python chaos.py gameday`) puis 2 manches difficiles (`python chaos.py gameday --hard`, deux pannes simultanées, une bruyante et une discrète).
2. Après avoir lancé une manche, **vous ne regardez que votre observabilité** : Grafana, e-mails reçus dans Mailpit. Interdits : `chaos.py status` (bloqué de toute façon), `docker ps`, `docker logs`, lire le code ou le fichier `.gameday`.
3. Notez l'heure de lancement. Chronométrez : **détection** (première alerte reçue) et **diagnostic** (cause racine identifiée et prouvée).
4. Remédiation : quand vous avez identifié la cause, écrivez le post-mortem **puis** lancez `python chaos.py reveal` (qui révèle et remet tout d'aplomb). Pas de reveal avant d'avoir écrit votre conclusion.
5. Attendez que toutes les alertes soient résolues avant la manche suivante.

### Livrable : un post-mortem par manche

Dans `gameday/manche-N.md`, avec le modèle du module 11.3 du cours :
- résumé, impact chiffré (requêtes en erreur, budget d'erreur consommé — avec la requête),
- chronologie horodatée (lancement, première alerte, étapes du diagnostic, conclusion),
- **détection** : quelle alerte, quel délai ; quel signal aurait dû alerter plus tôt,
- **diagnostic** : le chemin suivi, avec les requêtes (PromQL, LogQL, TraceQL) et captures,
- cause racine, et 5 pourquoi,
- actions : au moins une action **« détecter »** (nouvelle alerte, dashboard) que vous **implémentez** avant la manche suivante.

### Grille d'évaluation

| Critère (par manche) | Points |
| --- | --- |
| La panne est détectée **par une alerte** (pas en regardant un dashboard par hasard) | 3 |
| Délai de détection ≤ 5 min (≤ 10 min pour une panne « discrète » comme une fuite mémoire) | 1 |
| Cause racine exacte (service, composant, mécanisme) | 3 |
| Cause prouvée par au moins deux signaux différents (ex. trace + logs, métrique + trace) | 1 |
| Diagnostic en moins de 15 min après la détection | 1 |
| Post-mortem complet, factuel, sans reproche, avec une action « détecter » implémentée | 1 |
| **Total par manche** | **10** |

Manches difficiles : les deux pannes doivent être trouvées ; la note porte sur 10 pour la paire (chaque panne manquée coûte 5 points).

### Réussite

**Maîtrise du cursus confirmée** si :
- **≥ 40 / 50** au total ;
- **au moins 4 pannes sur 5 manches** détectées par une alerte (critère 1) ;
- **aucune** manche sans cause racine exacte ;
- `verify.py --palier 3` toujours vert **après** le game day (vos corrections n'ont rien cassé).

En dessous : identifiez dans la grille ce qui a manqué (détection ? diagnostic ?), retournez au module correspondant, renforcez votre stack, et rejouez 5 nouvelles manches.

---

Terminé ? Comparez avec [solution/palier-3](solution/palier-3/) et lisez [solution/README.md](solution/README.md) : les écarts entre votre stack et la référence sont autant de sujets de discussion.
