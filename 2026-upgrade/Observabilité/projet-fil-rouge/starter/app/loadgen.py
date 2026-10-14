"""Générateur de trafic : simule des clients qui naviguent et commandent en continu.

Mélange volontairement du trafic « sain » et quelques requêtes invalides (404, 422),
pour que vos tableaux de bord aient toujours quelque chose d'intéressant à montrer.
"""
import os
import random
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import httpx

GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://gateway:8000")
RPS = float(os.environ.get("RPS", "5"))

client = httpx.Client(base_url=GATEWAY_URL, timeout=15.0)
known_orders: list[int] = []
stats: dict[str, int] = {}
lock = threading.Lock()


def one_request() -> str:
    roll = random.random()
    if roll < 0.55:
        return str(client.get("/api/products").status_code)
    if roll < 0.85:
        resp = client.post("/api/orders", json={
            "product_id": random.choice([1, 1, 2, 2, 3, 4, 4, 4, 5, 5]),
            "quantity": random.randint(1, 4),
            "payment_method": random.choice(["mobile_money", "mobile_money", "mobile_money", "card"]),
        })
        if resp.status_code in (201, 402):
            known_orders.append(resp.json()["id"])
            del known_orders[:-500]
        return str(resp.status_code)
    if roll < 0.96 and known_orders:
        return str(client.get(f"/api/orders/{random.choice(known_orders)}").status_code)
    if roll < 0.98:
        return str(client.get(f"/api/orders/{random.randint(10_000_000, 20_000_000)}").status_code)
    return str(client.post("/api/orders", json={"product_id": 1, "quantity": 0, "payment_method": "card"}).status_code)


def record() -> None:
    try:
        status = one_request()
    except httpx.HTTPError as exc:
        status = type(exc).__name__
    with lock:
        stats[status] = stats.get(status, 0) + 1
        total = sum(stats.values())
    if total % 500 == 0:
        print(f"loadgen : {total} requêtes, répartition {dict(sorted(stats.items()))}", flush=True)


def main() -> None:
    print(f"loadgen : {RPS} req/s vers {GATEWAY_URL}", flush=True)
    # Charge « ouverte » : les requêtes partent au rythme prévu même si le système ralentit,
    # comme de vrais clients qui n'attendent pas que le voisin ait fini.
    with ThreadPoolExecutor(max_workers=64) as pool:
        while True:
            pool.submit(record)
            time.sleep(random.expovariate(RPS))


if __name__ == "__main__":
    main()
