#!/usr/bin/env python3
"""Génère donnees/marche.access.log.gz : une journée de logs nginx (format « combined »)
du site Marché, avec quelques anomalies à découvrir pendant l'enquête du Palier 1.

Déterministe (graine fixe) : tout le monde obtient exactement le même fichier, donc les
mêmes réponses. Relancer ce script régénère un fichier identique.
"""
import gzip
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

rng = random.Random(20260928)
TZ = timezone(timedelta(hours=0))        # Lomé : UTC+0
JOUR = datetime(2026, 9, 14, tzinfo=TZ)
OUT = Path(__file__).with_name("marche.access.log.gz")

UA = [
    ("Mozilla/5.0 (Linux; Android 13; TECNO KI5k) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Mobile Safari/537.36", 40),
    ("Mozilla/5.0 (Linux; Android 12; itel A665L) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0 Mobile Safari/537.36", 25),
    ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36", 15),
    ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", 10),
    ("MarcheApp/2.4 (Android)", 10),
]
PRODUITS = [1, 2, 3, 4, 5]
clients = [f"196.{rng.randint(168, 175)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}" for _ in range(420)]
clients += [f"41.{rng.randint(202, 207)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}" for _ in range(180)]
GROS_CLIENT = "196.170.12.77"            # un revendeur qui utilise l'API intensivement
SCANNER = "185.220.101.42"
SCANS = ["/wp-login.php", "/.env", "/phpmyadmin/", "/admin/config.php", "/.git/config", "/xmlrpc.php",
         "/wp-admin/setup-config.php", "/vendor/phpunit/phpunit/src/Util/PHP/eval-stdin.php", "/cgi-bin/luci",
         "/boaform/admin/formLogin", "/server-status", "/.aws/credentials", "/backup.sql", "/config.json"]

def charge(heure: float) -> float:
    """Trafic relatif selon l'heure : creux la nuit, pics à midi et en soirée."""
    base = 0.08 + 0.9 * max(0.0, 1 - abs(heure - 12.5) / 6) + 0.7 * max(0.0, 1 - abs(heure - 19.5) / 3)
    return base

def ligne(t, ip, methode, chemin, statut, octets, ua, referer="-"):
    return (f'{ip} - - [{t.strftime("%d/%b/%Y:%H:%M:%S %z")}] "{methode} {chemin} HTTP/1.1" '
            f'{statut} {octets} "{referer}" "{ua}"')

lignes = []
t = JOUR
fin = JOUR + timedelta(days=1)
while t < fin:
    h = t.hour + t.minute / 60
    t += timedelta(seconds=rng.expovariate(0.9 * charge(h)))
    if t >= fin:
        break
    ip = GROS_CLIENT if rng.random() < 0.04 else rng.choice(clients)
    ua = "MarcheApp/2.4 (Android)" if ip == GROS_CLIENT else rng.choices([u for u, _ in UA], [w for _, w in UA])[0]
    r = rng.random()
    incident = datetime(2026, 9, 14, 14, 5, tzinfo=TZ) <= t < datetime(2026, 9, 14, 14, 23, tzinfo=TZ)
    if r < 0.50:
        lignes.append(ligne(t, ip, "GET", "/api/products", 200, rng.randint(410, 430), ua))
    elif r < 0.78:
        if incident and rng.random() < 0.62:
            statut, octets = 502, 157
        else:
            statut = 402 if rng.random() < 0.03 else 201
            octets = rng.randint(150, 175)
        lignes.append(ligne(t, ip, "POST", "/api/orders", statut, octets, ua))
    elif r < 0.93:
        lignes.append(ligne(t, ip, "GET", f"/api/orders/{rng.randint(1000, 99999)}", 200, rng.randint(150, 175), ua))
    elif r < 0.97:
        lignes.append(ligne(t, ip, "GET", f"/api/orders/{rng.randint(10_000_000, 20_000_000)}", 404, 34, ua))
    elif r < 0.995:
        lignes.append(ligne(t, ip, "GET", f"/static/catalogue-{rng.choice(['sept', 'oct'])}.pdf", 200,
                            rng.randint(2_400_000, 2_600_000), ua, "https://marche.example/promos"))
    else:
        lignes.append(ligne(t, ip, "POST", "/api/orders", 422, 88, ua))

# Le scanner : une rafale nocturne sur des chemins sensibles
ts = datetime(2026, 9, 14, 3, 17, 4, tzinfo=TZ)
for _ in range(3):
    for chemin in SCANS:
        ts += timedelta(seconds=rng.uniform(0.2, 1.5))
        lignes.append(ligne(ts, SCANNER, "GET", chemin, 404, 162, "Mozilla/5.0 zgrab/0.x"))

lignes.sort(key=lambda l: datetime.strptime(l.split("[", 1)[1].split("]", 1)[0], "%d/%b/%Y:%H:%M:%S %z"))
with gzip.open(OUT, "wt", encoding="utf-8", compresslevel=9) as f:
    f.write("\n".join(lignes) + "\n")
print(f"{OUT.name} : {len(lignes)} lignes")
