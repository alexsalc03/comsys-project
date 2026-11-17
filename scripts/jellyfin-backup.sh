
#!/bin/bash
set -euo pipefail

URL="http://192.168.100.7:8096"
KEY_FILE="$HOME/.config/jellyfin-backup/api-key"

# Prevent overlapping backup jobs
exec 9>"$HOME/.config/jellyfin-backup/backup.lock"
flock -n 9 || exit 0

echo "[$(date)] Starting Jellyfin backup"

API_KEY=$(cat "$KEY_FILE")

curl --fail-with-body --silent --show-error \
    --max-time 3600 \
    -X POST "$URL/Backup/Create" \
    -H "Authorization: MediaBrowser Token=\"$API_KEY\"" \
    -H "Content-Type: application/json" \
    -d '{
        "Database": true,
        "Metadata": true,
        "Subtitles": true,
        "Trickplay": false
    }'

unset API_KEY

echo
echo "[$(date)] Backup completed successfully"
