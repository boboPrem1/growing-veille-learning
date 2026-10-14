# SLO de Marché

Spécification : [`slo/marche-gateway.yml`](slo/marche-gateway.yml) — règles générées par Sloth dans `prometheus/rules/slo-marche-gateway.yml` (vérifié à chaque CI). Dashboard : *Marché — SLO du parcours client* (`/d/marche-slo`, données Mimir).

## Les objectifs

| SLO | SLI (bons / valides) | Objectif | Fenêtre | Budget |
| --- | --- | --- | --- | --- |
| Disponibilité | Requêtes du gateway sans 5xx / toutes les requêtes du gateway hors `/healthz` | 99,5 % | 30 j glissants | 0,5 % ≈ **3 h 36 min** de panne totale par mois |
| Latence | Requêtes du gateway servies en ≤ 500 ms / toutes (hors `/healthz`) | 99 % | 30 j glissants | 1 % ≈ **7 h 12 min** « lentes » par mois |

## Pourquoi ces chiffres

- **Mesuré au gateway** : c'est la porte d'entrée des clients ; une panne de payments ou de la base s'y voit.
- **Les 4xx comptent comme bonnes** : 402 (refus métier), 404, 422 (requêtes invalides du client) ne sont pas des défaillances du service.
- **99,5 % et pas 99,9 %** : une seule instance par service et une base unique, pas d'astreinte 24/7 ; 99,9 % (43 min/mois) serait promis sans les moyens de le tenir.
- **500 ms** : le parcours de commande appelle un prestataire de paiement externe (~150 ms en mobile money) ; 500 ms laisse une marge et reste perçu comme fluide. C'est aussi une frontière de bucket de l'histogramme, donc un SLI **exact** (pas d'interpolation).

## Alertes

Générées par Sloth (méthode multi-fenêtres du *SRE Workbook*) :

| Alerte | Condition | Sévérité | Réaction |
| --- | --- | --- | --- |
| page | burn rate ≥ 14,4 (1 h **et** 5 min) ou ≥ 6 (6 h **et** 30 min) | critical | Incident immédiat |
| ticket | burn rate ≥ 3 (1 j **et** 2 h) ou ≥ 1 (3 j **et** 6 h) | warning | Correction planifiée dans la journée |

Mesuré pendant l'incident `base-lente` (800 ms de SQL par commande) : `SLOLatenceGateway` critical en ~4 min.

## Politique de budget d'erreur

| Budget restant (30 j) | Décision |
| --- | --- |
| > 50 % | Déploiements libres, expérimentations autorisées |
| 25 – 50 % | Déploiements en heures ouvrées uniquement, avec rollback testé |
| 0 – 25 % | **Gel** des fonctionnalités : seules les corrections de fiabilité et de sécurité sont déployées ; revue hebdomadaire |
| 0 % (SLO violé) | Post-mortem obligatoire ; le prochain sprint est consacré à la fiabilité |

Revue mensuelle des SLO avec l'équipe produit : un objectif jamais menacé est peut-être trop laxiste ; un objectif violé chaque mois est irréaliste ou révèle un sous-investissement.
