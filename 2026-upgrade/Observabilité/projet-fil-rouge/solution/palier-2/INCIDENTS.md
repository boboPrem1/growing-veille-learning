# Exercices d'incident — mesures sur la solution Palier 2

Les 8 scénarios ont été rejoués automatiquement le 28/09/2026 sur une stack Palier 2 fraîche (volumes vidés), trafic ~5 req/s. Pour chacun : retour au calme (aucune alerte active), injection, observation pendant 10 à 30 min, relevé des alertes (Prometheus **et** Grafana) avec leur délai de passage en *firing*, et des e-mails reçus dans Mailpit.

## Résultats

| Scénario | Première alerte (délai) | Autres alertes (délai) | Détecté |
| --- | --- | --- | --- |
| `paiement-instable` | `TauxErreursEleve` payments, orders (3,0 min) | `TauxErreursEleve` gateway (4,0) | ✅ |
| `paiement-lent` | `LatenceP95Elevee` orders, payments (4,5 min) | `LatenceP95Elevee` gateway (5,0) | ✅ |
| `paiement-hors-ligne` | `SondeEnEchec` payments + Grafana `PaiementsInjoignablesDansLesLogs` (1,5 min) | `TauxErreursEleve` orders (3,5), gateway (4,0) ; `LatenceP95Elevee` orders (4,5), gateway (5,0) | ✅ |
| `base-hors-ligne` | `PostgresIndisponible`, `SondeEnEchec` orders + postgres:5432 (1,5 min) | `CibleInjoignable` orders (1,8) ; `TauxErreursEleve` gateway (4,0) ; `LatenceP95Elevee` gateway (5,0) ; `AucuneCommandePayee` (6,0) | ✅ |
| `base-lente` | `LatenceP95Elevee` orders (5,5 min) | `LatenceP95Elevee` gateway (6,5) | ✅ |
| `cpu-sature` | `ConteneurCPUSature` marche-orders (9,6 min) | — | ✅ (lent) |
| `tempete-de-logs` | Grafana `TempeteDeLogs` orders (3,0 min) | — | ✅ |
| `fuite-memoire` | `ConteneurFuiteMemoire` marche-gateway (9,0 min) | — | ✅ |

**8 / 8 détectés par une alerte.**

## E-mails reçus (extraits)

`paiement-instable` — routage conforme (critical → astreinte + équipe ; orders/payments → équipe paiements) :

```text
astreinte@marche.local | 🚨 [FIRING ×1] TauxErreursEleve — gateway
astreinte@marche.local | 🚨 [FIRING ×1] TauxErreursEleve — orders
astreinte@marche.local | 🚨 [FIRING ×1] TauxErreursEleve — payments
equipe@marche.local    | [FIRING ×1] TauxErreursEleve — gateway
paiements@marche.local | [FIRING ×1] TauxErreursEleve — orders
paiements@marche.local | [FIRING ×1] TauxErreursEleve — payments
```

`base-hors-ligne` — les inhibitions ont fonctionné : `TauxErreursEleve` (gateway) et `AucuneCommandePayee` étaient *firing* dans Prometheus, mais **aucun** e-mail n'est parti pour elles (masquées par `PostgresIndisponible`) :

```text
astreinte@marche.local | 🚨 [FIRING ×1] PostgresIndisponible — postgres
astreinte@marche.local | 🚨 [FIRING ×2] SondeEnEchec
astreinte@marche.local | 🚨 [FIRING ×1] CibleInjoignable — orders
equipe@marche.local    | [FIRING ×1] PostgresIndisponible — postgres
equipe@marche.local    | [FIRING ×2] SondeEnEchec
equipe@marche.local    | [FIRING ×1] LatenceP95Elevee — gateway
paiements@marche.local | [FIRING ×1] CibleInjoignable — orders
```

## Réponses aux questions du cahier des charges

**1. `CibleInjoignable` pour payments arrêté ?** Non. Payments est découvert par le service discovery Docker : arrêté, il **disparaît** de la liste des cibles, sa série `up` cesse d'exister (elle ne vaut pas 0). Au Palier 1, avec une configuration statique, la cible restait déclarée et `up` valait 0. Ce qui a sauvé la détection : la **sonde blackbox** (1,5 min) et l'alerte Grafana sur les **logs** d'orders.

**2. Combien d'e-mails pour `base-hors-ligne`, et les inhibitions ?** 7 e-mails, sans les alertes inhibées (voir ci-dessus). Un effet inattendu : `CibleInjoignable` sur **orders**, qui n'était pas en panne. Quand la base est tombée, les requêtes d'orders restaient bloquées en attente d'une connexion ; elles ont occupé tous les threads, y compris celui qui sert `/metrics`, et le scrape a expiré. Une métrique qui ne peut plus être lue est, elle aussi, un symptôme.

**3. Améliorations apportées après le banc :**
- **Label `service` sur les sondes blackbox.** `paiement-hors-ligne` a produit 9 e-mails. L'inhibition « une sonde en échec masque les erreurs et la latence du même service » (`equal: [service]`) ne pouvait **jamais** s'appliquer, car les séries `probe_success` n'avaient pas de label `service`. Correctif dans `prometheus.yml` : une règle de relabeling qui extrait le nom du service de l'URL sondée (vérifié : `probe_success{service="payments"}`). Il n'a pas été re-mesuré sur le banc.
- **Détection lente de `cpu-sature` (9,6 min)** : 5 min de fenêtre `rate` + `for: 5m`. Pistes : fenêtre `[2m]` et `for: 3m`, ou alerter sur le **symptôme** (latence d'orders), qui ne s'est pas dégradée au-delà d'1 s ici. Cela montre qu'un CPU saturé ne gêne pas forcément les clients, donc qu'une alerte *warning* lente est acceptable.
- **`fuite-memoire` en 9 min** : conforme à l'objectif (≤ 10 min pour une panne discrète), grâce à la garde d'ancienneté qui élimine les faux positifs au démarrage.
