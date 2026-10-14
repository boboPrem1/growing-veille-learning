# Secrets (jamais versionnés)

Ce dossier contient les secrets lus par Docker Compose (`secrets:`), montés dans les conteneurs
sous `/run/secrets/<nom>`. Les fichiers `*.txt` sont exclus de Git (voir `.gitignore`).

Créez-les avant le premier `docker compose up` :

```bash
printf '%s' 'un-mot-de-passe-long-et-unique' > secrets/grafana_admin_password.txt
printf '%s' 'prom-lab-2026'                  > secrets/prometheus_password.txt
chmod 644 secrets/*.txt   # Linux : Grafana (uid 472) et Prometheus (nobody) doivent pouvoir les lire
```

- `printf '%s'` et non `echo` : pas de retour à la ligne final, qui ferait partie du mot de passe.
- `prometheus_password.txt` doit correspondre au hash bcrypt de `prometheus/web-config.yml`
  (le hash fourni correspond à `prom-lab-2026`). Pour changer de mot de passe :
  `docker run --rm caddy:2.11.4-alpine caddy hash-password --plaintext 'nouveau'`
  puis remplacez le hash dans `web-config.yml`.
- En production : un gestionnaire de secrets (Vault, Infisical, SOPS + age, secrets du CI…).
