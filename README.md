# Jellyfin Media Server

## 1. Project Overview

This project aims to deploy and operate a self-hosted media streaming service using Jellyfin, an open-source alternative to commercial platforms such as Netflix and Spotify.

The service runs in Docker on an Ubuntu VM and is accessible at:

https://media.comsyslab.csg.uzh.ch

Our deployment focuses on security, data persistence, backup, and disaster recovery.

## 2. Architecture

The system consists of:

- **Jellyfin:** Media server running in a Docker container.
- **Monitoring stack:** Arcane (container management and logs), Uptime Kuma (internal service checks), and Beszel (server and container metrics), with alerts sent to our phones via ntfy.
- **Middleware (Team 4):** Provides DNS, HTTPS, and reverse proxy functionality, the remote Borg backup repository, and external availability checks with Uptime Kuma.
- **Docker Compose:** Manages container deployment and configuration.

Jellyfin listens on `192.168.100.7:8096` and is accessible through the middleware reverse proxy.

Direct access to Jellyfin is restricted to the middleware VM.

## 3. Project Structure

```text
~/project/
├── docker-compose.yml          # Jellyfin
├── .env
├── .gitignore
├── README.md
├── monitoring/
│   ├── docker-compose.yaml     # Arcane, Uptime Kuma, Beszel hub + agent
│   └── .env                    # Arcane ENCRYPTION_KEY, Beszel agent key
└── data/                       # persistent data, excluded from Git
    ├── config/
    ├── cache/
    ├── media/
    ├── arcane/
    ├── uptime-kuma/
    ├── beszel/
    └── beszel-socket/
```

Secrets are stored in the `.env` files (`~/project/.env` and `~/project/monitoring/.env`), which are excluded from Git.

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

### Monitoring stack

The monitoring stack has its own Compose file and is managed from its folder:

```bash
cd ~/project/monitoring
docker compose up -d      # start
docker compose down       # stop
docker compose ps         # status
```

| Container | Image | Purpose | Listens on |
|---|---|---|---|
| `jellyfin` | `jellyfin/jellyfin` | Media server | `192.168.100.7:8096` |
| `arcane` | `ghcr.io/getarcaneapp/manager:v2` | Container management and logs | `127.0.0.1:3552` |
| `uptime-kuma` | `louislam/uptime-kuma:2-slim` | Internal service checks, ntfy alerts | `127.0.0.1:3001` |
| `beszel` | `henrygd/beszel:latest` | Metrics dashboard and resource alerts | `127.0.0.1:8090` |
| `beszel-agent` | `henrygd/beszel-agent:latest` | Collects VM and container metrics | Unix socket in `data/beszel-socket/` |

The monitoring tools only listen on `127.0.0.1` and are reached through an SSH tunnel from a laptop:

```bash
ssh -N -L 8096:192.168.100.7:8096 -L 3552:localhost:3552 -L 3001:localhost:3001 -L 8090:localhost:8090 comsys-grp-3
```

Then open `http://localhost:8096` (Jellyfin), `http://localhost:3552` (Arcane), `http://localhost:3001` (Uptime Kuma), or `http://localhost:8090` (Beszel).

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
docker stop jellyfin arcane uptime-kuma beszel beszel-agent
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

cd ~/project/monitoring
docker compose up -d
```

Verify the containers:

```bash
docker ps
```

### Step 5 — Verify recovery

Open https://media.comsyslab.csg.uzh.ch and verify that:

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



## VM Disaster Recovery

### Overview

To protect our Jellyfin service against complete VM failure, we implemented a remote backup system using BorgBackup.

Our backup architecture consists of three copies:

1. **Original data:** `~/project/data/` on the Team 3 VM.
2. **Local backup:** `~/jellyfin-backup/` on the Team 3 VM.
3. **Remote backup:** Encrypted Borg repository on the Team 4 VM (`192.168.100.8`).

This approach follows the principles of the 3-2-1 backup strategy, although complete compliance depends on the physical independence of the storage infrastructure.

### Backup Configuration

We use three automated backup jobs:

| Time | Operation | Destination |
|---|---|---|
| 03:00 | Jellyfin database and metadata backup | Team 3 VM |
| 04:00 | Filesystem backup using rsync | Team 3 VM |
| 05:00 | Encrypted Borg backup | Team 4 VM |

Borg uses encryption, deduplication, and incremental snapshots to reduce storage usage and preserve previous backup versions.

Snapshot retention:
- 7 daily backups
- 4 weekly backups
- 3 monthly backups

Remote repository:

`ssh://borg@192.168.100.8/var/backups/borg/comsys-lab-group-3`

The Borg backup service and timer are configured in:

```text
~/.config/systemd/user/borg-backup.service
~/.config/systemd/user/borg-backup.timer
```

### Backup Verification

The first manual Borg backup completed successfully.

- Files: 287
- Original size: 12.38 GB
- Deduplicated size: 12.32 GB
- Duration: approximately 4 minutes

Check the backup service:

```bash
systemctl --user status borg-backup.service
```

Check the automatic timer:

```bash
systemctl --user list-timers borg-backup.timer
```

Check the logs:

```bash
journalctl --user -u borg-backup.service -n 50 --no-pager
```

---

## Complete VM Recovery Procedure

This procedure describes how to restore Jellyfin when the original Team 3 VM is completely lost.

### Prerequisites

Before starting, ensure that:

- A replacement Ubuntu VM is available.
- The Team 4 backup server is operational.
- The Borg repository is accessible.
- The Borg passphrase and exported encryption key are available from secure external storage.
- SSH access to the Borg server has been configured.

The recovery credentials were saved outside the original VM.

### Step 1 — Prepare the new VM

Install Docker, Docker Compose, BorgBackup, and rsync.

