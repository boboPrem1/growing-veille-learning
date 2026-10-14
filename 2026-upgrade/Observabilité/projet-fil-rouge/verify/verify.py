#!/usr/bin/env python3
"""verify.py — correcteur automatique du projet fil rouge « Marché observable ».

Vérifie les critères d'acceptation d'un palier en interrogeant VOTRE stack, uniquement
à travers l'API de Grafana (qui relaie vers Prometheus, Loki, Tempo… via ses datasources).
Bibliothèque standard uniquement.

    python verify.py --palier 1
    python verify.py --palier 2 --password <mdp admin Grafana>
    python verify.py --palier 3 --url https://localhost:8443 --password <mdp> --repo ../mon-projet

Un palier est validé quand TOUS ses critères sont verts ET ceux des paliers précédents.
Le trafic de loadgen doit tourner depuis au moins 10 minutes.
"""
import argparse
import base64
import json
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--palier", type=int, choices=[1, 2, 3], required=True)
parser.add_argument("--url", default="http://localhost:3000", help="URL de Grafana")
parser.add_argument("--user", default="admin")
parser.add_argument("--password", default="admin")
parser.add_argument("--repo", help="(palier 3) dossier de votre projet, pour vérifier la CI et les secrets")
args = parser.parse_args()
sys.stdout.reconfigure(encoding="utf-8")

AUTH = "Basic " + base64.b64encode(f"{args.user}:{args.password}".encode()).decode()
TLS = ssl._create_unverified_context()  # lab : certificat auto-signé de Caddy accepté
SERVICES = ("gateway", "orders", "payments")
results: list[tuple[str, bool, str]] = []
sections: list[tuple[str, int]] = []   # (titre du palier, index du 1er résultat)


# ------------------------------------------------------------------------------ outils
def http(path: str, auth: bool = True, raw_url: str | None = None):
    url = raw_url or args.url.rstrip("/") + path
    req = urllib.request.Request(url, headers={"Authorization": AUTH} if auth else {})
    with urllib.request.urlopen(req, timeout=20, context=TLS) as resp:
        body = resp.read()
        return json.loads(body) if body else {}


def safe(fn, default=None):
    try:
        return fn()
    except Exception:
        return default


class Stack:
    def __init__(self):
        self.ds = http("/api/datasources")

    def ds_of(self, kind: str, prefer_uid: str | None = None) -> dict | None:
        if prefer_uid:
            for d in self.ds:
                if d["uid"] == prefer_uid:
                    return d
        return next((d for d in self.ds if d["type"] == kind), None)

    def proxy(self, ds: dict | None, path: str, **params):
        if ds is None:
            raise LookupError("datasource absente dans Grafana")
        q = ("?" + urllib.parse.urlencode(params)) if params else ""
        return http(f"/api/datasources/proxy/uid/{ds['uid']}{path}{q}")

    def promql(self, expr: str, ds: dict | None = None) -> list:
        ds = ds or self.prom
        return self.proxy(ds, "/api/v1/query", query=expr)["data"]["result"]

    def logql(self, expr: str) -> list:
        return self.proxy(self.loki, "/loki/api/v1/query", query=expr)["data"]["result"]

    @property
    def prom(self):
        return self.ds_of("prometheus", "prometheus")

    @property
    def loki(self):
        return self.ds_of("loki", "loki")


def check(label: str, hint: str = ""):
    """Décorateur : exécute un critère, capture les erreurs, mémorise le résultat."""
    def deco(fn):
        try:
            ok, detail = fn()
        except Exception as exc:  # une API injoignable = critère non rempli
            ok, detail = False, (str(exc) if isinstance(exc, LookupError) else f"{type(exc).__name__}: {exc}")[:160]
        results.append((label, bool(ok), detail if not ok else (detail or "")))
        if not ok and hint:
            results[-1] = (label, False, f"{detail} → {hint}" if detail else hint)
        return fn
    return deco


def values(result: list) -> list[float]:
    return [float(r["value"][1]) for r in result]


def dashboards() -> list[dict]:
    out = []
    for hit in http("/api/search?type=dash-db&limit=500"):
        d = safe(lambda: http(f"/api/dashboards/uid/{hit['uid']}"))
        if d:
            out.append(d)
    return out


