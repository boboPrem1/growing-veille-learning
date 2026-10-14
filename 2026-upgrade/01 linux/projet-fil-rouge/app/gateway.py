"""Service `gateway` — API publique de Marché (port 8000).

Expose le catalogue et relaie la création/consultation de commandes au service `orders`.
"""
import os
from typing import Literal

import httpx
from fastapi import HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from common import create_app, log, run

ORDERS_URL = os.environ.get("ORDERS_URL", "http://127.0.0.1:8001")

# Prix en francs CFA (XOF)
PRODUCTS = {
    1: {"id": 1, "name": "Pagne wax 6 yards", "price": 15000},
    2: {"id": 2, "name": "Sac de riz 25 kg", "price": 17500},
    3: {"id": 3, "name": "Smartphone Tecno Spark", "price": 85000},
    4: {"id": 4, "name": "Panier de tomates", "price": 4000},
    5: {"id": 5, "name": "Forfait internet 10 Go", "price": 5000},
}

app = create_app("Marché — gateway")
orders = httpx.Client(base_url=ORDERS_URL, timeout=10.0)


class OrderIn(BaseModel):
    product_id: int
    quantity: int = Field(ge=1, le=20)
    payment_method: Literal["mobile_money", "card"]


@app.get("/api/products")
def list_products():
    return list(PRODUCTS.values())


@app.post("/api/orders")
def create_order(order: OrderIn):
    product = PRODUCTS.get(order.product_id)
    if product is None:
        raise HTTPException(404, "produit inconnu")
    payload = {
        "product_id": product["id"],
        "quantity": order.quantity,
        "amount": product["price"] * order.quantity,
        "payment_method": order.payment_method,
    }
    try:
        resp = orders.post("/orders", json=payload)
    except httpx.RequestError as exc:
        log.error("service orders injoignable", extra={"error": str(exc)})
        raise HTTPException(503, "service commandes injoignable")
    return JSONResponse(resp.json(), status_code=resp.status_code)


@app.get("/api/orders/{order_id}")
def get_order(order_id: int):
    try:
        resp = orders.get(f"/orders/{order_id}")
    except httpx.RequestError as exc:
        log.error("service orders injoignable", extra={"error": str(exc)})
        raise HTTPException(503, "service commandes injoignable")
    return JSONResponse(resp.json(), status_code=resp.status_code)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


if __name__ == "__main__":
    run(app, 8000)
