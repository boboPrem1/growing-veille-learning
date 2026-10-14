# Ce que chaque pièce du lab serait chez AWS, GCP et Azure

| Dans le lab | Rôle | AWS | GCP | Azure |
| --- | --- | --- | --- | --- |
| VPC `10.0.0.0/16` | réseau privé isolé | VPC | VPC network | Virtual Network (VNet) |
| `pub`, `baie.20`, `baie.30` | sous-réseaux | Subnets (par AZ) | Subnets (régionaux) | Subnets |
| VLAN 20 / 30 sur un trunk | séparation L2 | *invisible* (le SDN du fournisseur) | *invisible* | *invisible* |
| passerelle : route par défaut vers Internet | sortie/entrée publique | Internet Gateway | route par défaut + adresse externe | *implicite* (« default outbound access », en fin de vie) |
| passerelle : SNAT (`masquerade`) | sortie des sous-réseaux privés | NAT Gateway | Cloud NAT | NAT Gateway |
| passerelle : DNAT 443 → lb | exposer un service | Elastic IP + (Load Balancer public) | External IP + LB | Public IP + LB |
| tables de routage (networkd) | où va le trafic | Route tables | Routes (VPC) | Route tables (UDR) |
| pare-feu de chaque machine (nftables, avec état) | filtrage par instance | Security Groups | Firewall rules (tags / service accounts) | Network Security Groups |
| ACL du sous-réseau données (sans état) | filtrage par sous-réseau | Network ACLs | *(pas d'équivalent sans état)* | *(NSG au sous-réseau, avec état)* |
| résolveur du VPC (unbound, 10.0.x.1) | DNS des machines | Route 53 Resolver (« .2 ») | Cloud DNS (métadonnées 169.254.169.254) | Azure DNS (168.63.129.16) |
| ns1, vue externe | zone publique | Route 53 public hosted zone | Cloud DNS public zone | Azure DNS zone |
| ns1, vue interne (split-horizon) | zone privée | Route 53 private hosted zone | Cloud DNS private zone | Private DNS zone |
| registre `.test` (délégation + glue) | enregistrement du domaine | Route 53 Domains / registrar | Cloud Domains / registrar | App Service Domains / registrar |
| lb (HAProxy, TLS, routage par chemin) | répartiteur L7 | Application Load Balancer | External HTTP(S) LB | Application Gateway |
| contrôle de santé `/healthz` | retrait d'un serveur malade | Target group health check | Health check | Health probe |
| PKI maison (racine + intermédiaire) | certificats | ACM (public) / AWS Private CA | Certificate Manager / CA Service | Key Vault certificates |
| stockage (SeaweedFS, API S3) | stockage objet | S3 | Cloud Storage | Blob Storage |
| politique de bucket « lecture publique » | accès anonyme | Bucket policy (Block Public Access à lever !) | IAM `allUsers` : `roles/storage.objectViewer` | Container « Blob » public |
| utilisateurs IAM `marche-app`, `marche-publication` | identités à moindre privilège | IAM users (mieux : **rôles**) | Service accounts | Managed identities |
| edge (cache nginx à Lomé) | CDN | CloudFront | Cloud CDN | Front Door / Azure CDN |
| WireGuard console ↔ passerelle | VPN d'accès distant | Client VPN | *(tiers)* / IAP pour l'accès admin | Point-to-Site VPN |
| console (clé SSH, racine de la PKI) | poste d'administration | Session Manager / bastion | IAP TCP forwarding | Azure Bastion |

## Ce que le lab fait à la main et que le cloud fait pour vous

- **Le routage inter-sous-réseaux** : dans un VPC, deux sous-réseaux se voient **par défaut** (route « local »). Dans le lab, c'est la passerelle qui route — et son pare-feu qui décide.
- **Les VLAN** : le cloud isole les clients entre eux par encapsulation (VXLAN, Geneve…), sans que vous le voyiez.
- **La haute disponibilité** de la passerelle, du répartiteur, du NAT : managés et redondants chez le fournisseur ; ici, **un seul exemplaire** de chaque (point de défaillance unique, traité au Palier 2).

## Ce que le lab fait mieux que les réglages par défaut du cloud

- Les identifiants de l'application sont des **clés statiques** : acceptable dans le lab, à remplacer par un **rôle** attaché à l'instance (identifiants temporaires, renouvelés seuls) dans un vrai cloud — c'est l'objet du Palier 2.
