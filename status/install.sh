#!/bin/bash
# Installs the status feed in ~/status (no sudo). Does not touch ~/nextcloud.
set -e
export NAS_IP=${NAS_IP:-127.0.0.1}   # LAN address the tunnel connects to
cd ~/status
mkdir -p www state
chmod 755 gen_status.py
python3 gen_status.py && echo "status.json written: $(stat -c %s www/status.json) bytes"
python3 -c 'import json; d=json.load(open("www/status.json")); print("keys:", ", ".join(d)); print("freezes:", d["freezes"]["before"], d["freezes"]["after"], "last:", d["freezes"]["last_freeze_day"]); print("backup last:", d["backups"]["last"] and d["backups"]["last"]["date"], d["backups"]["last"] and d["backups"]["last"]["ok"], "dumps:", d["backups"]["db_dumps_kept"]); print("restarts:", d["restarts"]); print("services:", [(s["name"], s["running"]) for s in d["services"]]); print("nextcloud:", d["nextcloud"]); print("drives:", [(x["name"], x.get("used_pct")) for x in d["drives"]]); print("disk errors:", d["disk_errors_since_boot"])'
docker compose up -d 2>&1 | tail -n 3
sleep 2
echo "local fetch: $(curl -s -o /dev/null -w '%{http_code} %{content_type}' http://${NAS_IP}:8090/status.json)  other path: $(curl -s -o /dev/null -w '%{http_code}' http://${NAS_IP}:8090/)"
echo "CORS header: $(curl -sI http://${NAS_IP}:8090/status.json | grep -i access-control | tr -d '\r')"
echo "from tunnel container: $(docker exec cloudflared sh -c 'true' 2>/dev/null && echo has-shell || echo no-shell)"
( crontab -l 2>/dev/null | grep -vF 'status/gen_status.py'; echo '*/5 * * * * /usr/bin/python3 /home/mahim/status/gen_status.py >/dev/null 2>&1' ) | crontab -
echo "crontab now:"; crontab -l | grep -vE '^\s*(#|$)'
