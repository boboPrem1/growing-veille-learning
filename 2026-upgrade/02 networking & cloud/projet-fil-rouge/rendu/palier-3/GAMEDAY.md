# Game day — « L'IXP de Lomé disparaît » (30 septembre 2026, 21:47 UTC)

## Écrit AVANT

| | |
| --- | --- |
| **Scénario** | le serveur de routes de TGIX (l'IXP de Lomé) cesse de répondre, sans prévenir (`docker pause rs-ixp` : pas de fermeture propre des sessions BGP, comme une panne électrique) |
| **Hypothèse** | « Les clients de TogoNet, qui entrent par l'IXP, repassent par le transitaire A **en moins de 10 s**, et nous sommes prévenus par une alerte. » |
| **Rayon d'action** | les seuls clients de TogoNet (le `client` du lab) ; l'Europe et les autres transitaires ne sont pas touchés |
| **Condition d'arrêt** | 5 minutes d'échecs consécutifs pour la sonde client |
| **Retour arrière** | `docker unpause rs-ixp` |
| **Mesure** | une sonde sur `client` : une requête `https://www.marche.test/api/products` par seconde, code HTTP horodaté ; les journaux de FRR ; le pager |

## Ce qui s'est passé (mesuré)

| Heure (UTC) | Événement |
| --- | --- |
| 21:47:44 | l'IXP disparaît |
| 21:47:44 → 21:50:15 | **rien ne change** pour les clients : la sonde reçoit 200 à chaque seconde |
| 21:50:15 | la passerelle de Lomé déclare la session morte (*Hold Timer Expired*, **151 s** après la panne : le dernier keepalive reçu datait d'avant). TogoNet fait de même. Les routes apprises par l'IXP disparaissent ; le trafic passe par le **transitaire A** |
| 21:50:15 → 21:56:06 | toujours 200 à chaque seconde, par le transitaire |
| 21:56:06 | retour arrière (`docker unpause`) ; sessions rétablies à 21:56:15 (9 s) ; le trafic revient par l'IXP |

**Bilan de la sonde : 0 échec sur 306 requêtes.** **Aucune alerte** au pager.

## L'écart à l'hypothèse — ce qu'on a appris

1. **Le serveur de routes n'est pas sur le chemin des paquets.** TogoNet et Marché échangent leur trafic **directement** sur le réseau de l'IXP ; le serveur de routes ne fait que distribuer les routes. Sa panne ne coupe rien. Pendant 151 s, on route même avec des informations « périmées » qui restent justes. L'hypothèse « bascule en 10 s » supposait une panne qui n'existait pas.
2. **Une vraie panne du réseau de l'IXP (le commutateur, pas le serveur de routes) aurait coûté ~150 à 180 s de trou noir** : les mêmes temporisateurs BGP, mais cette fois avec des paquets jetés. C'est ce qu'on a mesuré sur le circuit sans BFD (180 s). → Demander à l'IXP s'il propose BFD sur son réseau, sinon réduire nos temporisateurs vers lui (`timers 10 30`).
3. **Pendant 6 minutes, tout le trafic de TogoNet est passé par le transitaire A, payé au volume, et personne ne l'a su.** Aucune alerte ne surveille les sessions BGP. La panne était sans effet pour les clients, mais pas pour la facture. Si elle avait duré tout un week-end, on l'aurait découverte sur la facture du mois.
4. **Le retour arrière n'avait pas été répété.** La boucle qui devait arrêter l'exercice après la bascule avait une condition fausse : l'IXP est resté en panne **8 minutes au lieu de 3 et demie**. Le retour arrière a été fait à la main. Un game day se prépare comme un changement en production, **retour arrière testé à blanc compris**.

## Actions

| # | Action | Pilier | Pour quand |
| --- | --- | --- | --- |
| 1 | Alerte « une session BGP de moins que la normale » (exporter l'état de FRR vers la supervision) | Excellence opérationnelle | 7 octobre 2026 |
| 2 | Métrique « part du trafic de Lomé par l'IXP » dans le tableau de bord FinOps : une chute = du transit payé | Coûts | 14 octobre 2026 |
| 3 | Demander BFD à TGIX ; à défaut, temporisateurs 10/30 vers l'IXP, puis rejouer ce game day en **coupant le réseau** de l'IXP (pas seulement son serveur de routes) | Fiabilité | 21 octobre 2026 |
| 4 | Script de game day avec arrêt et retour arrière **répétés à blanc** avant l'exercice | Excellence opérationnelle | avant le prochain game day |
