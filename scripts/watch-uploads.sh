#!/bin/bash
# Watches the Nextcloud data folder for new/modified files
# and triggers preview generation immediately when something changes
WATCH_DIR="/mnt/fast-storage/nextcloud_data/data"

inotifywait -m -r -e close_write -e moved_to --format '%w%f' "$WATCH_DIR" | while read FILE
do
  if [[ "$FILE" != *"/files_trashbin/"* ]] && \
     [[ "$FILE" != *"/cache/"* ]] && \
     [[ "$FILE" != *"/preview/"* ]] && \
     [[ "$FILE" != *"appdata_"* ]] && \
     [[ "$FILE" == *"/files/"* ]]; then

    # Convert absolute host path into Nextcloud-relative path
    RELATIVE_PATH="${FILE#$WATCH_DIR}"

    echo "$(date): New/changed file detected: $RELATIVE_PATH" >> /home/mahim/preview-watch.log
    docker exec -u www-data nextcloud-app php occ preview:generate "$RELATIVE_PATH" >> /home/mahim/preview-watch.log 2>&1
  fi
done
