# Runbook — Marché, Palier 3

Quatre procédures d'incident propres au Palier 3. Celles du Palier 2 (restaurer, basculer de région, revenir) restent valables : voir `rendu/palier-2/RUNBOOK.md`. Les commandes « sur une passerelle » se lancent par le VPN depuis la console (`ssh ubuntu@10.0.1.1` pour l'Europe, `ssh ubuntu@10.1.0.1` pour Lomé, puis `sudo -i`). Dans le lab, `docker exec <machine>` fait la même chose.

## 1. Sous attaque volumétrique (DDoS) : le trou noir à distance (RTBH)

> Symptômes : le lien d'une région sature (le trafic légitime n'arrive plus), une adresse publique reçoit des centaines de fois son trafic habituel. On ne filtre pas un DDoS chez soi : quand il arrive, le lien est déjà plein. On demande au transitaire de le jeter **chez lui**.

| # | Action | Pourquoi |
| --- | --- | --- |
| 1 | Identifier l'adresse visée : `nft list ruleset` (compteurs), `conntrack -L \| awk …`, ou le taux d'erreurs par adresse dans la supervision | RTBH sacrifie UNE adresse : il faut la bonne |
| 2 | Si c'est l'adresse d'un service anycast (www .200, dns .253) : **ne pas** la mettre au trou noir — retirer d'abord l'annonce anycast de la région attaquée (`systemctl stop anycast-sante`, puis `vtysh -c 'conf t' -c 'no ip route 198.51.100.192/26 blackhole'` : sans son ancre, le /26 n'est plus annoncé) : l'autre région absorbe les clients | le trou noir couperait www **pour tout le monde** ; l'anycast déplace les clients légitimes (et l'attaque se répartit) |
| 3 | Pour une adresse unicast (PI .10, .100) : `./trou-noir.sh <europe\|lome> activer <adresse>` | annonce `<adresse>/32` avec la communauté `65010:666` (et `no-export`) ; le transitaire A la route vers son interface de rejet |
| 4 | Vérifier chez le transitaire : `show ip bgp neighbors <nous> advertised-routes` doit montrer le /32 ; depuis Internet, l'adresse ne répond plus, **les autres oui** | un /32 filtré par une liste de préfixes trop stricte ne partirait pas (l'exception `TROU-NOIR` est placée AVANT le refus final) |
| 5 | Basculer ce que servait cette adresse (DNS : autre adresse, TTL court) | l'attaquant « a gagné » sur cette adresse : on continue ailleurs |
| 6 | Quand l'attaque cesse : `./trou-noir.sh <région> lever <adresse>` | l'adresse redevient joignable en quelques secondes |

**Limites.** Le transitaire B ne connaît pas notre communauté : pendant un RTBH, ne comptez pas sur lui. Un DDoS plus large que tous nos liens réunis relève d'un service de nettoyage (scrubbing) ou d'un CDN en frontal.

## 2. Le circuit dédié est coupé

> Rien à faire pour que le service continue : BFD déclare le circuit mort en 0,9 s, BGP bascule sur le VPN (préférence 50). Mesuré : 3 commandes en échec, puis tout passe par Internet (voir MESURES.md). Ce qui reste à faire : **le savoir, le mesurer, le réparer**.

| # | Action | Pourquoi |
| --- | --- | --- |
| 1 | `vtysh -c 'show bfd peers brief'` sur les deux passerelles : `down` | confirmer que c'est le circuit (et pas BGP, ou le pare-feu) |
| 2 | `ip route get 10.0.3.10` sur la passerelle de Lomé : `dev wg0` | le secours est actif |
| 3 | `wg show wg0 endpoints` + `ip route get <extrémité>` : l'extrémité passe **par le transitaire**, pas par le circuit | si le tunnel s'était « promené » sur le circuit (WireGuard suit l'adresse des derniers paquets reçus), il serait tombé avec lui |
| 4 | Surveiller la file sur `wg0` (QoS HTB + fq_codel toujours en place) et le p95 des commandes | tout le trafic inter-régions tient désormais dans 18 Mbit/s |
| 5 | Ouvrir un ticket chez l'opérateur du circuit, avec l'heure de la coupure (`journalctl -u frr \| grep -i bfd`) | c'est le SLA du circuit qui s'applique |
| 6 | Au retour : BFD `up`, puis `ip route get 10.0.3.10` → `dev fibre` | le retour est automatique (préférence 150 > 50) — à vérifier, pas à faire |

**Si BFD manque** (panne des démons, profil supprimé) : BGP attendrait la fin de son *hold timer* — 180 s de trou noir mesurés. L'alerte à créer : « une session BGP de moins que la normale ».

## 3. Une identité de service compromise (clé privée volée sur une machine)

> Ce qu'un voleur peut faire : se présenter comme ce service (ex. `lb.svc.marche.test` → appeler l'API de toutes les instances ; `app.svc.marche.test` → se connecter à la base avec un compte temporaire). Jusqu'à quand : **l'expiration du certificat, 24 h au plus**. C'est le premier rempart des identités courtes.