For example, on a compatible Ubuntu system:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 borgbackup rsync
```

Ensure the `comsys` user can operate Docker without sudo.

The replacement VM should have sufficient storage for the recovered media library and application data.

### Step 2 — Restore the project from GitHub

```bash
cd ~
git clone https://github.com/alexsalc03/comsys-project.git project
```

This restores the Docker Compose configuration, scripts, and documentation.

### Step 3 — Configure Borg access

Restore the Borg passphrase from the secure external copy:

```bash
mkdir -p ~/.config/borg
chmod 700 ~/.config/borg
```

Place the saved passphrase at:

```text
~/.config/borg/passphrase
```

Protect it:

```bash
chmod 600 ~/.config/borg/passphrase
```

Configure the Borg environment:

```bash
export BORG_REPO="ssh://borg@192.168.100.8/var/backups/borg/comsys-lab-group-3"

export BORG_PASSCOMMAND="cat $HOME/.config/borg/passphrase"

export BORG_RSH="ssh -i $HOME/.ssh/comsys_deploy -o IdentitiesOnly=yes"
```

The SSH private key must be restored securely or replaced with a new key authorized by Team 4.

Verify the SSH host fingerprint with Team 4 before trusting the connection.

The exported Borg repository key should also remain available. With `repokey-blake2`, the repository normally stores its encrypted key, so manual key import is not usually necessary.

**Do not run `borg init` again.** The repository already exists and contains our backups.

### Step 4 — List available backups

```bash
borg list
```

This displays the available snapshots.

Example:

```text
comsys-lab-group-3-2026-11-17T15:42:14
```

Select the latest valid backup.

### Step 5 — Restore the backup

Create a temporary recovery directory:

```bash
mkdir -p ~/borg-restore
cd ~/borg-restore
```

Restore the selected archive:

```bash
borg extract ::comsys-lab-group-3-2026-11-17T15:42:14
```

Replace the archive name with the one selected from `borg list`.

The recovered directory should contain:

```text
~/borg-restore/
├── .env
├── config/
└── media/
```

Check the restored files:

```bash
ls -la ~/borg-restore/
```

### Step 6 — Restore Jellyfin data

Create the required directories:

```bash
mkdir -p ~/project/data/{config,cache,media}
```

Restore the configuration and database:

```bash
rsync -a ~/borg-restore/config/ ~/project/data/config/
```

Restore media files:

```bash
rsync -a ~/borg-restore/media/ ~/project/data/media/
```

Restore the environment file:

```bash
install -m 600 ~/borg-restore/.env ~/project/.env
```

The cache does not need to be restored because Jellyfin can regenerate it.

### Step 7 — Start Jellyfin

```bash
cd ~/project
docker compose config --quiet
docker compose up -d
```

Check the containers:

```bash
docker compose ps
```

Check Jellyfin logs if necessary:

```bash
docker compose logs --tail=100 jellyfin
```

Start the monitoring stack (recreate `~/project/monitoring/.env` first, with the Arcane `ENCRYPTION_KEY` from secure external storage):

```bash
cd ~/project/monitoring
docker compose up -d
```

### Step 8 — Restore networking

The original Jellyfin VM used:

```text
192.168.100.7:8096
```

If the replacement VM has a different private IP address:

1. Update the Docker Compose configuration or environment variables.
2. Coordinate with Team 4 to update the reverse proxy destination.
3. Reapply firewall rules to allow connections only from the middleware VM.
4. Verify HTTPS connectivity.

### Step 9 — Verify recovery

Open:

https://media.comsyslab.csg.uzh.ch

Check that:

- Jellyfin is accessible through HTTPS.
- Existing users can log in.
- Media libraries are available.
- Movies and music can be played.
- User preferences and watch history are restored.
- Direct access to Jellyfin from unauthorized hosts is blocked.

### Step 10 — Restore backup automation

Ensure the backup scripts are available in their expected locations:

```text
~/backup.sh
~/bin/jellyfin-backup.sh
```

Restore their execution permissions and the existing cron schedule.

Recreate or restore the Borg systemd service and timer:

```text
~/.config/systemd/user/borg-backup.service
~/.config/systemd/user/borg-backup.timer
```

Enable user lingering if needed:

```bash
sudo loginctl enable-linger "$USER"
```

Reload systemd and enable the timer:

```bash
systemctl --user daemon-reload
systemctl --user enable --now borg-backup.timer
```

Verify that automatic backups are scheduled correctly:

```bash
crontab -l
systemctl --user list-timers borg-backup.timer
```

---

## Limitations

- Remote backups depend on the availability of the Team 4 VM.
- Both VMs may share underlying physical infrastructure.
- The remote backup contains the latest successfully synchronized local data, which may not include the most recent application changes.
- The backup schedule does not currently enforce dependencies between jobs.
- The Borg credentials must remain available outside the original VM.
- The backup does not contain the entire operating system or its firewall configuration.
- The monitoring data (`data/arcane`, `data/uptime-kuma`, `data/beszel`) and `monitoring/.env` are not included in the current backup.
- Our own Uptime Kuma and Beszel run on the monitored VM and cannot report its complete outage; this is covered by Team 4's external Uptime Kuma check.
- A complete recovery on a replacement VM has not yet been tested.

## Recovery Objectives

| Metric | Target |
|---|---|
| Backup frequency | Daily |
| Recovery Point Objective (RPO) | 24 hours |
| Recovery Time Objective (RTO) | 2 hours |
| Recovery source | Team 4 Borg repository |
| Recovery method | Git + Borg + Docker Compose |

RPO and RTO are targets and have not yet been validated through a complete recovery test.

**Status:** Remote backup implemented, automated, and manually verified. Complete VM disaster recovery procedure documented but not yet tested.
