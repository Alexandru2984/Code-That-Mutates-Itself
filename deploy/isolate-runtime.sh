#!/usr/bin/env bash
# Migrate only this installation's app and backup services to an unprivileged UID.
# Checkpoint units, ownership/ACLs and the final world before changing identity.
set -Eeuo pipefail
umask 077
if (( EUID != 0 )); then exec sudo -n -- bash "$0" "$@"; fi
[[ $# == 0 ]] || { echo 'Usage: isolate-runtime.sh' >&2; exit 2; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/evolving_minds"
DATA="$APP_DIR/data"
BACKUP=/srv/backups/evolving-minds
ENV_FILE=/etc/evolving-minds/evolving-minds.env
UNIT=evolving-minds-canary.service
BACKUP_UNIT=evolving-minds-backup.service
TIMER=evolving-minds-backup.timer
RUN_USER=evolving-minds
RUN_GROUP=evolving-minds
RELEASES="$REPO_ROOT/.releases"
[[ -d "$DATA" && ! -L "$DATA" && -d "$BACKUP" && ! -L "$BACKUP" ]]
systemctl is-active --quiet "$UNIT"
[[ -L "$REPO_ROOT/current" && -r "$ENV_FILE" ]]
# Do not traverse links while changing data ownership.
[[ -z "$(find "$DATA" "$BACKUP" -xdev -type l -print -quit)" ]] || { echo 'Unexpected data symlink; refusing migration' >&2; exit 1; }
exec 9>"$APP_DIR/_build/deploy.lock"
flock -n 9 || { echo 'Another deployment is running' >&2; exit 1; }
old_user="$(systemctl show "$UNIT" --property=User --value)"
old_group="$(id -gn "$old_user")"
old_backup_user="$(stat -c %U "$BACKUP")"
old_backup_group="$(stat -c %G "$BACKUP")"
checkpoint="$(mktemp -d "$RELEASES/runtime-user.XXXXXX")"
cp -a "/etc/systemd/system/$UNIT" "$checkpoint/app.service"
cp -a "/etc/systemd/system/$BACKUP_UNIT" "$checkpoint/backup.service"
cp -a /usr/local/sbin/evolving-minds-backup "$checkpoint/backup-script"
getfacl -R -p "$DATA" "$BACKUP" > "$checkpoint/data.acl"
timer_active=false
if systemctl is-active --quiet "$TIMER"; then timer_active=true; fi
if ! id "$RUN_USER" > /dev/null 2>&1; then
  useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$RUN_USER"
fi
[[ "$(id -gn "$RUN_USER")" == "$RUN_GROUP" ]]
setfacl -m "u:$RUN_USER:--x" "$RELEASES"
for payload in "$RELEASES"/*; do
  if [[ -d "$payload" && -x "$payload/bin/evolving_minds" ]]; then
    setfacl -R -P -m "u:$RUN_USER:r-X" "$payload"
  fi
done
sudo -u "$RUN_USER" test -r "$REPO_ROOT/current/bin/evolving_minds"
if sudo -u "$RUN_USER" test -w "$REPO_ROOT/current/bin/evolving_minds"; then echo 'Runtime must not write release binaries' >&2; exit 1; fi
if sudo -u "$RUN_USER" test -r "$ENV_FILE"; then echo 'Runtime must not read the operator environment file' >&2; exit 1; fi
for spec in evolving-minds evolving-minds-backup; do
  python3 "$REPO_ROOT/deploy/render-unit.py" --template "$REPO_ROOT/deploy/$spec.service" --output "$checkpoint/$spec.service" \
    --repo-root "$REPO_ROOT" --app-dir "$APP_DIR" --env-file "$ENV_FILE" --user "$RUN_USER" --group "$RUN_GROUP" --backup-dir "$BACKUP"
done
systemd-analyze verify "$checkpoint/evolving-minds.service" "$checkpoint/evolving-minds-backup.service"
rollback() {
  trap - ERR
  echo "Runtime migration failed; restoring service identity and permissions from $checkpoint" >&2
  systemctl stop "$UNIT" "$BACKUP_UNIT" || true
  cp -a "$checkpoint/app.service" "/etc/systemd/system/$UNIT"
  cp -a "$checkpoint/backup.service" "/etc/systemd/system/$BACKUP_UNIT"
  cp -a "$checkpoint/backup-script" /usr/local/sbin/evolving-minds-backup
  chown -R -P "$old_user:$old_group" "$DATA"
  chown -R -P "$old_backup_user:$old_backup_group" "$BACKUP"
  setfacl --restore="$checkpoint/data.acl"
  systemctl daemon-reload
  systemctl start "$UNIT" || true
  if "$timer_active"; then systemctl start "$TIMER" || true; fi
  exit 1
}
trap rollback ERR
systemctl stop "$TIMER" "$BACKUP_UNIT"
systemctl stop "$UNIT"
[[ -s "$DATA/world.snapshot" ]]
cp -p "$DATA/world.snapshot" "$checkpoint/world.snapshot"
chown -R -P "$RUN_USER:$RUN_GROUP" "$DATA" "$BACKUP"
chmod 700 "$DATA" "$BACKUP"
if id evolving-minds-offsite > /dev/null 2>&1; then
  setfacl -m u:evolving-minds-offsite:r-x "$BACKUP"
  setfacl -d -m u::rwx,g::---,o::---,u:evolving-minds-offsite:r-x,m::r-x "$BACKUP"
  find "$BACKUP" -maxdepth 1 -type f -name 'world-*' -exec setfacl -m u:evolving-minds-offsite:r-- {} +
fi
install -m 755 "$REPO_ROOT/deploy/backup-local.sh" /usr/local/sbin/evolving-minds-backup
install -m 644 "$checkpoint/evolving-minds.service" "/etc/systemd/system/$UNIT"
install -m 644 "$checkpoint/evolving-minds-backup.service" "/etc/systemd/system/$BACKUP_UNIT"
systemctl daemon-reload
systemctl start "$UNIT"
ready=false
for attempt in $(seq 1 30); do
  body="$(curl -fsS --max-time 2 -H 'Host: elixir.micutu.com' -H 'X-Forwarded-Proto: https' http://127.0.0.1:4001/healthz 2>/dev/null || true)"
  if [[ "$body" == '{"status":"ok"}' ]]; then ready=true; break; fi
  sleep 1
done
if ! "$ready"; then rollback; fi
systemctl start "$BACKUP_UNIT"
if "$timer_active"; then systemctl start "$TIMER"; fi
trap - ERR
printf 'Runtime and backup migrated to %s. Checkpoint: %s\n' "$RUN_USER" "$checkpoint"
