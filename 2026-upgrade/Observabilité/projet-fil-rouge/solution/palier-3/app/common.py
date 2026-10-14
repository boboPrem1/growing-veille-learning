"""Briques partagées par les 3 services de Marché : logs JSON, métriques HTTP, injection de pannes.

Version Palier 3 : ajoute le tracing distribué OpenTelemetry, le trace_id dans
chaque ligne de log et des exemplars sur l'histogramme de latence (métrique → trace).
"""
import asyncio
import json
import logging
import os
import random
import sys
import threading
import time
from datetime import datetime, timezone

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import REGISTRY, Counter, Gauge, Histogram
from prometheus_client.exposition import choose_encoder
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.psycopg import PsycopgInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from pydantic import BaseModel, Field

SERVICE = os.environ.get("SERVICE_NAME", "unknown")
VERSION = os.environ.get("SERVICE_VERSION", "1.0.0")

log = logging.getLogger(SERVICE)


# --------------------------------------------------------------------------- #
# Traces : OpenTelemetry
# --------------------------------------------------------------------------- #
def setup_tracing() -> None:
    """Configure le SDK. Tout le reste vient des variables d'environnement standard :
    OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_TRACES_SAMPLER, OTEL_RESOURCE_ATTRIBUTES…"""
    resource = Resource.create({"service.name": SERVICE, "service.version": VERSION})
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
    # Instrumentation automatique des clients : chaque appel sortant devient un span enfant
    # et propage l'en-tête W3C `traceparent` au service appelé.
    HTTPXClientInstrumentor().instrument()
    PsycopgInstrumentor().instrument(enable_commenter=False)


setup_tracing()
tracer = trace.get_tracer(SERVICE)


def current_trace_id() -> str | None:
    ctx = trace.get_current_span().get_span_context()
    return format(ctx.trace_id, "032x") if ctx.is_valid else None


# --------------------------------------------------------------------------- #
# Logs : une ligne JSON par événement, sur stdout (12-factor)
# --------------------------------------------------------------------------- #
class JsonFormatter(logging.Formatter):
    """Sérialise chaque LogRecord en JSON ; les champs passés via `extra=` sont conservés."""

    _STANDARD = set(vars(logging.makeLogRecord({}))) | {"message", "asctime", "taskName"}

    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": datetime.fromtimestamp(record.created, timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname.lower(),
            "service": SERVICE,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        ctx = trace.get_current_span().get_span_context()
        if ctx.is_valid:  # corrélation logs ↔ traces
            entry["trace_id"] = format(ctx.trace_id, "032x")
            entry["span_id"] = format(ctx.span_id, "016x")
        for key, value in vars(record).items():
            if key not in self._STANDARD and not key.startswith("_"):
                entry[key] = value
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, ensure_ascii=False, default=str)


def setup_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
    # Les logs d'accès d'uvicorn sont remplacés par notre propre ligne d'accès JSON
    logging.getLogger("uvicorn.access").disabled = True
    logging.getLogger("httpx").setLevel(logging.WARNING)


