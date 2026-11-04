#!/usr/bin/env bash
# Install the already-authorized encrypted Drive destination for this app only.
set -Eeuo pipefail
umask 077
if (( EUID != 0 )); then exec sudo -n -- bash "$0" "$@"; fi
SOURCE_CONFIG="${1:-/home/micu/.config/rclone/rclone.conf}"
[[ $# -le 1 ]] || { echo 'Usage: setup-offsite.sh [operator-rclone-config]' >&2; exit 2; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR=/etc/evolving-minds
BACKUP_DIR=/srv/backups/evolving-minds
SERVICE=evolving-minds-offsite.service
TIMER=evolving-minds-offsite.timer
exec 9>"$ENV_DIR/.offsite-setup.lock"
flock -n 9 || { echo 'Another offsite setup is running' >&2; exit 1; }
checkpoint="$(mktemp -d "$ENV_DIR/offsite-setup.XXXXXX")"
enabled="$(systemctl is-enabled "$TIMER" 2>/dev/null || true)"
active=false
if systemctl is-active --quiet "$TIMER"; then active=true; fi
managed_files=("$ENV_DIR/backup-rclone.conf" /etc/systemd/system/"$SERVICE" /etc/systemd/system/"$TIMER" /usr/local/sbin/evolving-minds-offsite-backup /usr/local/libexec/evolving-minds/stage-offsite.py)
for item in "${managed_files[@]}"; do
  if [[ -e "$item" || -L "$item" ]]; then cp -a "$item" "$checkpoint/$(basename "$item")"; fi
done
rollback() {
  trap - ERR
  systemctl stop "$SERVICE" "$TIMER" || true
  systemctl disable "$TIMER" 2>/dev/null || true
  for item in "${managed_files[@]}"; do
    saved="$checkpoint/$(basename "$item")"
    if [[ -e "$saved" || -L "$saved" ]]; then cp -a "$saved" "$item"; else rm -f -- "$item"; fi
  done
  systemctl daemon-reload
  case "$enabled" in
    enabled) systemctl enable "$TIMER" || true ;;
    enabled-runtime) systemctl enable --runtime "$TIMER" || true ;;
  esac
  if "$active"; then systemctl start "$TIMER" || true; fi
  echo "Offsite setup failed; previous configuration restored from $checkpoint" >&2
  exit 1
}
trap rollback ERR
systemctl stop "$TIMER" "$SERVICE" 2>/dev/null || true
if ! id evolving-minds-offsite > /dev/null 2>&1; then
  useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin evolving-minds-offsite
fi
[[ "$(id -Gn evolving-minds-offsite)" == 'evolving-minds-offsite' ]]
python3 "$REPO_ROOT/deploy/provision-offsite.py" --source-config "$SOURCE_CONFIG"
setfacl -m u:evolving-minds-offsite:r-x "$BACKUP_DIR"
setfacl -d -m u::rwx,g::---,o::---,u:evolving-minds-offsite:r-x,m::r-x "$BACKUP_DIR"
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'world-*' -exec setfacl -m u:evolving-minds-offsite:r-- {} +
install -d -m 755 /usr/local/libexec/evolving-minds
install -m 644 "$REPO_ROOT/deploy/stage-offsite.py" /usr/local/libexec/evolving-minds/stage-offsite.py
install -m 755 "$REPO_ROOT/deploy/offsite-backup.sh" /usr/local/sbin/evolving-minds-offsite-backup
python3 "$REPO_ROOT/deploy/render-unit.py" --template "$REPO_ROOT/deploy/$SERVICE" --output "$checkpoint/rendered.service" \
  --repo-root "$REPO_ROOT" --app-dir "$REPO_ROOT/evolving_minds" --env-file "$ENV_DIR/evolving-minds.env" \
  --user evolving-minds --group evolving-minds --backup-dir "$BACKUP_DIR"
install -m 644 "$checkpoint/rendered.service" /etc/systemd/system/"$SERVICE"
install -m 644 "$REPO_ROOT/deploy/$TIMER" /etc/systemd/system/"$TIMER"
systemd-analyze verify /etc/systemd/system/"$SERVICE" /etc/systemd/system/"$TIMER"
systemctl daemon-reload
systemctl start "$SERVICE"
systemctl enable --now "$TIMER"
trap - ERR
printf 'Encrypted Drive backup installed, downloaded and verified; timer enabled. Checkpoint: %s\n' "$checkpoint"
