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

from common import create_app, log, run, tracer

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
    # Span manuel : l'appel au prestataire externe mérite son propre segment dans la trace
    with tracer.start_as_current_span("prestataire.debit") as span:
        span.set_attribute("payment.method", req.method)
        span.set_attribute("payment.amount_xof", req.amount)
        span.set_attribute("marche.order_id", req.order_id)
        mean, stddev = PROVIDER_LATENCY_MS[req.method]
        provider_ms = max(20, random.gauss(mean, stddev))
        time.sleep(provider_ms / 1000)
        declined = random.random() < DECLINE_RATE
        span.set_attribute("payment.outcome", "declined" if declined else "approved")
        if declined:
            # Un refus est un résultat MÉTIER normal, pas une erreur technique : pas de status ERROR
            span.add_event("paiement refusé", {"reason": "solde insuffisant"})
    PROVIDER_DURATION.labels(req.method, "declined" if declined else "approved").observe(provider_ms / 1000)
    # Donnée personnelle volontairement présente dans les logs : Alloy doit la masquer
    phone = f"+228 9{req.order_id % 10} {req.order_id % 100:02d} {(req.order_id * 7) % 100:02d} {(req.order_id * 13) % 100:02d}"

    if declined:
        log.warning("paiement refusé", extra={
            "order_id": req.order_id, "amount": req.amount, "method": req.method, "reason": "solde insuffisant",
            "customer_phone": phone,
        })
        return JSONResponse({"status": "declined", "reason": "solde insuffisant"}, status_code=402)

    transaction_id = str(uuid.uuid4())
    log.info("paiement accepté", extra={
        "order_id": req.order_id, "amount": req.amount, "method": req.method, "transaction_id": transaction_id,
        "customer_phone": phone,
    })
    return {"status": "approved", "transaction_id": transaction_id}


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


if __name__ == "__main__":
    run(app, 8002)
