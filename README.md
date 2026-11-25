# HomeNAS

My own private cloud: a Dell OptiPlex 7040 running **Ubuntu Server, Docker, Nextcloud 35 and MariaDB**, reachable from anywhere through a **Cloudflare Tunnel** with no open router ports. Photos from my phone sync to it automatically, it backs itself up every night, restarts itself every two days, and publishes its own health to a public status page.

**Live status:** [status.mahimlamichhane.com.np](https://status.mahimlamichhane.com.np)

```
 iPhone / laptop ──HTTPS──▶ Cloudflare ══tunnel══▶ cloudflared ──▶ Nextcloud (Apache, PHP)
                                                                     │
          ┌──────────────────────────────┬───────────────────────────┤
     System SSD (128 GB)            Data SSD (256 GB)          USB HDD (500 GB)
     Ubuntu, Docker                 files + MariaDB            nightly backups 02:00
```

## What's in this repo

| Folder | What it does |
|---|---|
| [`docker/`](docker) | Compose file for Nextcloud + MariaDB, and a custom image with ffmpeg and ImageMagick for HEIC photo, video and PDF previews |
| [`scripts/backup.sh`](scripts/backup.sh) | Nightly backup: verified database dump (7 kept), stack files, and a full file mirror. Refuses to run if a drive isn't mounted, so `rsync --delete` can never wipe the mirror |
| [`scripts/auto-reboot.sh`](scripts/auto-reboot.sh) | Restarts the server every 2 days at 04:00, but waits while a backup or package install is running and skips if the machine was up less than 12 hours |
| [`scripts/ssd-daily-freeze.sh`](scripts/ssd-daily-freeze.sh) | Writes one line per day counting SSD freezes, resets, failed reads/writes and I/O errors from the kernel log |
| [`system/freezelog.service`](system/freezelog.service) | systemd service that streams disk errors to the backup drive as they happen, so evidence survives a crash |
| [`scripts/healthcheck.sh`](scripts/healthcheck.sh) | One command to check mounts, space, containers, Nextcloud, public URL, disk errors, SMART health and the last backup |
| [`scripts/watch-uploads.sh`](scripts/watch-uploads.sh) | Generates previews the moment a new photo lands, instead of waiting for the nightly job |
| [`status/`](status) | Python script that writes a privacy-safe `status.json` every 5 minutes, served by a locked-down nginx container (read-only, 64 MB) through the tunnel |

## The hard part: random freezes

Nextcloud kept freezing while SSH still worked. I logged every kernel disk event to a separate drive and compared them:

- **128** freeze events, all on the boot SSD (`ata1`), none on the data SSD on the same controller
- **116 of 128** happened within 2 minutes of a 5-minute cron job, i.e. under small random writes
- SMART said the drive was healthy, but the kernel showed exceptions and link resets

Fixes, in order: moved the live MariaDB database to the healthy SSD (481 files verified by SHA-256, with a tested rollback), then cloned the whole system to a new SSD over USB with `rsync -aAXH`, made it bootable with GRUB on a GPT/BIOS layout, tested the new disk with a one-time GRUB entry before swapping, and removed the `libata.force=noncq` workaround. **Freezes since the swap: 0.** See [docs/ssd-freeze-investigation.md](docs/ssd-freeze-investigation.md).

## Setup notes

- Secrets live only in `.env` (see [`docker/.env.example`](docker/.env.example)); the backup script reads the database login from inside the container, so no password appears in any script.
- Paths assume the data SSD at `/mnt/fast-storage` and the backup drive at `/mnt/backup-hdd`.
- The Cloudflare Tunnel runs as its own container with a token from the Cloudflare dashboard.

## Stack

Ubuntu Server · Docker Compose · Nextcloud 35 · MariaDB 10.11 · Cloudflare Tunnel · Bash · Python · cron · systemd · smartctl · nginx

MIT licensed.
