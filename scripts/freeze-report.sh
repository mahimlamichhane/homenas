#!/bin/bash
# Summarise the live freeze log written by the freezelog service.
LOG=/mnt/backup-hdd/ssd_freeze_log.txt
echo "Freezes (ata1 exception):  $(grep -c 'ata1.00: exception' $LOG)"
echo "I/O errors:                $(grep -c 'I/O error' $LOG)"
echo "Read-only lockups:         $(grep -c -i -E 'emergency_ro|Remounting filesystem read-only' $LOG)"
echo "Boots logged:              $(grep -c '=== BOOT' $LOG)"
echo; echo "Freezes per day:"; grep 'ata1.00: exception' $LOG | cut -c1-10 | sort | uniq -c
