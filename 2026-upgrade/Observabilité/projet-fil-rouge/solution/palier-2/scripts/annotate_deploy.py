#!/usr/bin/env python3
"""Pose une annotation « deploy » dans Grafana — à appeler à la fin de chaque déploiement.

    python scripts/annotate_deploy.py payments 1.2.0 [--token <jeton de compte de service>]

Tous les dashboards qui affichent les annotations taguées « deploy » montreront un trait vertical.
"""
import argparse
import base64
import json
import sys
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("service")
parser.add_argument("version")
parser.add_argument("--url", default="http://localhost:3000")
parser.add_argument("--token", help="jeton de compte de service (sinon admin:marche-admin)")
args = parser.parse_args()
sys.stdout.reconfigure(encoding="utf-8")

auth = f"Bearer {args.token}" if args.token else "Basic " + base64.b64encode(b"admin:marche-admin").decode()
body = {"text": f"Déploiement {args.service} {args.version}", "tags": ["deploy", args.service, args.version]}
req = urllib.request.Request(f"{args.url}/api/annotations", data=json.dumps(body).encode(), method="POST",
                             headers={"Authorization": auth, "Content-Type": "application/json"})
with urllib.request.urlopen(req) as resp:
    print(f"✔ annotation créée (id {json.load(resp)['id']}) : {body['text']}")
