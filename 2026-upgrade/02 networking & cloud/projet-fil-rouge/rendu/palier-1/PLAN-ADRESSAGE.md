# Plan d'adressage — région « Europe » de Marché

## Principes

- **Un VPC = un bloc privé** RFC 1918 assez large pour grandir sans renuméroter : `10.0.0.0/16` (65 536 adresses). La région suivante prendra `10.1.0.0/16` : **jamais de chevauchement** entre VPC, sinon aucune interconnexion (peering, VPN) ne sera possible plus tard.
- **Un sous-réseau par rôle** (public / applications / données), chacun en `/24` : 254 hôtes utilisables, un découpage lisible (le 3ᵉ octet = le rôle). C'est volontairement large : en cloud, un sous-réseau trop petit est une migration à venir.
- **Adresses fixes pour les serveurs**, choisies pour être mémorisables (`.1` passerelle, `.10`+ services).
- **IPv6 partout** : un préfixe ULA `/48` pour le VPC, un `/64` par sous-réseau (le seul masque qui permet le SLAAC). En production, les 40 bits de l'identifiant ULA se tirent **au hasard** (RFC 4193) ; celui du lab, `4d41:5243` (« MARC » en ASCII), est choisi pour être reconnaissable.

## Sous-réseaux

| Rôle | VLAN | IPv4 | Passerelle | Broadcast | Hôtes utilisables | IPv6 |
| --- | --- | --- | --- | --- | --- | --- |
| Public (lb, ns1) | — (lien dédié `pub`) | `10.0.1.0/24` | `10.0.1.1` | `10.0.1.255` | 254 | `fd00:4d41:5243:1::/64` |
| Applications | **20** | `10.0.2.0/24` | `10.0.2.1` | `10.0.2.255` | 254 | `fd00:4d41:5243:20::/64` |
| Données | **30** | `10.0.3.0/24` | `10.0.3.1` | `10.0.3.255` | 254 | `fd00:4d41:5243:30::/64` |
| VPN d'administration | — (`wg0`) | `10.99.0.0/24` | `10.99.0.1` | — | — | — |
| *Réservé* (région suivante) | | `10.1.0.0/16` | | | | |

Le sous-réseau VPN est **hors** du VPC (`10.99/24`) : on le reconnaît d'un coup d'œil dans les journaux et les règles de pare-feu (« 10.99 = un humain par le VPN »).

## Hôtes

| Machine | Interface | IPv4 | IPv6 |
| --- | --- | --- | --- |
| passerelle | `internet` / `pub` / `baie.20` / `baie.30` / `wg0` | `203.0.113.10` / `10.0.1.1` / `10.0.2.1` / `10.0.3.1` / `10.99.0.1` | `…:1::1`, `…:20::1`, `…:30::1` |
| lb | `pub` | `10.0.1.10` | `fd00:4d41:5243:1::10` |
| ns1 | `pub` | `10.0.1.53` | `fd00:4d41:5243:1::53` |
| app1, app2 | `baie.20` | `10.0.2.11`, `10.0.2.12` | `…:20::11`, `…:20::12` (+ SLAAC) |
| db | `baie.30` | `10.0.3.10` | `fd00:4d41:5243:30::10` (+ SLAAC) |
| stockage | `baie.30` | `10.0.3.20` | (IPv4 seulement : pas d'AAAA publié) |
| console | `wg0` | `10.99.0.2` | — |

Adresses **publiques** (attribuées par le « fournisseur ») : `203.0.113.10` (passerelle, porte le site et le DNS par DNAT), `192.0.2.80` (nœud CDN de Lomé).

## Le lien « baie » : un trunk

`app1`, `app2`, `db` et `stockage` sont branchés sur le même commutateur, mais dans deux VLAN : leurs trames portent l'étiquette 802.1Q 20 ou 30. Deux machines de VLAN différents ne se voient pas (pas d'ARP entre elles) : `app1 → db` passe par la passerelle (routage inter-VLAN, « router on a stick »), où l'ACL du sous-réseau données s'applique.

## Et si… (VLSM)

Si les données n'avaient besoin que de 10 hôtes, un `/28` (14 utilisables) suffirait : `10.0.3.0/28`. On garde un `/24` ici, parce qu'en cloud les adresses privées ne coûtent rien et qu'agrandir un sous-réseau oblige souvent à le recréer.
