#!/bin/bash
# Nightly Nextcloud backup (fresh Nextcloud 35 stack; HDD reformatted 2026-11-13).
# - DB login is read from inside the nextcloud-db container: no password in this file.
# - Everything goes under $DEST/nextcloud/: db_backups/ (7 daily dumps), nextcloud_mirror/ (single mirror), stack/.
set -u
DEST=/mnt/backup-hdd
NEW=$DEST/nextcloud
SRC=/mnt/fast-storage/nextcloud_data
STACK=/home/mahim/nextcloud
LOG=$DEST/backup.log
log() { echo "$(date): $*" >> "$LOG"; }

# Abort if a drive is not mounted, so rsync --delete can't wipe the mirror
mountpoint -q "$DEST" || { echo "$(date): HDD not mounted, aborted" >> /home/mahim/backup-error.log; exit 1; }
mountpoint -q /mnt/fast-storage || { log "SSD2 not mounted, aborted"; exit 1; }
# Abort if the source doesn't look like a real Nextcloud install
[ -d "$SRC/data" ] && [ -f "$SRC/config/config.php" ] || { log "source data/config missing, aborted"; exit 1; }
docker ps --format '{{.Names}}' | grep -qx nextcloud-db || { log "nextcloud-db not running, aborted"; exit 1; }

mkdir -p "$NEW/db_backups" "$NEW/nextcloud_mirror" "$NEW/stack"

# Database dump: temp file first, only keep it if valid
TMP="$NEW/db_backups/tmp.sql"
if docker exec nextcloud-db sh -c 'exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --routines --triggers "$MARIADB_DATABASE"' > "$TMP" 2>/dev/null \
   && tail -n 1 "$TMP" | grep -q "Dump completed"; then
  chmod 600 "$TMP"
  mv "$TMP" "$NEW/db_backups/nextcloud_db_$(date +%F).sql"
  ls -1t "$NEW"/db_backups/nextcloud_db_*.sql | tail -n +8 | xargs -r rm
  log "DB dump OK"
else
  rm -f "$TMP"
  log "DB DUMP FAILED, old dumps kept"
fi

# Stack files (compose + Dockerfile; .env is copied as a link, not the secrets)
rsync -a "$STACK/" "$NEW/stack/" && log "stack files OK"

# File mirror (program, config and user data)
rsync -a --delete "$SRC/" "$NEW/nextcloud_mirror/" && log "file mirror OK"