# --------------------------------------------------------------------------- #
# Métriques Prometheus
# --------------------------------------------------------------------------- #
HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Nombre de requêtes HTTP traitées.",
    ["method", "route", "status"],
)
# Durée : histogramme (et non summary) pour pouvoir agréger les quantiles entre instances.
# Pas de label `status` ici : chaque label multiplie le nombre de séries par le nombre de buckets.
HTTP_DURATION = Histogram(
    "http_request_duration_seconds",
    "Durée de traitement des requêtes HTTP.",
    ["method", "route"],
    buckets=(0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)
HTTP_IN_PROGRESS = Gauge(
    "http_requests_in_progress",
    "Requêtes HTTP en cours de traitement (saturation).",
)
BUILD_INFO = Gauge(
    "marche_build_info",
    "Version déployée du service (valeur toujours 1, l'information est dans les labels).",
    ["version"],
)
BUILD_INFO.labels(VERSION).set(1)


# --------------------------------------------------------------------------- #
# Injection de pannes (chaos) — pilotée par chaos.py via /admin/chaos
# --------------------------------------------------------------------------- #
class Chaos(BaseModel):
    latency_ms: int = Field(0, ge=0, description="Latence ajoutée à chaque requête métier")
    error_rate: float = Field(0.0, ge=0.0, le=1.0, description="Proportion de requêtes en erreur 503")
    cpu_burn: bool = Field(False, description="Un thread consomme du CPU en continu")
    leak_kb_per_request: int = Field(0, ge=0, description="Mémoire jamais libérée à chaque requête")
    log_flood: bool = Field(False, description="Émet une rafale de logs WARNING à chaque requête")
    db_slow_ms: int = Field(0, ge=0, description="(orders uniquement) requête SQL ralentie")


CHAOS = Chaos()
_leak: list[bytes] = []
_burner: threading.Thread | None = None


def _burn_cpu() -> None:
    while CHAOS.cpu_burn:
        sum(i * i for i in range(10_000))


async def _apply_chaos() -> JSONResponse | None:
    """Applique les pannes actives. Renvoie une réponse d'erreur si la requête doit échouer."""
    if CHAOS.latency_ms:
        await asyncio.sleep(max(0.0, random.gauss(CHAOS.latency_ms, CHAOS.latency_ms * 0.2)) / 1000)
    if CHAOS.leak_kb_per_request:
        _leak.append(os.urandom(CHAOS.leak_kb_per_request * 1024))
    if CHAOS.log_flood:
        for attempt in range(1, 51):
            log.warning("connexion au cache perdue, nouvelle tentative", extra={"attempt": attempt})
    if CHAOS.error_rate and random.random() < CHAOS.error_rate:
        return JSONResponse({"detail": "service temporairement indisponible"}, status_code=503)
    return None


# --------------------------------------------------------------------------- #
# Fabrique d'application
# --------------------------------------------------------------------------- #
_UNOBSERVED = ("/metrics", "/admin")
_NO_CHAOS = ("/metrics", "/admin", "/healthz")


def create_app(title: str, lifespan=None) -> FastAPI:
    app = FastAPI(title=title, version=VERSION, docs_url=None, redoc_url=None, lifespan=lifespan)

    # Span serveur pour chaque requête (sauf endpoints techniques, inutiles à tracer)
    FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz,metrics,admin")

    @app.get("/metrics", include_in_schema=False)
    def metrics(request: Request) -> Response:
        # Format texte Prometheus par défaut, OpenMetrics si le scraper le demande (exemplars)
        encoder, content_type = choose_encoder(request.headers.get("accept", ""))
        return Response(encoder(REGISTRY), media_type=content_type)

    @app.middleware("http")
    async def observe(request: Request, call_next):
        path = request.url.path
        if path.startswith(_UNOBSERVED):
            return await call_next(request)

        start = time.perf_counter()
        response = None
        with HTTP_IN_PROGRESS.track_inprogress():
            if not path.startswith(_NO_CHAOS):
                response = await _apply_chaos()
            if response is None:
                try:
                    response = await call_next(request)
                except Exception:
                    log.exception("erreur non gérée", extra={"path": path})
                    response = JSONResponse({"detail": "erreur interne"}, status_code=500)
        duration = time.perf_counter() - start

        # On étiquette avec le *modèle* de route (/api/orders/{order_id}), jamais avec le chemin
        # réel (/api/orders/42) : sinon chaque identifiant crée une nouvelle série temporelle.
        route = request.scope.get("route")
        route_path = getattr(route, "path", "unmatched")
        status = response.status_code
        HTTP_REQUESTS.labels(request.method, route_path, str(status)).inc()
        # Exemplar : on accroche le trace_id à l'observation → Grafana affiche un point
        # cliquable sur le graphe de latence qui ouvre LA trace correspondante.
        trace_id = current_trace_id()
        HTTP_DURATION.labels(request.method, route_path).observe(
            duration, exemplar={"trace_id": trace_id} if trace_id else None)

        level = logging.ERROR if status >= 500 else logging.WARNING if status >= 400 else logging.INFO
        log.log(level, "requête traitée", extra={
            "method": request.method,
            "path": path,
            "route": route_path,
            "status": status,
            "duration_ms": round(duration * 1000, 1),
        })
        return response

    @app.get("/admin/chaos")
    def get_chaos() -> Chaos:
        return CHAOS

    @app.post("/admin/chaos")
    def set_chaos(update: dict) -> Chaos:
        global CHAOS, _burner
        CHAOS = Chaos(**{**CHAOS.model_dump(), **update})
        if CHAOS.cpu_burn and (_burner is None or not _burner.is_alive()):
            _burner = threading.Thread(target=_burn_cpu, daemon=True)
            _burner.start()
        if not CHAOS.leak_kb_per_request:
            _leak.clear()
        log.warning("configuration de chaos modifiée", extra={"chaos": CHAOS.model_dump()})
        return CHAOS

    return app


def run(app: FastAPI, port: int) -> None:
    setup_logging()
    log.info("démarrage du service", extra={"version": VERSION, "port": port})
    uvicorn.run(app, host="0.0.0.0", port=port, access_log=False, log_config=None)
