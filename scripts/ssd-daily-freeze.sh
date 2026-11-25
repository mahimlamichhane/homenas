#!/bin/bash
# Daily boot-SSD (ata1) freeze record. Geonix until 2026-11-15, new 128GB SSD after. Runs at 00:00, records the PREVIOUS day.
# Usage: ssd-daily-freeze.sh            -> record yesterday (appends to $OUT)
#        ssd-daily-freeze.sh YYYY-MM-DD -> print that day only (dry run, writes nothing)
# Stops recording automatically after END (one month). Read-only on the system; only appends to $OUT.
END=2026-12-14
OUT=/mnt/fast-storage/ssd_freeze_daily.log
FLOG=/mnt/backup-hdd/ssd_freeze_log.txt

if [ -n "${1:-}" ]; then DAY=$1; DRY=1; else DAY=$(date -d yesterday +%F); DRY=0; fi
[ $DRY = 0 ] && [[ "$DAY" > "$END" ]] && exit 0

# _TRANSPORT=kernel instead of -k: -k only covers the current boot, this covers every boot of that day
K=$(journalctl _TRANSPORT=kernel --since "$DAY 00:00:00" --until "$DAY 23:59:59" --no-pager -o short-iso 2>/dev/null | grep -v '^-- ')
cnt() { [ -z "$K" ] && echo 0 || grep -cE "$1" <<<"$K"; }
fr=$(cnt 'ata1\.00: exception')
rs=$(cnt 'ata1: hard resetting link')
fw=$(cnt 'ata1\.00: failed command: WRITE')
fread=$(cnt 'ata1\.00: failed command: READ')
io=$(cnt 'I/O error')
ro=$(cnt 'emergency_ro|Remounting filesystem read-only')
sl=$(cnt 'ata1: limiting SATA link speed')
if [ -r "$FLOG" ]; then fl=$(grep "^$DAY" "$FLOG" | grep -c 'ata1.00: exception'); else fl="n/a"; fi
boots=$(journalctl --list-boots --no-pager 2>/dev/null | awk -v d="$DAY" '$4==d' | wc -l)
times=$( [ "$fr" -gt 0 ] && grep 'ata1\.00: exception' <<<"$K" | cut -c12-16 | tr '\n' ' ' | sed 's/ $//')
[ ${#times} -gt 300 ] && times="${times:0:300} ..."

LINE="$DAY | freezes=$fr (freezelog: $fl) | resets=$rs | failed writes=$fw reads=$fread | I/O errors=$io | read-only=$ro | link slowdowns=$sl | boots=$boots | times: ${times:-none}"
if [ $DRY = 1 ]; then echo "$LINE"; exit 0; fi
[ -f "$OUT" ] || echo "# Geonix SSD (ata1) daily freeze record. One line per day, written at 00:00. Ends after $END." > "$OUT"
echo "$LINE" >> "$OUT"
