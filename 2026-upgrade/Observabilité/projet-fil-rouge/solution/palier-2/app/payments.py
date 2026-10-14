"""Service `payments` — passerelle de paiement simulée (port 8002).

Simule un prestataire de paiement (mobile money, carte) : latence variable et
quelques refus « métier » (solde insuffisant), comme dans la vraie vie.
"""
import random
import time
import uuid
from typing import Literal

from fastapi.responses import JSONResponse
from prometheus_client import Histogram
from pydantic import BaseModel

from common import create_app, log, run

# Latence moyenne / écart-type du prestataire simulé, en millisecondes
PROVIDER_LATENCY_MS = {"mobile_money": (180, 60), "card": (90, 30)}
DECLINE_RATE = 0.03

app = create_app("Marché — payments")

PROVIDER_DURATION = Histogram(
    "marche_payment_provider_duration_seconds",
    "Temps de réponse du prestataire de paiement, par moyen et résultat.",
    ["method", "outcome"],
    buckets=(0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.0, 5.0),
)


class ChargeIn(BaseModel):
    order_id: int
    amount: int
    method: Literal["mobile_money", "card"]


@app.post("/payments/charge")
def charge(req: ChargeIn):
    mean, stddev = PROVIDER_LATENCY_MS[req.method]
    provider_ms = max(20, random.gauss(mean, stddev))
    time.sleep(provider_ms / 1000)
    declined = random.random() < DECLINE_RATE
    PROVIDER_DURATION.labels(req.method, "declined" if declined else "approved").observe(provider_ms / 1000)

    if declined:
        log.warning("paiement refusé", extra={
            "order_id": req.order_id, "amount": req.amount, "method": req.method, "reason": "solde insuffisant",
        })
        return JSONResponse({"status": "declined", "reason": "solde insuffisant"}, status_code=402)

    transaction_id = str(uuid.uuid4())
    log.info("paiement accepté", extra={
        "order_id": req.order_id, "amount": req.amount, "method": req.method, "transaction_id": transaction_id,
    })
    return {"status": "approved", "transaction_id": transaction_id}


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


if __name__ == "__main__":
    run(app, 8002)
