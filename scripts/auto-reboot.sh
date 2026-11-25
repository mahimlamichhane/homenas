#!/bin/bash
# Auto-reboot every 2nd day at 04:00 (called daily by /etc/cron.d/auto-reboot).
# Counts days from ANCHOR so it is exactly every 2 days, also across month/year ends.
# Usage: auto-reboot.sh            -> real run (reboots if today is a reboot day)
#        auto-reboot.sh --dry DATE -> only print whether DATE would be a reboot day
#        auto-reboot.sh --busy     -> only print what (if anything) would block a reboot right now
ANCHOR=2026-11-18
DAY=$(date +%F); DRY=0

busy_check() {
  local b=""
  pgrep -f '/home/mahim/backup.sh' >/dev/null && b="backup"
  # apt/dpkg really working = someone holds the dpkg/apt lock files (the always-running
  # unattended-upgrade-shutdown helper does NOT hold them, so it no longer blocks reboots)
  fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1 && b="$b apt"
  echo "$b"
}

[ "${1:-}" = "--busy" ] && { b=$(busy_check); echo "blocking now: ${b:-nothing}"; exit 0; }
[ "${1:-}" = "--dry" ] && { DRY=1; DAY=${2:-$DAY}; }
diff=$(( ( $(date -d "$DAY 12:00" +%s) - $(date -d "$ANCHOR 12:00" +%s) ) / 86400 ))
if [ $(( ((diff % 2) + 2) % 2 )) -ne 0 ]; then [ $DRY = 1 ] && echo "$DAY: no reboot"; exit 0; fi
[ $DRY = 1 ] && { echo "$DAY: REBOOT at 04:00"; exit 0; }

# Safety: never reboot in the middle of the backup or a package install; wait up to 60 min.
for i in $(seq 1 60); do
  busy=$(busy_check)
  [ -z "$busy" ] && break
  logger -t auto-reboot "waiting:$busy still running"; sleep 60
done
[ -n "$busy" ] && { logger -t auto-reboot "skipped:$busy still running after 60 min"; exit 0; }
# Avoid back-to-back reboots if the machine was already restarted recently (less than 12 h up)
up=$(cut -d. -f1 /proc/uptime); [ "$up" -lt 43200 ] && { logger -t auto-reboot "skipped: up only $((up/3600)) h"; exit 0; }
logger -t auto-reboot "scheduled reboot (every 2 days at 04:00)"
sync
/usr/bin/systemctl reboot
