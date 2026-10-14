# Le lab du projet fil rouge Networking & Cloud

Un « Internet » et une région cloud en miniature, sur votre PC, avec Docker : 12 machines au Palier 1. Chaque machine est un conteneur **privilégié** qui exécute systemd — elle se comporte comme un serveur Ubuntu 24.04 (services, pare-feu, VLAN, WireGuard, `tc`…). Testé avec Docker Desktop (Windows 11 / WSL2).

> Pas de compte cloud nécessaire, et **rien d'exposé sur votre vrai réseau** : tous les réseaux du lab sont isolés ; seule la dorsale sort vers Internet, par NAT.

## Démarrer

```bash
cd lab/docker
./lab.sh up 1          # construit l'image (≈ 10 min la première fois), démarre les 12 machines
./lab.sh etat          # machine, état systemd, adresses
./lab.sh shell app1    # un shell root (≈ la console série d'un fournisseur)
./lab.sh down          # tout arrêter (les machines et leurs données sont conservées)
```

Ressources : ≈ 4 Go de mémoire au Palier 1. L'image (≈ 2 Go) contient **tous** les logiciels des trois paliers, installés mais **arrêtés et désactivés** : `systemctl enable --now` est votre travail.

## Ce qui est fourni, ce qui est à vous

| Machine | Réseau | Rôle |
| --- | --- | --- |
| `backbone` | `lome` 192.0.2.1, `europe` 203.0.113.1, `sortie` | **Fournie.** La dorsale de l'Internet du lab : ~60 ms dans chaque sens entre Lomé et l'Europe (un câble sous-marin), filtrage BCP 38 (adresses usurpées) et RFC 1918 (adresses privées), sortie vers le vrai Internet par NAT. |
| `dns-racine` | `lome` 192.0.2.53 / .54 / .35 | **Fournie.** La racine DNS « . », le TLD « test. » et son **registre**, le résolveur récursif du FAI de Lomé. |
| `client`, `console` | `lome` .50, .60 | **Fournies** (route et résolveur du FAI). Vos clients ; votre poste d'administration. |
| `edge` | `lome` .80 | À vous : le nœud CDN de Lomé. |
| `passerelle` | `europe` 203.0.113.10, `pub` 10.0.1.1, `baie` | À vous : le routeur du VPC. |
| `lb`, `ns1` | `pub` 10.0.1.10, 10.0.1.53 | À vous. |
| `app1`, `app2`, `db`, `stockage` | `baie` (trunk) | À vous : dans les VLAN 20 et 30. |

Les **noms d'interface** sont parlants (`internet`, `pub`, `baie`, `lome`…) et stables. Une interface `gre0`/`erspan0` peut apparaître : le noyau (partagé) les crée dans chaque machine dès que le module GRE est chargé ; ignorez-les.

Le **registre** de `.test` : `./lab.sh registre voir`, `./lab.sh registre deleguer marche.test ns1.marche.test 203.0.113.10`.

Vos rendus vont dans `rendu/` à la racine du projet, visible aussi depuis la console dans `/srv/rendu`.

## Paliers 2 et 3 : un fournisseur de cloud

```bash
./lab.sh passer-palier-2   # supprime vos 8 machines du Palier 1 et leurs réseaux (la console et sa PKI restent)
./lab.sh up 2              # l'Internet, la console, et le S3 managé du fournisseur
./lab.sh identifiants      # les clés de VOTRE compte S3 chez le fournisseur
```

- **Vos machines, c'est votre Terraform** : depuis la console, le fournisseur `kreuzwerker/docker` crée des conteneurs de la même image, sur des réseaux `macvlan` que vous déclarez aussi. Les fournisseurs Terraform sont dans un **miroir local** (`terraform init` sans Internet).
- **Le S3 managé du fournisseur** : `https://s3.fournisseur.test` (203.0.113.30), API S3 **et** IAM, certificat signé par l'AC publique du lab (dans le magasin de toutes les machines). L'AWS CLI ne lit pas ce magasin : `AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`.
- **Le câble a une capacité** : 20 Mbit/s par sens entre Lomé et l'Europe, avec un tampon de 1 200 paquets chez l'opérateur (≈ 0,7 s plein). Réglable : `CAPACITE=50mbit` dans l'environnement du backbone.
- **`~ 22 machines`** au Palier 2 : prévoir ≈ 8 Go de mémoire pour Docker.

