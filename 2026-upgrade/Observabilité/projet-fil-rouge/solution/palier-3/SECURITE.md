# Sécurité de la stack — Palier 3

## Surface exposée

| Port hôte | Service | Protection |
| --- | --- | --- |
| 8443 | Caddy → Grafana | HTTPS (CA locale au lab), en-têtes de sécurité, authentification Grafana, anonyme désactivé |
| 8000 | gateway (application) | L'API publique de Marché |
| 127.0.0.1:8001-8002 | orders, payments | Local uniquement, pour `chaos.py` |
| 127.0.0.1:8025 | Mailpit | Local uniquement (lab) |

Prometheus, Alertmanager, Loki, Tempo, Mimir, le Collector et tous les exporters sont sur le réseau `obs` (`internal: true`) : aucun port publié, aucun accès sortant. Vérifié par `verify.py` (ports 9090, 3100, 9093, 3200, 9009, 4317 fermés).

## Mesures

- **Authentification Prometheus** (`web-config.yml`, bcrypt) : UI, API, `/-/reload`. Grafana et les scrapes mutuels des deux répliques s'authentifient avec le secret `prometheus_password`.
- **Secrets Docker** (`secrets/*.txt`, hors Git) : mot de passe admin Grafana (`GF_SECURITY_ADMIN_PASSWORD__FILE`), mot de passe Prometheus (lu par Grafana via `$__file{}` et par Prometheus via `password_file`).
- **Proxy du socket Docker** en lecture seule (`CONTAINERS=1`, `NETWORKS=1`, `POST=0`) : Prometheus et Alloy ne montent plus le socket ; Prometheus ne tourne plus en root.
- **Grafana** : cookies `Secure` + `SameSite=strict`, inscription et accès anonyme désactivés, `root_url` HTTPS.
- **cAdvisor** reste `privileged` (nécessaire) : isolé sur `obs`, sans port publié.
- **Données personnelles** : Alloy masque les numéros de téléphone avant stockage (`+228 95 ** ** 65`).

## Pourquoi le masquage dans Alloy ne suffit pas

1. Le numéro complet reste dans les **fichiers de logs de Docker** sur l'hôte (`docker logs marche-payments` l'affiche) : quiconque accède à l'hôte ou aux sauvegardes de `/var/lib/docker` le lit.
2. Un autre chemin de collecte (un deuxième agent, un export, un développeur qui lit `docker logs`) contourne le masquage.
3. Le motif ne couvre que le format `+228 xx xx xx xx` : un numéro écrit autrement passe.

À faire en plus : **ne pas loguer** la donnée (ou la hacher/tronquer dans l'application), limiter la rotation et la durée de vie des logs Docker (`log-opts max-size/max-file`), définir une rétention Loki conforme aux obligations légales, et restreindre qui peut lire les logs bruts.

## Limites connues (lab)

- Certificat de la CA locale Caddy (avertissement navigateur) ; en production, un vrai domaine → Let's Encrypt.
- Pas de TLS entre composants internes (réseau isolé) ; en production multi-machines : mTLS (exporter-toolkit, `tls` des exporters OTLP).
- Comptes Grafana locaux ; en production : SSO OIDC (voir cours, module 12.6).
- Images épinglées par tag mais pas par digest, non scannées automatiquement.
