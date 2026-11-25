#!/usr/bin/env python3
"""Writes ~/status/www/status.json: a public, privacy-safe summary of the NAS.
Run every 5 minutes by mahim's crontab. Contains no file names, users, IPs or secrets."""
import json, os, re, shutil, subprocess, time, urllib.request
from datetime import datetime, timedelta
from pathlib import Path

BASE = Path.home() / "status"
OUT = BASE / "www" / "status.json"
STATE = BASE / "state" / "checks.json"
FREEZE_LOG = Path("/mnt/fast-storage/ssd_freeze_daily.log")
BACKUP_LOG = Path("/mnt/backup-hdd/backup.log")
DUMPS = Path("/mnt/backup-hdd/nextcloud/db_backups")
MIGRATION_DAY = "2026-11-15"   # Geonix SSD replaced by the new SSD
DRIVES = [("/", "System SSD", "128 GB SATA SSD: Ubuntu, Docker, database"),
          ("/mnt/fast-storage", "Data SSD", "256 GB SATA SSD: Nextcloud files"),
          ("/mnt/backup-hdd", "Backup HDD", "500 GB USB hard drive: nightly backups")]
SERVICES = {"nextcloud-app": "Nextcloud", "nextcloud-db": "Database (MariaDB)", "cloudflared": "Cloudflare Tunnel"}


def run(cmd, timeout=20):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


def nextcloud_check():
    t0 = time.time()
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/status.php", timeout=10) as r:
            j = json.load(r)
        ms = round((time.time() - t0) * 1000)
        ok = bool(j.get("installed")) and not j.get("maintenance")
        return {"ok": ok, "maintenance": bool(j.get("maintenance")), "version": j.get("versionstring"), "ms": ms}
    except Exception:
        return {"ok": False, "maintenance": False, "version": None, "ms": None}