| # | Action | Pourquoi |
| --- | --- | --- |
| 1 | Isoler la machine (pare-feu de sa passerelle, ou l'éteindre) | elle ne doit plus rien renouveler |
| 2 | Relever le numéro de série : `openssl x509 -in /etc/identite/service.crt -noout -serial` | pour révoquer CE certificat |
| 3 | `bao write pki-services/revoke serial_number=<série>` | le certificat entre dans la CRL de l'AC des services |
| 4 | Remplacer la machine : `terraform apply -replace='module.machine["<nom>"].docker_container.this' -replace='tls_locally_signed_cert.cert["<nom>"]'` (couche `regions`) | nouvelle machine, **nouveau certificat de machine** (celui avec lequel elle s'authentifie auprès d'OpenBao), nouvelle identité de service |
| 5 | `bao lease revoke -prefix base/creds/app` si c'était une application | les comptes temporaires de la base qu'elle détenait meurent tout de suite, sessions comprises |
| 6 | Chercher ce que l'identité a fait : journaux nginx des sidecars (`$ssl_client_s_dn`), `pg_stat_activity`, journaux d'audit d'OpenBao | l'étendue des dégâts |

**Limite connue, à corriger (voir REVUE.md).** Les sidecars nginx et HAProxy **ne consultent pas la CRL** : la révocation de l'étape 3 ne bloque pas un certificat déjà émis ; seule son expiration le fait. Tant que ce n'est pas corrigé, l'étape 1 (isoler) est la seule coupure immédiate — et une identité volée **ailleurs** que sur la machine reste valable jusqu'à 24 h.

**Et même l'expiration n'est pas immédiate** : les répartiteurs **reprennent** leurs sessions TLS, et une session reprise ne revérifie pas le certificat. Mesuré : une identité expirée est restée en service 3 min 20, jusqu'à l'expiration des sessions de nginx (`ssl_session_timeout`, 5 min). Pour couper une identité tout de suite, **recharger le service qui l'accepte** (`systemctl reload nginx` sur les instances) : ses clés de session changent, les sessions en cours ne se reprennent plus (mesuré : 3 s après le rechargement, l'identité expirée était refusée).

## 4. L'IDS/IPS : trier une alerte, réagir à une panne de Suricata

**Une alerte arrive** (`IntrusionDetectee` : mineure, `AttaqueBloquee` : majeure) :

| # | Action | Pourquoi |
| --- | --- | --- |
| 1 | Sur la passerelle de la région : `jq -c 'select(.event_type == "alert") \| [.timestamp, .src_ip, .dest_ip, .dest_port, .alert.signature_id, .alert.action]' /var/log/suricata/eve.json \| tail` | qui, vers quoi, quelle signature, alerté ou bloqué |
| 2 | La source est-elle connue ? (la console, un scanner de l'équipe sécurité, un partenaire) | un faux positif répété use l'attention |
| 3 | Faux positif légitime → une exception **étroite** dans `/etc/suricata/threshold.config` : `suppress gen_id 1, sig_id <sid>, track by_src, ip <source>`, puis `systemctl restart suricata` — et la documenter (qui, pourquoi) | cette source, cette signature ; jamais « désactiver la règle » |
| 4 | Vraie attaque, répétée, d'une source : la bloquer à la passerelle (`nft insert rule inet filtre transit ip saddr <source> drop`, et de même dans `entree`) ; volumétrique : procédure 1 | l'IPS bloque ce qui est sans ambiguïté ; le reste est une décision humaine |

**Suricata est tombé** : le trafic **passe** (`queue … bypass`) — on a choisi la disponibilité. On perd la détection et le blocage des requêtes DNS `ANY`, pas le service. `systemctl status suricata`, `journalctl -u suricata`, puis `systemctl restart suricata`. Pour une zone où l'on préfère la sécurité (une base, un bastion), on retire `bypass` : Suricata arrêté = plus rien ne passe.

**Suricata bloque du trafic légitime** (symptôme vécu : les sauvegardes vers le S3 du fournisseur s'arrêtent) : un IPS qui ne voit qu'**un** sens d'une connexion reçoit des réponses sans avoir vu les questions, et les rejette. Les deux sens doivent passer par la file (`forward` entrant ET sortant, `input` ET `output`).
