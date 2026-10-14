#!/usr/bin/env python3
"""Pose une annotation « deploy » dans Grafana — à appeler à la fin de chaque déploiement.

    python scripts/annotate_deploy.py payments 1.2.0 --token <jeton du compte de service> [--insecure]

Tous les dashboards qui affichent les annotations taguées « deploy » montreront un trait vertical.
"""
import argparse
import json
import ssl
import sys
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("service")
parser.add_argument("version")
parser.add_argument("--url", default="https://localhost:8443")
parser.add_argument("--insecure", action="store_true", help="accepter un certificat auto-signé (lab uniquement)")
parser.add_argument("--token", required=True, help="jeton du compte de service ci-dashboards")
args = parser.parse_args()
TLS = ssl._create_unverified_context() if args.insecure else None
sys.stdout.reconfigure(encoding="utf-8")

auth = f"Bearer {args.token}"
body = {"text": f"Déploiement {args.service} {args.version}", "tags": ["deploy", args.service, args.version]}
req = urllib.request.Request(f"{args.url}/api/annotations", data=json.dumps(body).encode(), method="POST",
                             headers={"Authorization": auth, "Content-Type": "application/json"})
with urllib.request.urlopen(req, context=TLS) as resp:
    print(f"✔ annotation créée (id {json.load(resp)['id']}) : {body['text']}")
