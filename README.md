# Jellyfin Media Server

## 1. Project Overview

This project aims to deploy and operate a self-hosted media streaming service using Jellyfin, an open-source alternative to commercial platforms such as Netflix and Spotify.

The service runs in Docker on an Ubuntu VM and is accessible at:

https://media.csg.uzh.ch

Our deployment focuses on security, data persistence, backup, and disaster recovery.

## 2. Architecture

The system consists of:

- **Jellyfin:** Media server running in a Docker container.
- **Dozzle:** Web interface for monitoring Docker container logs.
- **Middleware (Team 4):** Provides DNS, HTTPS, and reverse proxy functionality.
- **Docker Compose:** Manages container deployment and configuration.

Jellyfin listens on `192.168.100.7:8096` and is accessible through the middleware reverse proxy.

Direct access to Jellyfin is restricted to the middleware VM.

## 3. Project Structure

```text
~/project/
├── docker-compose.yml
├── .env
├── .gitignore
└── data/
    ├── config/
    ├── cache/
    ├── media/
    └── dozzle/
```

The `data` directory contains persistent application data.

Secrets are stored in `.env`, which is excluded from Git.

## 4. Docker Management

Start the services:

```bash
cd ~/project
docker compose up -d
```

Stop the services:

```bash
docker compose down
```

Check container status:

```bash
docker compose ps
```

View Jellyfin logs:

```bash
docker compose logs jellyfin
```

## 5. Backup System

We use two backup mechanisms.

**Jellyfin API backup**

Runs every day at 03:00 using:

```text
~/bin/jellyfin-backup.sh
```

It saves Jellyfin's database, metadata, and subtitles.

**Filesystem backup**

Runs every day at 04:00 using:

```text
~/backup.sh
```

It uses rsync to copy:

- Jellyfin configuration and database.
- Media files (movies, music, videos).
- Environment variables (`.env`).

Only new or modified files are copied during subsequent executions.

Backups are stored in:

```text
~/jellyfin-backup/
├── .env
├── config/
└── media/
```

Both backups are scheduled through cron.

Check the schedule:

```bash
crontab -l
```

## 6. Disaster Recovery — Project Folder Failure

This procedure explains how to restore Jellyfin if the `~/project` directory is accidentally deleted or corrupted.

It assumes the VM is operational and the backup directory is intact.

### Step 1 — Stop existing containers

```bash
docker stop jellyfin dozzle
```

Skip this step if the containers no longer exist.

### Step 2 — Restore the project from Git

If the damaged project directory still exists, rename it:

```bash
mv ~/project ~/project-damaged
```

Clone the repository:

```bash
cd ~
git clone https://github.com/alexsalc03/comsys-project.git project
```

### Step 3 — Restore persistent data

Create the required directories:

```bash
mkdir -p ~/project/data/{config,cache,media}
```

Restore Jellyfin configuration and database:

```bash
rsync -a ~/jellyfin-backup/config/ ~/project/data/config/
```

Restore media files:

```bash
rsync -a ~/jellyfin-backup/media/ ~/project/data/media/
```

Restore secrets:

```bash
install -m 600 ~/jellyfin-backup/.env ~/project/.env
```

### Step 4 — Restart the services

```bash
cd ~/project
docker compose config --quiet
docker compose up -d
```

Verify the containers:

```bash
docker compose ps
```

### Step 5 — Verify recovery

Open https://media.csg.uzh.ch and verify that:

- Jellyfin is accessible.
- Existing users can log in.
- Media files are available.
- Settings and watch history are restored.

If necessary, check the logs:

```bash
docker compose logs --tail=100 jellyfin
```

## 7. Backup Verification

Check the latest filesystem backup logs:

```bash
tail -n 30 ~/filesystem-backup.log
```

Check Jellyfin API backup logs:

```bash
tail -n 30 ~/jellyfin-backup.log
```

Check backup size:

```bash
du -sh ~/jellyfin-backup/*
```

Check scheduled backup jobs:

```bash
crontab -l
```

## 8. Limitations

- Backups are currently stored on the same VM.
- A complete VM failure could result in the loss of both the service and its backups.
- The rsync backup is not versioned.
- Changes made after the last successful backup may be lost.
