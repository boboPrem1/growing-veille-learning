"""Service `payments` — passerelle de paiement simulée (port 8002).

Simule un prestataire de paiement (mobile money, carte) : latence variable et
quelques refus « métier » (solde insuffisant), comme dans la vraie vie.
"""
import random
import time
import uuid
from typing import Literal

from fastapi.responses import JSONResponse
from pydantic import BaseModel

from common import create_app, log, run

# Latence moyenne / écart-type du prestataire simulé, en millisecondes
PROVIDER_LATENCY_MS = {"mobile_money": (180, 60), "card": (90, 30)}
DECLINE_RATE = 0.03

app = create_app("Marché — payments")


class ChargeIn(BaseModel):
    order_id: int
    amount: int
    method: Literal["mobile_money", "card"]


@app.post("/payments/charge")
def charge(req: ChargeIn):
    mean, stddev = PROVIDER_LATENCY_MS[req.method]
    time.sleep(max(20, random.gauss(mean, stddev)) / 1000)

    if random.random() < DECLINE_RATE:
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
