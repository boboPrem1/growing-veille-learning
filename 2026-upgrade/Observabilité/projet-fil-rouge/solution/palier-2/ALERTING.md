# Alerting — vérifications de la solution Palier 2

## Règles

```text
$ promtool check rules rules/recording.yml rules/alerts.yml
Checking rules/recording.yml
  SUCCESS: 10 rules found
Checking rules/alerts.yml
  SUCCESS: 12 rules found

$ promtool test rules alerts_test.yml
  SUCCESS
```

## Arbre de routage (`amtool config routes test`)

| Alerte (labels) | Destinataires |
| --- | --- |
| `severity=critical service=gateway` | `astreinte`, `equipe` |
| `severity=critical service=orders` | `astreinte`, `equipe-paiements` |
| `severity=warning service=gateway` | `equipe` |
| `severity=warning service=payments` | `equipe-paiements` |

Avant l'ajout de la route « attrape-tout » finale, le premier cas renvoyait **`astreinte` seul** : le receiver de la racine n'est jamais utilisé dès qu'une sous-route (même avec `continue: true`) a correspondu. C'est `amtool` qui l'a révélé.

## Test de bout en bout

`paiement-hors-ligne` + `tempete-de-logs` injectés simultanément ; après 4 min, e-mails reçus dans Mailpit :

```text
paiements@marche.local | [FIRING ×1] TauxErreursEleve — orders
astreinte@marche.local | 🚨 [FIRING ×1] TauxErreursEleve — gateway
astreinte@marche.local | 🚨 [FIRING ×1] TauxErreursEleve — orders
astreinte@marche.local | 🚨 [FIRING ×1] SondeEnEchec
equipe@marche.local    | [FIRING ×1] SondeEnEchec
equipe@marche.local    | [FIRING:1] TempeteDeLogs Alertes logs orders (warning)            ← Grafana Alerting
equipe@marche.local    | [FIRING:1] PaiementsInjoignablesDansLesLogs Alertes logs orders (critical)
```

`CibleInjoignable` ne s'est **pas** déclenchée pour payments : le conteneur arrêté a disparu du service discovery Docker, sa série `up` n'existe plus. La sonde blackbox (`SondeEnEchec`) a pris le relais.

Les résultats des 8 scénarios d'incident sont dans [INCIDENTS.md](INCIDENTS.md).
