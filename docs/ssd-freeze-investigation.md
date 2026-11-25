# Tracing random Nextcloud freezes to a failing SSD

## Symptom
Nextcloud on my home server would hang for minutes at a time: uploads stalled, the web UI timed out, and the database sometimes reported "server has gone away". SSH kept working, so the machine itself was alive.

## Collecting evidence
A crash can lose the very logs that explain it, so I added a small systemd service ([`freezelog.service`](../system/freezelog.service)) that follows the kernel log and appends every disk exception, link reset, I/O error or read-only remount to a file **on a different drive**. A daily script ([`ssd-daily-freeze.sh`](../scripts/ssd-daily-freeze.sh)) turns that into one line per day.

## What the numbers said
- 128 freeze events, every one on `ata1`, the boot SSD. The data SSD on the same SATA controller had none, which ruled out the controller, cable standard and kernel driver as a shared cause.
- 116 of the 128 happened within two minutes of a cron job that runs every five minutes and does many small writes.
- SMART reported "PASSED". Health counters alone would have hidden the problem.

## Fixes
1. **Protect the data first.** I moved the live MariaDB database off the failing drive onto the healthy SSD, verified all 481 files by SHA-256 checksum and kept a rollback path.
2. **Mitigate.** Disabling NCQ (`libata.force=noncq`) reduced, but didn't stop, the freezes.
3. **Replace the drive without reinstalling.** I partitioned a new SSD (BIOS boot, `/boot`, root), copied the running system with `rsync -aAXHx --numeric-ids` in two passes (the second with Docker stopped), pointed `fstab` at the new UUIDs, installed GRUB from a chroot, and booted it once using a one-time GRUB entry before physically swapping drives.
4. **Clean up.** Removed the NCQ workaround and put the NCQ queue depth back to 32.

## Result
Zero freezes since the swap. The daily record keeps running and is published live at [status.mahimlamichhane.com.np](https://status.mahimlamichhane.com.np).

## Lessons
- Log to a different disk than the one you suspect.
- Compare against a control: the healthy SSD on the same controller was the most useful data point.
- "SMART: PASSED" is not proof a drive is fine.
