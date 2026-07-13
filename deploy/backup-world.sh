#!/usr/bin/env bash
#
# Backs up the Evolving Minds world snapshot to Google Drive via rclone.
#
# Cron (every 6h):
#   0 */6 * * * /home/micu/testing_elixir/deploy/backup-world.sh >> /home/micu/backups/evolving_minds/backup.log 2>&1
#
# Keeps a rolling `world-latest.snapshot` plus timestamped copies with
# a retention window. Fails loudly if the snapshot is missing or stale —
# a stale snapshot means Persistence stopped saving.
#
# Overridable for testing: WORLD_SNAPSHOT, WORLD_BACKUP_REMOTE.
set -euo pipefail

SNAPSHOT="${WORLD_SNAPSHOT:-/home/micu/testing_elixir/evolving_minds/data/world.snapshot}"
REMOTE="${WORLD_BACKUP_REMOTE:-gdrive:Backup_VPS_ovhcloud/evolving-minds}"
KEEP_DAYS=30
MAX_AGE_MINUTES=10

log() { echo "[$(date '+%F %T')] $*"; }

if [ ! -s "$SNAPSHOT" ]; then
  log "ERROR: snapshot missing or empty: $SNAPSHOT"
  exit 1
fi

if [ -n "$(find "$SNAPSHOT" -mmin +"$MAX_AGE_MINUTES")" ]; then
  log "ERROR: snapshot older than ${MAX_AGE_MINUTES}m — is the service running and persisting?"
  exit 1
fi

stamp=$(date '+%Y%m%d-%H%M%S')

rclone copyto "$SNAPSHOT" "$REMOTE/world-$stamp.snapshot"
rclone copyto "$SNAPSHOT" "$REMOTE/world-latest.snapshot"

# Prune timestamped copies past the window; world-latest never matches.
rclone delete "$REMOTE" --min-age "${KEEP_DAYS}d" --include "world-2*.snapshot"

log "OK: uploaded world-$stamp.snapshot ($(stat -c%s "$SNAPSHOT") bytes) to $REMOTE, retention ${KEEP_DAYS}d"
