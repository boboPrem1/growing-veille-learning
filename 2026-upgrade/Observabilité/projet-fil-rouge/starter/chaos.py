#!/usr/bin/env python3
"""chaos.py — injecte des pannes dans Marché pour vérifier que votre observabilité les voit.

Uniquement la bibliothèque standard : fonctionne tel quel sous Linux, macOS et Windows.

    python chaos.py status                         # état de chaque service
    python chaos.py set payments latency_ms=1500   # réglage manuel
    python chaos.py scenarios                      # liste des scénarios
    python chaos.py scenario paiement-lent         # déclenche un scénario connu
    python chaos.py gameday [--hard]               # incident(s) tiré(s) au sort, à l'aveugle
    python chaos.py reveal                         # révèle le game day et remet tout d'aplomb
    python chaos.py reset                          # remet tout d'aplomb
"""
import base64
import json
import random
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

SERVICES = {
    "gateway": "http://localhost:8000",
    "orders": "http://localhost:8001",
    "payments": "http://localhost:8002",
}
CONTAINERS = ["gateway", "orders", "payments", "postgres"]
TICKET = Path(__file__).with_name(".gameday")

# nom -> (description révélée après coup, liste d'actions)
# action = ("set", service, {réglages}) ou ("stop", conteneur)
SCENARIOS = {
    "paiement-lent": ("Le prestataire de paiement répond en ~1,5 s au lieu de ~150 ms.",
                      [("set", "payments", {"latency_ms": 1500})]),
    "paiement-instable": ("30 % des appels au service payments échouent en 503.",
                          [("set", "payments", {"error_rate": 0.3})]),
    "base-lente": ("Chaque insertion de commande attend 800 ms dans PostgreSQL.",
                   [("set", "orders", {"db_slow_ms": 800})]),
    "fuite-memoire": ("Le gateway conserve 128 Ko de mémoire à chaque requête.",
                      [("set", "gateway", {"leak_kb_per_request": 128})]),
    "cpu-sature": ("Un thread du service orders consomme un cœur CPU en boucle.",
                   [("set", "orders", {"cpu_burn": True})]),
    "tempete-de-logs": ("Le service orders émet 50 lignes WARNING par requête.",
                        [("set", "orders", {"log_flood": True})]),
    "gateway-erreurs": ("15 % des requêtes du gateway échouent en 503 avant même d'être traitées.",
                        [("set", "gateway", {"error_rate": 0.15})]),
    "paiement-hors-ligne": ("Le conteneur payments est arrêté.",
                            [("stop", "payments")]),
    "base-hors-ligne": ("Le conteneur PostgreSQL est arrêté.",
                        [("stop", "postgres")]),
}
LOUD = ["paiement-hors-ligne", "base-hors-ligne", "paiement-instable", "gateway-erreurs"]
SUBTLE = ["paiement-lent", "base-lente", "fuite-memoire", "cpu-sature", "tempete-de-logs"]


def call(service: str, method: str = "GET", body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{SERVICES[service]}/admin/chaos", data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.load(resp)


def docker(action: str, name: str) -> None:
    subprocess.run(["docker", action, f"marche-{name}"], check=True, capture_output=True)


def apply(name: str) -> None:
    for action in SCENARIOS[name][1]:
        if action[0] == "set":
            call(action[1], "POST", action[2])
        else:
            docker("stop", action[1])


def reset() -> None:
    for name in CONTAINERS:
        docker("start", name)
    time.sleep(3)
    neutral = {"latency_ms": 0, "error_rate": 0.0, "cpu_burn": False,
               "leak_kb_per_request": 0, "log_flood": False, "db_slow_ms": 0}
    for service in SERVICES:
        for attempt in range(10):
            try:
                call(service, "POST", neutral)
                break
            except (urllib.error.URLError, ConnectionError):
                time.sleep(2)
    print("✔ Tous les conteneurs tournent et aucune panne n'est active.")


def status() -> None:
    if TICKET.exists():
        sys.exit("Game day en cours : l'état est masqué. C'est à votre observabilité de vous le dire !")
    for service in SERVICES:
        try:
            active = {k: v for k, v in call(service).items() if v}
            print(f"{service:9} {'✔ nominal' if not active else '⚠ ' + json.dumps(active)}")
        except (urllib.error.URLError, ConnectionError):
            print(f"{service:9} ✖ injoignable")


def parse_value(raw: str):
    if raw.lower() in ("true", "false"):
        return raw.lower() == "true"
    try:
        return int(raw)
    except ValueError:
        return float(raw)


def gameday(hard: bool) -> None:
    if TICKET.exists():
        sys.exit("Un game day est déjà en cours : terminez-le avec `python chaos.py reveal`.")
    chosen = [random.choice(LOUD), random.choice(SUBTLE)] if hard else [random.choice(LOUD + SUBTLE)]
    for name in chosen:
        apply(name)
    started = time.strftime("%Y-%m-%d %H:%M:%S")
    TICKET.write_text(base64.b64encode(json.dumps({"started": started, "scenarios": chosen}).encode()).decode())
    print(f"🔥 Game day démarré à {started} — {len(chosen)} incident(s) en cours.")
    print("   Détectez, diagnostiquez, rédigez votre post-mortem, PUIS lancez `python chaos.py reveal`.")


def reveal() -> None:
    if not TICKET.exists():
        sys.exit("Aucun game day en cours.")
    ticket = json.loads(base64.b64decode(TICKET.read_text()))
    print(f"Game day démarré à {ticket['started']}. Incident(s) injecté(s) :")
    for name in ticket["scenarios"]:
        print(f"  • {name} — {SCENARIOS[name][0]}")
    TICKET.unlink()
    reset()


def main(argv: list[str]) -> None:
    sys.stdout.reconfigure(encoding="utf-8")  # emojis et accents lisibles aussi dans une console Windows
    sys.stderr.reconfigure(encoding="utf-8")
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return
    cmd, args = argv[0], argv[1:]
    if cmd == "status":
        status()
    elif cmd == "set" and len(args) >= 2:
        settings = {k: parse_value(v) for k, v in (a.split("=", 1) for a in args[1:])}
        print(json.dumps(call(args[0], "POST", settings), indent=2))
    elif cmd == "scenarios":
        for name, (desc, _) in SCENARIOS.items():
            print(f"{name:20} {desc}")
    elif cmd == "scenario" and args and args[0] in SCENARIOS:
        apply(args[0])
        print(f"🔥 Scénario « {args[0]} » actif. `python chaos.py reset` pour revenir à la normale.")
    elif cmd == "gameday":
        gameday(hard="--hard" in args)
    elif cmd == "reveal":
        reveal()
    elif cmd == "reset":
        reset()
    else:
        sys.exit(f"Commande inconnue ou incomplète : {' '.join(argv)}\n{__doc__}")


if __name__ == "__main__":
    main(sys.argv[1:])
