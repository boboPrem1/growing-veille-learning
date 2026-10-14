# 🧵 Projet fil rouge Networking & Cloud — Marché, du câble au réseau mondial

Un seul projet accompagne les trois étapes du cours Networking & Cloud. Vous construisez l'infrastructure réseau et cloud de **Marché** — la plateforme de commande en ligne des cours Linux et Observabilité (catalogue, commandes, paiements, prix en francs CFA) — pour des clients à **Lomé**, depuis une région hébergée en Europe.

Tout se passe dans un **lab local** (Docker) qui reproduit un Internet complet : une racine DNS et un registre de domaines, un opérateur qui filtre les adresses usurpées et privées, un câble sous-marin de 120 ms, et vos propres machines, livrées nues. Aucun compte cloud n'est nécessaire : le stockage objet parle l'API S3 et IAM d'AWS, Terraform pilote l'infrastructure, et chaque pièce a sa correspondance chez AWS, GCP et Azure.

Chaque palier se termine par un **correcteur automatique** qui mesure (et provoque) plutôt que de lire vos fichiers, des **pannes injectées à l'aveugle**, et des critères manuels. Le terminer seul, correcteur au vert, prouve la maîtrise du cours correspondant.

| Palier | Cours | Ce que vous construisez | Preuve |
| --- | --- | --- | --- |
| 🟢 [Palier 1 — Câbler le réseau, du câble au navigateur](palier-1.md) | [01.md](../01.md) | Un VPC à la main : VLAN, routage, IPv6, NAT, security groups et ACL sans état, DNS faisant autorité en split-horizon, PKI et TLS, répartiteur L7, CDN, VPN, stockage objet et IAM | `verifier.sh 1` (67 critères), 12 pannes |
| 🟡 [Palier 2 — Tout en code, deux régions](palier-2.md) | [02.md](../02.md) | Terraform en trois couches (état distant verrouillé, module d'instance immuable, politique de plan), une seconde région en VLSM et un VPN site à site, DNS à deux vues et GSLB en santé L7, secrets temporaires (OpenBao), base répliquée entre continents et sauvegardée chiffrée (restauration à la seconde), flotte bleu/vert découverte par DNS, pipeline sans interruption, auto-scaling, supervision hors région, QoS du lien intercontinental, perte de région mesurée (RTO/RPO) | `verifier.sh 2` (47 critères), 9 pannes, perte de région |
| 🔴 [Palier 3 — À l'échelle d'Internet](palier-3.md) | [03.md](../03.md) | Votre propre AS (64500) : BGP avec deux transitaires et un IXP, politiques d'entrée et de sortie, anycast conditionné à la santé, circuit dédié avec BFD et VPN de secours, trou noir à distance (RTBH) ; Zero Trust (identités de service de 24 h, mTLS partout) et IPS en ligne ; BBR et SD-WAN ; landing zone multi-comptes et conformité continue ; SLO et budget d'erreur, capacité (loi de Little), coût par commande, revue Well-Architected | `verifier.sh 3` (108 critères, le Palier 2 rejoué), 8 pannes, **game day** |

## Contenu

```
projet-fil-rouge/
├── palier-1.md, palier-2.md, palier-3.md   les énoncés
├── app/                  le code de Marché (préinstallé dans les machines du lab)
├── lab/                  le lab Docker : l'Internet fourni + vos machines — lab/README.md
├── outils/
│   ├── verifier.sh       le correcteur (sur l'hôte du lab)
│   ├── panne.sh          les pannes : liste, entraînement, tirage à l'aveugle
│   └── attaque.sh        (Palier 3) des attaques depuis Internet, pour éprouver l'IDS/IPS
├── rendu/                vos livrables (plan d'adressage, captures, incidents…) — visible depuis la console
└── solution/             les solutions de référence (à ouvrir APRÈS)
```

## Démarrer

1. Lancer le lab — [lab/README.md](lab/README.md) : `cd lab/docker && ./lab.sh up 1`.
2. Lire [palier-1.md](palier-1.md), et s'y tenir : dans l'ordre, tout à la main, tout ce que vous faites doit survivre à un redémarrage.
3. Ne regarder [solution/](solution/) qu'une fois le correcteur au vert — pour comparer, pas pour recopier.

## Règles du jeu

- **Mesurer, pas supposer.** Un réseau se diagnostique couche par couche, par la mesure : `ip`, `ping`, `traceroute -I`, `tracepath`, `tcpdump`, `dig +trace`, `openssl s_client`, `curl -w`, les compteurs du pare-feu. Le correcteur fonctionne ainsi : il se place tour à tour chez un client de Lomé, dans une application, sur la console, et **provoque** ce qu'il vérifie (connexions interdites, serveur arrêté, redémarrages, objets déposés avec les clés de l'application).
- **Les pannes se diagnostiquent, elles ne s'annulent pas.** `panne.sh annuler` existe pour débloquer une situation ; chaque usage est une manche perdue. Et redémarrer une machine n'est pas diagnostiquer.
- **Tout ce qui est écrit dans ce projet a été exécuté.** Les solutions ont été déroulées de zéro sur le lab, les correcteurs passés à 100 %, chaque panne injectée, détectée, puis annulée. Les pièges listés en fin d'énoncé sont ceux **réellement** rencontrés en construisant le projet.
