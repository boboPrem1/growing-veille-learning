# Mesures — Marché sur son propre réseau (Palier 3)

**Méthode.** Sauf mention contraire, le client est `client` (TogoNet, le FAI de Lomé, 198.18.30.50). Il interroge `https://www.marche.test` (anycast 198.51.100.200) toutes les 0,2 à 1 s et journalise l'heure, le code HTTP et l'en-tête `X-Marche-Region`. Une **durée de bascule** va de l'incident provoqué à la première réponse servie par l'autre chemin. Chaque chiffre a été mesuré au moins deux fois ; on garde le pire.

## Routage : anycast, circuit, trou noir

| Incident | Mesure | Remarques |
| --- | --- | --- |
| Lomé ne sert plus (haproxy arrêté) : bascule **anycast** vers l'Europe | **2,7 s** | la sonde `anycast-sante` vérifie `/sante` chaque seconde ; 2 échecs → retrait du /26 |
| Lomé guérie : retour **anycast** | **1,9 s** | réannonce ; TogoNet préfère de nouveau l'IXP (préférence 200) |
| Même bascule par le **GSLB** (Palier 2, pour comparaison) | 3 s côté serveur, **jusqu'à 30 s de plus** côté client (TTL) | l'anycast ne dépend d'aucun cache DNS |
| **Circuit coupé**, avec BFD (300 ms × 3) | BFD : ≤ 0,9 s par construction (3 × 300 ms) ; **0 à 3 commandes en échec** selon les essais (une commande toutes les 0,5 s), puis tout passe par le VPN | les échecs, quand il y en a : des connexions TCP vers la base ouvertes juste avant la coupure, que l'application doit rouvrir |
| Circuit coupé, **sans** BFD (mesure de contrôle) | **180 s** de trou noir | le « hold timer » de BGP par défaut |
| Circuit rétabli | retour automatique, **0** échec | BFD remonte, BGP repréfère le circuit (préférence 150 > 50) |
| Aller-retour Lomé → base d'Europe | **111 ms** par le circuit ; 122 ms par Internet (tunnel) | le circuit : moins de sauts, pas de chiffrement WireGuard, pas de file d'attente partagée |
| **RTBH** sur 198.51.100.10 (`trou-noir.sh europe activer`) | le transitaire A jette le trafic en **moins de 6 s** ; 198.51.100.200 (www) **répond toujours** | l'adresse sacrifiée est injoignable pour TOUS — c'est le prix |

## Sécurité : Zero Trust, IDS/IPS

| Essai | Résultat |
| --- | --- |
| Application, port 8000, depuis le réseau | **fermé** (écoute sur 127.0.0.1) |
| Sidecar 8443 sans certificat client | **400** |
| Identité `lb` : `/` puis `/metrics` | **200**, puis **403** |
| Identité `supervision` : `/metrics` puis `/` | **200**, puis **403** |
| Identité **forgée** (bon nom `lb.svc.marche.test`, autre autorité) | **400** |
| Base, connexion non chiffrée | refusée (`no encryption`) |
| Base, TLS sans certificat client | refusée (`connection requires a valid client certificate`) |
| Durée de vie d'une identité de service | **24 h**, renouvelée par l'agent OpenBao avant expiration |
| Balayage de 200 ports depuis Internet | **détecté** (sid 9000001) ; alerte `IntrusionDetectee` au pager |
| SSH cherché depuis Internet | **détecté** (sid 9000002) |
| 10 requêtes DNS `ANY` (amplification) | **0 / 10** obtiennent une réponse ; les requêtes ordinaires, pendant ce temps : servies ; alerte `AttaqueBloquee` |
| Suricata arrêté (bypass) | le site **répond** : le choix de la disponibilité |
| Le scanner de conformité (console) | **aucune** alerte après exception étroite (cette source, cette signature) ; avant : une alerte toutes les 5 min |

## Performance : BBR contre CUBIC, SD-WAN, QoS

**Transitaire B** (le secours : 180 ms aller-retour, 0,5 % de pertes, 50 Mbit/s) — un téléchargement de 30 s :

| Contrôle de congestion de l'émetteur | Débit obtenu |
| --- | --- |
| CUBIC (défaut de Linux) | **4,56 Mbit/s** — chaque perte (aléatoire, pas de congestion) divise la fenêtre |
| BBR | **42,6 Mbit/s** (×9) — BBR mesure le débit et le RTT, il ne prend pas une perte pour un signal |

