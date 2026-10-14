#!/bin/sh
# Nomme les interfaces d'après leur sous-réseau, au démarrage, avant la configuration réseau.
# /etc/lab/interfaces : une ligne par interface — « <sous-réseau IPv4> <nom> », par exemple
#   10.0.1.0/24  pub
# (Les machines créées par Docker Compose ont déjà des noms parlants ; celles que crée Terraform
#  arrivent en eth0, eth1… dans un ordre qui n'est pas garanti.)
f=/etc/lab/interfaces
[ -r "$f" ] || exit 0
grep -v '^[[:space:]]*#' "$f" | while read -r reseau nom; do
    [ -n "$nom" ] || continue
    ip -br link show "$nom" >/dev/null 2>&1 && continue
    python3 - "$reseau" "$nom" <<'PY'
import ipaddress, json, subprocess, sys
reseau, nom = ipaddress.ip_network(sys.argv[1]), sys.argv[2]
for lien in json.loads(subprocess.check_output(["ip", "-j", "-4", "addr"])):
    if lien["ifname"] == "lo":
        continue
    for a in lien.get("addr_info", []):
        if ipaddress.ip_address(a["local"]) in reseau:
            i = lien["ifname"]
            subprocess.run(["ip", "link", "set", "dev", i, "down"], check=True)
            subprocess.run(["ip", "link", "set", "dev", i, "name", nom], check=True)
            subprocess.run(["ip", "link", "set", "dev", nom, "up"], check=True)
            sys.exit(0)
PY
done
