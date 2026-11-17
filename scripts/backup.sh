#!/bin/bash
set -euo pipefail

PROJECT="$HOME/project"
BACKUP="$HOME/jellyfin-backup"

mkdir -p "$BACKUP"

echo "Starting Jellyfin backup..."

# Stop Jellyfin to ensure database consistency
cd "$PROJECT"
docker compose stop jellyfin

# Always restart Jellyfin, even if the backup fails
trap 'docker compose start jellyfin' EXIT

# Backup application configuration and database
rsync -a "$PROJECT/data/config/" "$BACKUP/config/"

# Backup media files
rsync -a "$PROJECT/data/media/" "$BACKUP/media/"

# Backup secrets
if [ -f "$PROJECT/.env" ]; then
    install -m 600 "$PROJECT/.env" "$BACKUP/.env"
fi

echo "Backup completed successfully!"