## Palier 3 : un Internet à plusieurs opérateurs

```bash
./lab.sh up 3              # ajoute trois opérateurs et un circuit dédié ; vos machines ne sont pas touchées
```

| Machine | Opérateur | Réseaux (adresse) | Ce qu'il fait |
| --- | --- | --- | --- |
| `backbone` | TransAtlantique, AS 65010 (transitaire A) | `europe` 203.0.113.1, `lome` 192.0.2.1, `interco` 198.18.0.1 | celui des Paliers 1-2, qui parle désormais BGP (FRR). Accepte de Marché (AS 64500) ses préfixes de `198.51.100.0/24` jusqu'au /26, et un /32 marqué `65010:666` (trou noir : routé vers une interface de rejet) |
| `transit-b` | OuestNet, AS 65020 (transitaire B) | `europe-b` 198.18.2.1, `lome-b` 198.18.3.1, `interco` 198.18.0.2 | un transitaire lent et qui perd des paquets : +90 ms, 0,5 % de pertes, 50 Mbit/s |
| `rs-ixp` | TGIX, AS 65100 | `ixp` 198.18.1.254 | le serveur de routes de l'IXP de Lomé (il ne s'insère pas dans le chemin d'AS) |
| `fai-lome` | TogoNet, AS 65030 | `lome` 192.0.2.2, `ixp` 198.18.1.30, `togonet` 198.18.30.1 | le FAI des clients de Lomé : préfère l'IXP (200) au transit (100) |
| `circuit` | l'opérateur du circuit | `fibre-europe` 198.18.9.1, `fibre-lome` 198.18.9.9 | un circuit dédié Europe ↔ Lomé : 55 ms, 100 Mbit/s, non chiffré (routage par interface d'entrée, comme un lien de niveau 2) |

- Le **`client`** déménage chez TogoNet (`togonet` 198.18.30.50, route par défaut via `fai-lome`) : il atteint Marché par l'IXP ou par le transitaire A, selon ce que **vous** annoncez. `lab.sh up 3` le branche sur ce réseau sans le recréer (son magasin de certificats reste).
- Les fournisseurs gardent ce que vous leur envoyez **avant** leurs filtres (`soft-reconfiguration inbound`) : `docker exec backbone vtysh -c 'show ip bgp neighbors 203.0.113.10 received-routes'` montre votre annonce, fuites comprises.
- Le câble « océan » de la dorsale ne retarde que le trafic qui le **traverse** (marqué par interface d'entrée) : les sessions BGP locales ne sont pas ralenties.
- `../../outils/attaque.sh balayage|ssh|dns-any <adresse>` : des attaques lancées depuis le client, pour éprouver votre IDS/IPS.

## Pièges du lab Docker (vérifiés)

- 🪤 **Les réseaux sont des `macvlan` isolés, pas des `bridge` internes.** Sur un réseau `bridge` « internal », Docker installe dans sa VM une règle qui jette tout paquet dont la **destination sort du sous-réseau** — autrement dit, tout trafic *routé* par l'une de vos machines. La première version du lab en est morte (`iifname "br-…" ip daddr != 192.0.2.0/24 drop`, 12 paquets au compteur). En `macvlan`, les trames vont d'une machine à l'autre sans traverser le pare-feu de la VM : routage, VLAN 802.1Q, IPv6, `tc netem`, tout passe.
- 🪤 **Une machine redémarrée change d'adresse MAC.** Quelques secondes d'échecs, le temps que les voisins (ARP, NDP) rafraîchissent leur cache.
- 🪤 **`/etc/resolv.conf` est un montage Docker** : `sed -i` échoue (`Device or resource busy`) ; réécrivez-le en place.
- 🪤 **Clés propres à chaque machine** : générées pendant la construction de l'image, les clés d'hôte SSH et le certificat « snakeoil » seraient identiques partout ; `lab-cles.service` les crée au premier démarrage de chaque machine.
- ⚠️ **Le noyau est celui de Docker, partagé** : ne poussez jamais de `sysctl kernel.*` depuis une machine. Les réglages `net.*` (routage, `rp_filter`, algorithme de congestion TCP…) sont propres à chaque machine.
