#!/usr/bin/env bash
# Valide TOUTE la configuration de la stack, sans rien démarrer.
# Utilisé tel quel par la CI (.github/workflows/observabilite-ci.yml) et en local avant chaque commit :
#   ./scripts/validate.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1                      # Git Bash sous Windows : ne pas réécrire les chemins /c/...
ROOT="$(pwd -W 2>/dev/null || pwd)"            # chemin compris par Docker Desktop

PROM=prom/prometheus:v3.15.0
AM=prom/alertmanager:v0.34.1
ALLOY=grafana/alloy:v1.20.0
LOKI=grafana/loki:3.7.8
OTEL=otel/opentelemetry-collector-contrib:0.161.0
SLOTH=ghcr.io/slok/sloth:v0.16.0

step() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
run()  { docker run --rm -v "$ROOT:/w" -w /w "$@"; }

step "Prometheus : syntaxe de la configuration"
run -e PROM_REPLICA=ci --entrypoint promtool "$PROM" check config --syntax-only prometheus/prometheus.yml

step "Prometheus : règles d'enregistrement, d'alerte et SLO"
run --entrypoint promtool "$PROM" check rules prometheus/rules/*.yml

step "Prometheus : tests unitaires des règles"
run -w /w/prometheus/tests --entrypoint promtool "$PROM" test rules alerts_test.yml

step "Sloth : les règles SLO versionnées sont à jour avec la spécification"
run "$SLOTH" generate -i slo/marche-gateway.yml -o .slo-check.yml >/dev/null 2>&1
trap 'rm -f .slo-check.yml' EXIT
diff -q .slo-check.yml prometheus/rules/slo-marche-gateway.yml >/dev/null   || { echo "✖ prometheus/rules/slo-marche-gateway.yml est périmé : relancez sloth generate"; exit 1; }
echo "règles SLO à jour"

step "Alertmanager : configuration et arbre de routage"
run --entrypoint amtool "$AM" check-config alertmanager/alertmanager.yml
test "$(run --entrypoint amtool "$AM" config routes test --config.file=alertmanager/alertmanager.yml severity=critical service=gateway)" = "astreinte,equipe"

step "Alloy : syntaxe"
run "$ALLOY" fmt alloy/config.alloy >/dev/null

step "Loki : configuration"
run "$LOKI" -config.file=loki/loki-config.yaml -verify-config

step "OpenTelemetry Collector : configuration"
run "$OTEL" validate --config=otel-collector/config.yaml

step "Grafana : dashboards JSON valides, uid uniques"
PY=python3; "$PY" -c '' 2>/dev/null || PY=python      # Windows : souvent « python » seulement
"$PY" - <<'EOF'
import json, pathlib, sys
uids = {}
for f in pathlib.Path("grafana/dashboards").rglob("*.json"):
    d = json.loads(f.read_text(encoding="utf-8"))
    for key in ("uid", "title", "panels"):
        if key not in d:
            sys.exit(f"✖ {f} : champ « {key} » manquant")
    if d["uid"] in uids:
        sys.exit(f"✖ uid « {d['uid']} » dupliqué : {f} et {uids[d['uid']]}")
    uids[d["uid"]] = f
    for p in d["panels"]:
        ds = (p.get("datasource") or {}).get("uid", "")
        if ds.startswith("${"):
            sys.exit(f"✖ {f} / « {p.get('title')} » : datasource « {ds} » non résolue (export « for sharing externally » ?)")
print(f"{len(uids)} dashboards OK")
EOF

step "Docker Compose : fichier valide"
docker compose config -q

printf '\n\033[32m✔ Toute la configuration est valide.\033[0m\n'
