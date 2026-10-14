"""Service `orders` — gestion des commandes (port 8001).

Enregistre la commande dans PostgreSQL, demande le paiement au service `payments`,
puis met à jour le statut de la commande.
"""
import os
import time
from contextlib import asynccontextmanager

import httpx
from fastapi import HTTPException
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel

import common
from common import create_app, log, run

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://marche:marche@postgres:5432/marche")
PAYMENTS_URL = os.environ.get("PAYMENTS_URL", "http://payments:8002")

pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=10, open=False, kwargs={"row_factory": dict_row})
payments = httpx.Client(base_url=PAYMENTS_URL, timeout=10.0)

SCHEMA = """
CREATE TABLE IF NOT EXISTS orders (
    id             BIGSERIAL PRIMARY KEY,
    product_id     INT         NOT NULL,
    quantity       INT         NOT NULL,
    amount         INT         NOT NULL,
    payment_method TEXT        NOT NULL,
    status         TEXT        NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
)
"""


@asynccontextmanager
async def lifespan(_app):
    pool.open(wait=False)
    for attempt in range(1, 31):
        try:
            with pool.connection() as conn:
                conn.execute(SCHEMA)
            log.info("base de données prête")
            break
        except Exception as exc:
            log.warning("base de données indisponible, nouvelle tentative", extra={"attempt": attempt, "error": str(exc)})
            time.sleep(2)
    yield
    pool.close()


app = create_app("Marché — orders", lifespan=lifespan)


class OrderIn(BaseModel):
    product_id: int
    quantity: int
    amount: int
    payment_method: str


def _set_status(order_id: int, status: str) -> dict:
    with pool.connection() as conn:
        row = conn.execute(
            "UPDATE orders SET status = %s WHERE id = %s RETURNING *", (status, order_id)
        ).fetchone()
    return jsonable_encoder(row)


@app.post("/orders")
def create_order(order: OrderIn):
    with pool.connection() as conn:
        if common.CHAOS.db_slow_ms:
            conn.execute("SELECT pg_sleep(%s)", (common.CHAOS.db_slow_ms / 1000,))
        row = conn.execute(
            "INSERT INTO orders (product_id, quantity, amount, payment_method, status) "
            "VALUES (%s, %s, %s, %s, 'pending') RETURNING *",
            (order.product_id, order.quantity, order.amount, order.payment_method),
        ).fetchone()
    order_id = row["id"]
    log.info("commande créée", extra={"order_id": order_id, "amount": order.amount})

    try:
        resp = payments.post("/payments/charge", json={
            "order_id": order_id, "amount": order.amount, "method": order.payment_method,
        })
    except httpx.RequestError as exc:
        log.error("service payments injoignable", extra={"order_id": order_id, "error": str(exc)})
        return JSONResponse(_set_status(order_id, "payment_error"), status_code=502)

    if resp.status_code == 200:
        return JSONResponse(_set_status(order_id, "paid"), status_code=201)
    if resp.status_code == 402:
        return JSONResponse(_set_status(order_id, "payment_declined"), status_code=402)
    log.error("échec du paiement", extra={"order_id": order_id, "payments_status": resp.status_code})
    return JSONResponse(_set_status(order_id, "payment_error"), status_code=502)


@app.get("/orders/{order_id}")
def get_order(order_id: int):
    with pool.connection() as conn:
        row = conn.execute("SELECT * FROM orders WHERE id = %s", (order_id,)).fetchone()
    if row is None:
        raise HTTPException(404, "commande introuvable")
    return JSONResponse(jsonable_encoder(row))


@app.get("/healthz")
def healthz():
    try:
        with pool.connection(timeout=2) as conn:
            conn.execute("SELECT 1")
    except Exception:
        return JSONResponse({"status": "degraded", "database": "down"}, status_code=503)
    return {"status": "ok", "database": "up"}


if __name__ == "__main__":
    run(app, 8001)