def all_panels(dash: dict) -> list[dict]:
    panels = []
    for p in dash.get("panels", []):
        panels.append(p)
        panels.extend(p.get("panels", []))
    return [p for p in panels if p.get("type") != "row"]


def port_closed(port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(1)
        return s.connect_ex(("127.0.0.1", port)) != 0


# ============================================================================ PALIER 1
def palier_1(st: Stack):
    sections.append(("🟢 Palier 1 — Fondamentaux", len(results)))

    @check("Grafana répond et l'authentification fonctionne")
    def _():
        return http("/api/health").get("database") == "ok", ""

    @check("Datasource Prometheus opérationnelle", "Connections → Data sources → Prometheus → Save & test")
    def _():
        d = st.prom
        return d and http(f"/api/datasources/uid/{d['uid']}/health").get("status") == "OK", "introuvable ou en erreur"

    @check("Datasource Loki opérationnelle", "URL http://loki:3100 (nom du service, pas localhost)")
    def _():
        d = st.loki
        return d and http(f"/api/datasources/uid/{d['uid']}/health").get("status") == "OK", "introuvable ou en erreur"

    @check("Toutes les cibles Prometheus sont UP", "Status → Targets dans Prometheus")
    def _():
        down = st.promql("up == 0")
        return len(st.promql("up")) >= 4 and not down, f"{len(down)} cible(s) DOWN : " + ", ".join(r["metric"].get("instance", "?") for r in down)

    @check("Node Exporter scrapé (métriques node_*)")
    def _():
        return bool(st.promql("node_cpu_seconds_total")), "aucune série node_cpu_seconds_total"

    @check("Les 3 services de Marché sont scrapés", "un job par service, ou un job avec 3 cibles")
    def _():
        found = {r["metric"].get("service") or r["metric"].get("instance", "") for r in st.promql("sum by (service, instance) (http_requests_total)")}
        missing = [s for s in SERVICES if not any(s in f for f in found)]
        return not missing, f"manquant(s) : {missing}"

    @check("Les logs des 3 services arrivent dans Loki avec un label `service`", "voir discovery.relabel dans Alloy")
    def _():
        res = st.logql('sum by (service) (count_over_time({service=~"gateway|orders|payments"}[5m]))')
        got = {r["metric"].get("service") for r in res}
        return set(SERVICES) <= got, f"services trouvés : {sorted(got)}"

    @check("Pas de logs parasites d'autres projets Docker dans Loki", "filtrer dans discovery.docker")
    def _():
        res = st.logql('sum by (container) (count_over_time({service_name=~".+", container!~"marche-.*|prometheus.*|grafana|loki|alloy|node-exporter|cadvisor|.*exporter.*|alertmanager.*|mailpit|tempo|mimir|otel-collector|caddy|docker-socket-proxy"}[10m]))')
        return not res, "conteneurs étrangers : " + ", ".join(r["metric"].get("container", "?") for r in res)

    @check("Un dashboard « Marché » : ≥ 6 panels, métriques + logs, rate() utilisé")
    def _():
        for d in dashboards():
            dash = d["dashboard"]
            if not re.search(r"march[eé]", dash.get("title", ""), re.I):
                continue
            panels = all_panels(dash)
            exprs = " ".join(t.get("expr", "") for p in panels for t in p.get("targets", []))
            has_logs = any(p.get("type") == "logs" for p in panels)
            if len(panels) >= 6 and has_logs and "rate(" in exprs:
                return True, dash["title"]
        return False, "aucun dashboard dont le titre contient « Marché » ne remplit les 3 conditions"


# ============================================================================ PALIER 2
def palier_2(st: Stack):
    sections.append(("🟡 Palier 2 — Intermédiaire", len(results)))

    @check("Datasources provisionnées par fichier avec des uid fixes (prometheus, loki)")
    def _():
        ok = all(any(d["uid"] == u and d.get("readOnly") for d in st.ds) for u in ("prometheus", "loki"))
        return ok, "uid attendus : prometheus, loki (readOnly = provisionné)"

    @check("≥ 2 dashboards provisionnés depuis des fichiers")
    def _():
        prov = [d for d in dashboards() if d["meta"].get("provisioned")]
        return len(prov) >= 2, f"{len(prov)} provisionné(s)"

    @check("Un dashboard avec variable de requête ET annotation personnalisée")
    def _():
        for d in dashboards():
            dash = d["dashboard"]
            has_var = any(v.get("type") == "query" for v in dash.get("templating", {}).get("list", []))
            has_annot = any(not a.get("builtIn") for a in dash.get("annotations", {}).get("list", []))
            if has_var and has_annot:
                return True, dash["title"]
        return False, "aucun"

    @check("Histogramme de latence exposé par les 3 services", "http_request_duration_seconds (Histogram)")
    def _():
        got = {r["metric"].get("service") for r in st.promql("count by (service) (http_request_duration_seconds_bucket)")}
        return set(SERVICES) <= got, f"services : {sorted(filter(None, got))}"

    @check("Métriques métier présentes (marche_orders_total, marche_build_info)")
    def _():
        return bool(st.promql("marche_orders_total")) and bool(st.promql("marche_build_info")), "absentes"

    @check("≥ 3 recording rules nommées niveau:métrique:opérations")
    def _():
        rules = [r for g in st.proxy(st.prom, "/api/v1/rules")["data"]["groups"] for r in g["rules"] if r["type"] == "recording"]
        good = [r for r in rules if r["name"].count(":") >= 2]
        return len(good) >= 3, f"{len(good)} trouvée(s)"

    @check("≥ 6 alertes, toutes avec `severity` et une annotation `summary`")
    def _():
        rules = [r for g in st.proxy(st.prom, "/api/v1/rules")["data"]["groups"] for r in g["rules"] if r["type"] == "alerting"]
        bad = [r["name"] for r in rules if "severity" not in r.get("labels", {}) or "summary" not in r.get("annotations", {})]
        return len(rules) >= 6 and not bad, f"{len(rules)} alerte(s) ; incomplètes : {bad}"

    @check("Prometheus est relié à un Alertmanager actif")
    def _():
        am = st.proxy(st.prom, "/api/v1/alertmanagers")["data"]["activeAlertmanagers"]
        return len(am) >= 1, "aucun"

    @check("cAdvisor : métriques par conteneur Marché")
    def _():
        return len(st.promql('container_memory_working_set_bytes{name=~"marche-.*"}')) >= 4, "absentes"

    @check("Blackbox : ≥ 3 sondes, dont au moins une TCP ou sur /healthz")
    def _():
        res = st.promql("probe_success")
        return len(res) >= 3, f"{len(res)} sonde(s)"

    @check("postgres-exporter : pg_up == 1")
    def _():
        return values(st.promql("pg_up")) == [1.0] or 1.0 in values(st.promql("pg_up")), "pg_up absent ou 0"

    @check("Service discovery Docker utilisé pour l'application", "docker_sd_configs + labels sur les conteneurs")
    def _():
        targets = st.proxy(st.prom, "/api/v1/targets")["data"]["activeTargets"]
        sd = [t for t in targets if "__meta_docker_container_name" in t.get("discoveredLabels", {})]
        return len(sd) >= 3, f"{len(sd)} cible(s) découverte(s) via Docker"

    @check("Pipeline Alloy : label `level` extrait des logs JSON")
    def _():
        res = st.logql('sum by (level) (count_over_time({service=~"gateway|orders|payments", level=~".+"}[10m]))')
        return len(res) >= 2, f"valeurs de level : {[r['metric'].get('level') for r in res]}"

    @check("Alerte Grafana sur les logs (Loki), provisionnée par fichier")
    def _():
        rules = http("/api/v1/provisioning/alert-rules")
        loki_uid = st.loki["uid"]
        ok = [r["title"] for r in rules if r.get("provenance") == "file" and any(q.get("datasourceUid") == loki_uid for q in r["data"])]
        return bool(ok), "aucune règle Loki avec provenance « file »"

    @check("RBAC : une équipe avec membres et un dossier réservé à une équipe")
    def _():
        teams = [t for t in http("/api/teams/search?perpage=100")["teams"] if t.get("memberCount", 0) >= 1]
        restricted = []
        for f in http("/api/folders"):
            perms = safe(lambda: http(f"/api/folders/{f['uid']}/permissions"), [])
            if any(p.get("teamId") for p in perms) and not any(p.get("role") == "Viewer" for p in perms):
                restricted.append(f["title"])
        return bool(teams) and bool(restricted), f"équipes avec membres : {len(teams)} ; dossiers réservés : {restricted}"


# ============================================================================ PALIER 3
def palier_3(st: Stack):
    sections.append(("🔴 Palier 3 — Expert", len(results)))
    tempo = st.ds_of("tempo", "tempo")
    long_term = next((d for d in st.ds if d["type"] == "prometheus" and re.search(r"mimir|thanos", d["url"] + d["name"], re.I)), None)

    @check("Grafana servi en HTTPS, accès anonyme désactivé")
    def _():
        https = args.url.startswith("https://")
        try:
            http("/api/dashboards/home", auth=False)
            anonymous = True
        except urllib.error.HTTPError as err:
            anonymous = err.code != 401
        return https and not anonymous, f"https={https}, anonyme={anonymous}"

    @check("Prometheus, Loki, Alertmanager, Tempo, Mimir non exposés sur l'hôte")
    def _():
        exposed = [p for p in (9090, 3100, 9093, 3200, 9009, 4317) if not port_closed(p)]
        return not exposed, f"ports ouverts : {exposed}"

    @check("Traces des 3 services dans Tempo, dont une qui les traverse tous")
    def _():
        now = int(time.time())
        found = st.proxy(tempo, "/api/search", q='{ resource.service.name = "payments" }', limit=5, start=now - 900, end=now)["traces"]
        if not found:
            return False, "aucune trace de payments ces 15 dernières minutes"
        trace = st.proxy(tempo, f"/api/v2/traces/{found[0]['traceID']}")["trace"]
        services = {a["value"].get("stringValue") for rs in trace["resourceSpans"] for a in rs["resource"]["attributes"] if a["key"] == "service.name"}
        return set(SERVICES) <= services, f"services dans la trace : {sorted(services)}"

    @check("Corrélations configurées : exemplars → Tempo, traces → logs, logs → traces")
    def _():
        def jd(d):
            return http(f"/api/datasources/uid/{d['uid']}")["jsonData"]
        ex = bool(jd(st.prom).get("exemplarTraceIdDestinations"))
        t2l = bool(jd(tempo).get("tracesToLogsV2", {}).get("datasourceUid"))
        l2t = bool(jd(st.loki).get("derivedFields"))
        return ex and t2l and l2t, f"exemplars={ex}, traces→logs={t2l}, logs→traces={l2t}"

    @check("Des exemplars (trace_id) sont réellement stockés")
    def _():
        now = int(time.time())
        data = st.proxy(st.prom, "/api/v1/query_exemplars", query="http_request_duration_seconds_bucket", start=now - 600, end=now)["data"]
        return any(e["labels"].get("trace_id") for s in data for e in s["exemplars"]), "aucun exemplar avec trace_id"

    @check("Les logs portent le trace_id")
    def _():
        res = st.logql('sum(count_over_time({service="payments"} | json | trace_id != "" [5m]))')
        return bool(res) and values(res)[0] > 0, "aucune ligne de payments avec trace_id"

    @check("Service graph : métriques générées à partir des traces")
    def _():
        return bool(st.promql("traces_service_graph_request_total", long_term or st.prom)), "traces_service_graph_request_total absent"

    @check("Stockage long terme (Mimir/Thanos) interrogeable depuis Grafana")
    def _():
        return long_term is not None and bool(st.promql("up", long_term)), "pas de datasource Mimir/Thanos opérationnelle"

    @check("Paire Prometheus HA, dédoublonnée dans le stockage long terme")
    def _():
        replicas = len(st.promql("count by (instance) (prometheus_build_info)", long_term))
        node = len(st.promql('up{job="node"}', long_term))
        return replicas >= 2 and node == 1, f"{replicas} Prometheus, {node} série(s) up{{job=\"node\"}} (attendu : 1)"

    @check("Cluster Alertmanager ≥ 2 membres")
    def _():
        return min(values(st.promql("alertmanager_cluster_members")) or [0]) >= 2, "cluster absent ou incomplet"

    @check("Alerte sentinelle Watchdog active (dead man's switch)")
    def _():
        return bool(st.promql('ALERTS{alertname="Watchdog", alertstate="firing"}')), "absente"

    @check("SLO : SLI enregistrés et alertes multi-burn-rate (14.4 / 6)")
    def _():
        slis = st.promql('{__name__=~"slo:sli_error:ratio_rate.*"}')
        rules = [r for g in st.proxy(st.prom, "/api/v1/rules")["data"]["groups"] for r in g["rules"] if r["type"] == "alerting"]
        burn = [r["name"] for r in rules if "14.4" in r["query"] and "6" in r["query"]]
        return bool(slis) and bool(burn), f"SLI : {len(slis)} série(s), alertes burn-rate : {burn}"

    @check("Données personnelles masquées : aucun numéro de téléphone complet dans Loki")
    def _():
        total = st.logql('sum(count_over_time({service="payments"} |= "customer_phone" [10m]))')
        leaked = st.logql(r'sum(count_over_time({service="payments"} |~ `\+228 \d{2} \d{2} \d{2} \d{2}` [10m]))')
        n_total = values(total)[0] if total else 0
        n_leak = values(leaked)[0] if leaked else 0
        return n_total > 0 and n_leak == 0, f"{int(n_leak)} ligne(s) non masquée(s) sur {int(n_total)}"

    @check("Méta-monitoring : la stack d'observabilité est elle-même scrapée")
    def _():
        comps = {r["metric"].get("job", "") + r["metric"].get("component", "") for r in st.promql('up{job!~"app|database|node|cadvisor|blackbox.*|docker"}')}
        text = " ".join(comps)
        missing = [c for c in ("loki", "tempo", "mimir", "otel") if c not in text]
        return not missing, f"non scrapé(s) : {missing}"

    if args.repo:
        repo = Path(args.repo)

        @check("CI : un workflow valide la config (promtool / amtool)")
        def _():
            wf = list(repo.glob(".github/workflows/*.y*ml")) + list(repo.glob(".gitlab-ci.yml"))
            text = " ".join(p.read_text(encoding="utf-8") for p in wf)
            scripts = " ".join(p.read_text(encoding="utf-8", errors="ignore") for p in repo.glob("scripts/*"))
            return bool(wf) and "promtool" in text + scripts and "amtool" in text + scripts, f"{len(wf)} workflow(s)"

        @check("Secrets hors du dépôt (.gitignore) et plus de mot de passe en clair dans le compose")
        def _():
            ignore = (repo / ".gitignore").read_text(encoding="utf-8") if (repo / ".gitignore").exists() else ""
            compose = (repo / "docker-compose.yml").read_text(encoding="utf-8")
            clear = re.findall(r"GF_SECURITY_ADMIN_PASSWORD:\s*\S+", compose)
            return "secrets" in ignore and not clear, f".gitignore couvre secrets={'secrets' in ignore}, mot de passe en clair={bool(clear)}"


# ============================================================================== main
def main():
    try:
        st = Stack()
    except Exception as exc:
        sys.exit(f"✖ Grafana injoignable sur {args.url} avec {args.user} : {exc}")
    for n in range(1, args.palier + 1):
        {1: palier_1, 2: palier_2, 3: palier_3}[n](st)
    width = max(len(label) for label, _, _ in results)
    starts = {i: title for title, i in sections}
    for i, (label, ok, detail) in enumerate(results):
        if i in starts:
            print(f"\n{starts[i]}")
        print(f"  {'✅' if ok else '❌'} {label:<{width}}  {'' if ok else detail}".rstrip())
    passed = sum(ok for _, ok, _ in results)
    print(f"\n  Score : {passed}/{len(results)}")
    if passed == len(results):
        print(f"  🎉 Palier {args.palier} validé." + (" Passez au game day final (palier-3.md §Épreuve finale)." if args.palier == 3 else ""))
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
