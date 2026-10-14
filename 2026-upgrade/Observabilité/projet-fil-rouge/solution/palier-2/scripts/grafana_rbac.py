#!/usr/bin/env python3
"""Configure les accès Grafana de Marché (idempotent : relançable sans risque).

Grafana OSS ne sait pas provisionner utilisateurs, équipes et permissions par fichiers :
on passe par l'API HTTP. (En production : Terraform, provider grafana/grafana.)

    python scripts/grafana_rbac.py [--url http://localhost:3000] [--admin admin:marche-admin]

Résultat :
  - awa (Viewer) et koffi (Editor), membres de l'équipe « equipe-paiements »
  - yao (Viewer), hors équipe : sert à vérifier l'isolation du dossier
  - dossier « Paiements » : visible et modifiable UNIQUEMENT par equipe-paiements (+ admins)
  - compte de service « ci-dashboards » (Editor) et son jeton, pour la CI
"""
import argparse
import base64
import json
import sys
import urllib.error
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--url", default="http://localhost:3000")
parser.add_argument("--admin", default="admin:marche-admin", help="identifiants admin « login:mot_de_passe »")
args = parser.parse_args()
sys.stdout.reconfigure(encoding="utf-8")
AUTH = "Basic " + base64.b64encode(args.admin.encode()).decode()

VIEW, EDIT, ADMIN = 1, 2, 4


def api(method: str, path: str, body=None):
    req = urllib.request.Request(args.url + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": AUTH, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        if err.code == 404:
            return None
        raise SystemExit(f"{method} {path} → {err.code} {err.read().decode()}")


def ensure_user(login: str, name: str, role: str) -> int:
    user = api("GET", f"/api/users/lookup?loginOrEmail={login}")
    if user is None:
        user = {"id": api("POST", "/api/admin/users", {
            "login": login, "name": name, "email": f"{login}@marche.local", "password": f"{login}-change-moi",
        })["id"]}
        print(f"+ utilisateur {login}")
    api("PATCH", f"/api/org/users/{user['id']}", {"role": role})
    return user["id"]


def ensure_team(name: str, member_ids: list[int]) -> int:
    found = api("GET", f"/api/teams/search?name={name}")["teams"]
    team_id = found[0]["id"] if found else api("POST", "/api/teams", {"name": name})["teamId"]
    members = {m["userId"] for m in api("GET", f"/api/teams/{team_id}/members")}
    for uid in set(member_ids) - members:
        api("POST", f"/api/teams/{team_id}/members", {"userId": uid})
    print(f"✔ équipe {name} ({len(member_ids)} membres)")
    return team_id


def folder_uid(title: str) -> str:
    for folder in api("GET", "/api/folders"):
        if folder["title"] == title:
            return folder["uid"]
    raise SystemExit(f"Dossier « {title} » introuvable : le provisioning des dashboards a-t-il tourné ?")


def ensure_service_account(name: str, role: str) -> None:
    found = api("GET", f"/api/serviceaccounts/search?query={name}")["serviceAccounts"]
    sa_id = found[0]["id"] if found else api("POST", "/api/serviceaccounts", {"name": name, "role": role})["id"]
    if not api("GET", f"/api/serviceaccounts/{sa_id}/tokens"):
        token = api("POST", f"/api/serviceaccounts/{sa_id}/tokens", {"name": f"{name}-token"})["key"]
        print(f"✔ compte de service {name} — jeton (affiché une seule fois !) : {token}")
    else:
        print(f"✔ compte de service {name} (jeton déjà émis)")


awa = ensure_user("awa", "Awa Mensah", "Viewer")
koffi = ensure_user("koffi", "Koffi Agbeko", "Editor")
ensure_user("yao", "Yao Dossou", "Viewer")
team = ensure_team("equipe-paiements", [awa, koffi])

# POST sur /permissions REMPLACE toute la liste : on ne met ni « Viewer » ni « Editor »
# (rôles d'org), donc le dossier devient invisible pour les autres utilisateurs.
uid = folder_uid("Paiements")
api("POST", f"/api/folders/{uid}/permissions", {"items": [{"teamId": team, "permission": EDIT}]})
print("✔ dossier Paiements réservé à equipe-paiements (Edit)")

ensure_service_account("ci-dashboards", "Editor")