def main():
    now = datetime.now().astimezone()
    out = {"generated_at": now.isoformat(timespec="seconds"), "host": "Dell OptiPlex 7040 · Ubuntu Server"}

    # system
    osr = dict(re.findall(r'^(\w+)="?([^"\n]*)"?$', Path("/etc/os-release").read_text(), re.M))
    up = float(Path("/proc/uptime").read_text().split()[0])
    mem = dict((k, int(v.split()[0])) for k, v in (l.split(":", 1) for l in Path("/proc/meminfo").read_text().splitlines()))
    temp = None
    for z in Path("/sys/class/thermal").glob("thermal_zone*"):
        try:
            if (z / "type").read_text().strip() == "x86_pkg_temp":
                temp = round(int((z / "temp").read_text()) / 1000)
        except Exception:
            pass
    out["system"] = {"os": osr.get("PRETTY_NAME"), "kernel": os.uname().release, "uptime_s": int(up),
                     "booted_at": (now - timedelta(seconds=up)).isoformat(timespec="minutes"),
                     "load": round(os.getloadavg()[0], 2), "cpus": os.cpu_count(), "cpu_temp_c": temp,
                     "mem_used_gb": round((mem["MemTotal"] - mem["MemAvailable"]) / 1048576, 1),
                     "mem_total_gb": round(mem["MemTotal"] / 1048576, 1)}

    # drives
    drives = []
    for mnt, name, desc in DRIVES:
        try:
            u = shutil.disk_usage(mnt)
            mounted = os.path.ismount(mnt)
            drives.append({"name": name, "desc": desc, "mounted": mounted, "size_gb": round(u.total / 1e9),
                           "used_gb": round(u.used / 1e9, 1), "used_pct": round(u.used / u.total * 100, 1)})
        except Exception:
            drives.append({"name": name, "desc": desc, "mounted": False})
    out["drives"] = drives
    k = run(["journalctl", "-k", "-b", "--no-pager", "-q"])
    out["disk_errors_since_boot"] = len(re.findall(r"ata\d.*(exception|hard resetting|failed command)|I/O error|EXT4-fs error|remount.*read-only", k))

    # freeze history
    days = []
    if FREEZE_LOG.exists():
        for line in FREEZE_LOG.read_text(errors="ignore").splitlines():
            m = re.match(r"(\d{4}-\d{2}-\d{2}) \| freezes=(\d+).*?I/O errors=(\d+)", line)
            if m:
                days.append({"date": m[1], "freezes": int(m[2]), "io_errors": int(m[3])})
    dedup = {d["date"]: d for d in days}
    days = [dedup[k] for k in sorted(dedup)]
    before = [d for d in days if d["date"] < MIGRATION_DAY]
    after = [d for d in days if d["date"] >= MIGRATION_DAY]
    last_bad = max((d["date"] for d in days if d["freezes"] > 0), default=None)
    out["freezes"] = {"migration_day": MIGRATION_DAY,
                      "before": {"days": len(before), "freezes": sum(d["freezes"] for d in before),
                                 "days_with_freezes": sum(1 for d in before if d["freezes"] > 0)},
                      "after": {"days": len(after), "freezes": sum(d["freezes"] for d in after)},
                      "last_freeze_day": last_bad, "recent": days[-30:]}

    # backups
    runs = {}
    if BACKUP_LOG.exists():
        for line in BACKUP_LOG.read_text(errors="ignore").splitlines()[-400:]:
            m = re.match(r"(.+?\d{4}): (.+?) (OK|FAILED|FAIL|ERROR)\b", line)
            if not m:
                continue
            try:
                dt = datetime.strptime(re.sub(r"\s+", " ", m[1]), "%a %b %d %I:%M:%S %p %z %Y")
            except ValueError:
                continue
            key = dt.strftime("%Y-%m-%d")
            r = runs.setdefault(key, {"date": key, "time": dt.isoformat(timespec="minutes"), "steps": {}})
            r["steps"][m[2].strip()] = m[3] == "OK"
    hist = [dict(r, ok=all(r["steps"].values())) for r in sorted(runs.values(), key=lambda r: r["date"])][-14:]
    dumps = sorted(p.name for p in DUMPS.glob("nextcloud_db_*.sql")) if DUMPS.exists() else []
    out["backups"] = {"last": hist[-1] if hist else None, "history": [{"date": h["date"], "ok": h["ok"]} for h in hist],
                      "db_dumps_kept": len(dumps), "schedule": "Every night at 2:00 AM"}

    # restarts
    j = run(["journalctl", "-t", "auto-reboot", "--since", "-30days", "--no-pager", "-o", "short-iso", "-q"])
    reboots = [l.split()[0] for l in j.splitlines() if "scheduled reboot" in l]
    nxt = None
    for i in range(0, 4):
        d = (now + timedelta(days=i)).strftime("%Y-%m-%d")
        if "REBOOT" in run(["/usr/local/sbin/auto-reboot.sh", "--dry", d]):
            cand = datetime.fromisoformat(d + "T04:00:00").astimezone()
            if cand > now:
                nxt = cand.isoformat(timespec="minutes"); break
    out["restarts"] = {"schedule": "Every 2 days at 4:00 AM", "recent": reboots[-5:], "next": nxt}

    # services
    svc = []
    fmt = "{{.Name}}|{{.State.Status}}|{{.State.StartedAt}}|{{.RestartCount}}"
    for name, label in SERVICES.items():
        line = run(["docker", "inspect", "-f", fmt, name]).strip()
        if line:
            n, st, started, rc = line.split("|")
            svc.append({"name": label, "running": st == "running", "since": started[:19] + "Z", "restarts": int(rc)})
        else:
            svc.append({"name": label, "running": False, "since": None, "restarts": None})
    nc = nextcloud_check()
    out["nextcloud"] = nc
    out["services"] = svc

    # rolling 7-day availability of Nextcloud (one check per run)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    try:
        checks = json.loads(STATE.read_text())
    except Exception:
        checks = []
    checks.append([int(now.timestamp()), 1 if nc["ok"] else 0])
    cutoff = now.timestamp() - 7 * 86400
    checks = [c for c in checks if c[0] >= cutoff]
    STATE.write_text(json.dumps(checks))
    hours = {}
    for ts, ok in checks:
        h = int(ts // 3600)
        a = hours.setdefault(h, [0, 0]); a[0] += ok; a[1] += 1
    out["availability"] = {"checks": len(checks), "since": datetime.fromtimestamp(checks[0][0]).astimezone().isoformat(timespec="minutes"),
                           "pct": round(sum(c[1] for c in checks) / len(checks) * 100, 2),
                           "hourly": [[h * 3600, round(a[0] / a[1], 2)] for h, a in sorted(hours.items())][-168:]}

    tmp = OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(out, separators=(",", ":")))
    os.chmod(tmp, 0o644)
    tmp.replace(OUT)


if __name__ == "__main__":
    main()
