"""Briques partagées par les 3 services de Marché : logs JSON, métriques HTTP, injection de pannes.

Ce fichier est volontairement court et lisible : c'est lui que vous modifierez au
Palier 2 (métriques applicatives) et au Palier 3 (OpenTelemetry).
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
from prometheus_client import REGISTRY, Counter
from prometheus_client.exposition import choose_encoder
from pydantic import BaseModel, Field

SERVICE = os.environ.get("SERVICE_NAME", "unknown")
VERSION = os.environ.get("SERVICE_VERSION", "1.0.0")

log = logging.getLogger(SERVICE)


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
