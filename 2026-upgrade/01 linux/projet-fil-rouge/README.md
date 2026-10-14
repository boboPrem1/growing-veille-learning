# 🧵 Projet fil rouge Linux — Marché, du premier compte à l'infrastructure reconstruite par Ansible

Un seul projet accompagne les trois étapes du cours Linux. Vous mettez en production **Marché**, une plateforme de commande en ligne (catalogue, commandes, paiements mobile money et carte, prix en francs CFA) : trois services Python et une base PostgreSQL. Le serveur unique du premier jour devient une infrastructure redondante, sauvegardée hors site et reconstructible en une commande.

Chaque palier se termine par un **correcteur automatique**, des **pannes injectées à l'aveugle** et des critères manuels. Le terminer seul, correcteur au vert, prouve la maîtrise du cours correspondant.

| Palier | Cours | Ce que vous livrez | Preuve |
| --- | --- | --- | --- |
| 🟢 [Palier 1 — Mettre un serveur en service](palier-1.md) | [01.md](../01.md) | web1 : comptes, permissions, services systemd, nginx, ufw, cron, sauvegardes ; enquête sur une journée de logs | `verifier.sh 1` (58 critères), 9 pannes |
| 🟡 [Palier 2 — Fiabiliser et durcir](palier-2.md) | [02.md](../02.md) | LVM, déploiements réversibles (`marchectl`), services confinés, timers, HTTPS, nftables + fail2ban, sauvegardes vérifiées ; diagnostic de performance | `verifier.sh 2` (122 critères), 9 pannes de plus |
| 🔴 [Palier 3 — Haute disponibilité, reconstruite par Ansible](palier-3.md) | [03.md](../03.md) | 6 machines : HAProxy + keepalived, 2 web, PostgreSQL dédié, sauvegardes restic chiffrées par WireGuard ; tout en Ansible | `verifier-infra.sh`, 8 pannes multi-machines, **sinistre** (RTO ≤ 30 min) |

## Contenu

```
projet-fil-rouge/
├── palier-1.md, palier-2.md, palier-3.md   les énoncés
├── app/                    le code de Marché (gateway, orders, payments, loadgen)
├── donnees/                la journée de logs du 14 septembre (enquête) et son générateur
├── lab/                    les machines : lxd/ (sur votre VPS) ou docker/ (sur votre PC)
├── outils/
│   ├── empaqueter.sh       produit une livraison : livraison/marche-X.Y.Z.tar.gz (+ .sha256), --cassee
│   ├── verifier.sh         correcteur des Paliers 1 et 2 (sur web1)
│   ├── panne.sh            pannes des Paliers 1 et 2 (sur web1)
│   ├── verifier-infra.sh   correcteur du Palier 3 (sur ctl)
│   ├── panne-infra.sh      pannes du Palier 3 (sur ctl)
│   └── sinistre.sh         l'épreuve finale : détruit db1 et web2 (sur l'hôte du lab)
└── solution/               les solutions de référence (à ouvrir APRÈS)
```

## Démarrer

1. Choisir son lab — [lab/README.md](lab/README.md) : sur votre VPS avec LXD (recommandé, l'hôte n'est pas modifié), ou sur votre PC avec Docker.
2. Lire [palier-1.md](palier-1.md), et s'y tenir : tout à la main, tout noté dans `NOTES.md`.
3. Ne regarder [solution/](solution/) qu'une fois le correcteur au vert — pour comparer, pas pour recopier.

## Règles du jeu

- **Mesurer, pas supposer.** Chaque affirmation se prouve par une commande (`sshd -T` plutôt que relire le fichier, `systemctl cat` plutôt que `cat`, `nft list ruleset`, `getfacl`…). Les correcteurs fonctionnent ainsi : ils mesurent, et plusieurs critères **provoquent** la situation qu'ils vérifient (un `SIGKILL`, un déploiement cassé, une bascule d'IP virtuelle).
- **Les pannes se diagnostiquent, elles ne s'annulent pas.** `panne.sh annuler` existe pour débloquer une situation ; chaque usage est une manche perdue.
- **Tout ce qui est écrit dans ce projet a été exécuté.** Les solutions ont été déroulées sur Ubuntu 24.04 (lab Docker), les correcteurs passés à 100 %, chaque panne injectée puis détectée. Les pièges listés en fin d'énoncé sont ceux **réellement** rencontrés en construisant le projet — plusieurs contredisaient ce que l'on lit couramment.
