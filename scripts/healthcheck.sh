#!/bin/bash
# Quick health check of the whole NAS. Set NEXTCLOUD_URL to your public address.
NEXTCLOUD_URL=${NEXTCLOUD_URL:-https://cloud.example.com}
echo "=== UPTIME / CLOCK ==="; uptime -p; date; sudo hwclock --show 2>/dev/null
echo; echo "=== ROOT (want rw, no emergency_ro) ==="; mount | grep " / " | grep -o "(.*)"
echo; echo "=== SPACE ==="; df -h / /mnt/fast-storage /mnt/backup-hdd
echo; echo "=== CONTAINERS (want 3 Up) ==="; docker ps --format "{{.Names}}: {{.Status}}"
echo; echo "=== NEXTCLOUD ==="; docker exec -u www-data nextcloud-app php occ status 2>&1 | grep -E "installed|maintenance"
echo; echo "=== PUBLIC SITE (want 200 or 302) ==="; curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 "$NEXTCLOUD_URL"
echo; echo "=== DISK ERRORS (want nothing) ==="; sudo dmesg -T 2>/dev/null | grep -i -E "ata[0-9].*(fail|exception|reset)|i/o error|ext4-fs error|emergency_ro" | tail -5
echo; echo "=== DRIVE HEALTH ==="; for d in /dev/disk/by-id/ata-* /dev/disk/by-id/usb-*; do case "$d" in *-part*) continue;; esac; echo -n "$(basename "$d"): "; sudo smartctl -H "$d" 2>/dev/null | grep -i result; done
echo; echo "=== LAST BACKUP ==="; tail -n 3 /mnt/backup-hdd/backup.log
echo; echo "=== DB DUMPS ==="; ls -lh /mnt/backup-hdd/db_backups/ | tail -n 3
echo; echo "=== CRON ==="; systemctl is-active cron; sudo crontab -l 2>/dev/null | grep backup