**Transitaire A** (sans perte, tampon profond) — un transfert massif, et la latence **des autres** :

| Émetteur | RTT des autres flux pendant le transfert |
| --- | --- |
| CUBIC | **580 ms** — il remplit le tampon jusqu'à la perte (« bufferbloat ») |
| BBR | **125 ms** — il vise le débit du goulot sans remplir la file |

**SD-WAN** (marque sur le port 8333 → table 200 → `wg0`) — 10 téléchargements du catalogue (400 Ko) par un client de Lomé, octets reçus par la passerelle de Lomé :

| Lien | Octets vus pendant le test |
| --- | --- |
| tunnel (Internet) | **4 154 Kio** (le catalogue, et le surcoût de WireGuard) |
| circuit | **162 Kio** (le reste, interactif : la base, le DNS, la supervision) |

Sonde `sdwan-sante` : tunnel en panne → le volumineux repasse par le circuit ; tunnel rétabli → il revient au tunnel (vérifié dans les deux sens).

QoS du Palier 2, toujours en place sur `wg0` : p95 de la poignée de main vers la base, sous charge, **123 ms** (122 ms au repos).

## Capacité (loi de Little)

`./capacite.sh` : des paliers de commandes/s depuis le client, 20 s chacun, 2 instances à Lomé (pool de 10 connexions à la base par instance ; une commande dure ~1 s : le paiement simulé et les allers-retours vers la base d'Europe par le circuit).

| Commandes/s demandées | Servies (toutes, au bout du compte) | p50 | p95 | Échecs |
| --- | --- | --- | --- | --- |
| 5 | 5 | 1,01 s | 1,06 s | 0 |
| 10 | 10 | 1,01 s | 1,07 s | 0 |
| 15 | 15 | 1,00 s | 1,06 s | 0 |
| 20 | 20 | 1,00 s | 1,05 s | 0 |
| 25 | 25 | **2,54 s** | **3,37 s** | 0 |
| 30 | 30 | **4,45 s** | **6,83 s** | 0 |

**Le coude : 20 commandes/s.** Jusque-là, le temps de réponse ne bouge pas ; au-delà, rien n'échoue, mais **tout attend** : les commandes font la queue devant le pool, et l'attente grandit tant que la charge dépasse le débit. (Maintenue plus longtemps, la file grandirait jusqu'aux délais d'expiration.) La loi de Little le prédisait : L = λ × W, soit λ max = 10 connexions ÷ 1 s = **10 commandes/s par instance**, ×2 instances = 20.

Pour aller plus haut : plus d'instances (l'autoscaler — mais chacune ouvre 10 connexions de plus à la base : la limite suivante est `max_connections`), OU un W plus court (le catalogue lu sur une réplique locale ; le paiement rendu asynchrone).

**Plan de capacité.** La cible de l'autoscaler (4 req/s par instance) laisse une marge ×2,5 au coude par instance : le temps de démarrer une instance avant que la file ne se forme.

## Coûts (FinOps)

Modèle aux prix fictifs (0,05 €/h par instance, 1,20 €/h de plateforme, 0,02 €/Go entre régions), calculé en continu par la supervision (`marche:cout_euros:par_commande`) :

| Poste | €/h |
| --- | --- |
| applications (4 instances) | 0,20 |
| plateforme | 1,20 |
| trafic inter-régions | ~0,00 (quelques Mo/h) |
| **Commandes** | 15,8 par heure (le générateur du lab) |
| **Coût complet d'une commande** | **0,0887 €** |

Lecture : 86 % du coût est fixe (la plateforme). Le levier n'est pas de réduire les instances, c'est l'activité : à 100 commandes/h, la commande tombe à ~0,014 €.

## Conformité

Surveillance continue (`cspm`, toutes les 5 min, identité d'audit en lecture seule) : **8 / 8 règles respectées**. Dérives réellement attrapées pendant la construction :
- le profil d'audit effacé par un redéploiement → `etat_versionne` et `sauvegardes_chiffrees` en échec (l'audit ne lisait plus rien) → alerte `NonConformite` ;
- un bucket rendu public à la main → `bucket_public` en échec au passage suivant.
