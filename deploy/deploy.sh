#!/usr/bin/env bash
# Build into a separate release, preserve the world, then switch atomically.
# --build-only performs the production build without changing the live service.
set -Eeuo pipefail
umask 077
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/evolving_minds"
SERVICE_NAME="${EVOLVING_MINDS_SERVICE:-evolving-minds-canary.service}"
ENV_FILE="${EVOLVING_MINDS_ENV:-/etc/evolving-minds/evolving-minds.env}"
RUN_USER="${EVOLVING_MINDS_USER:-$(id -un)}"
RUN_GROUP="${EVOLVING_MINDS_GROUP:-$(id -gn)}"
RELEASES="$REPO_ROOT/.releases"
CURRENT="$REPO_ROOT/current"
BUILD_ONLY=false
if [[ "${1:-}" == --build-only ]]; then BUILD_ONLY=true; elif [[ $# -gt 0 ]]; then echo 'Usage: deploy.sh [--build-only]' >&2; exit 2; fi
[[ "$SERVICE_NAME" =~ ^[a-zA-Z0-9@_.-]+\.service$ ]] || { echo 'Invalid service name' >&2; exit 2; }
[[ -r "$ENV_FILE" ]] || { echo "Cannot read runtime environment: $ENV_FILE" >&2; exit 1; }
mkdir -p "$APP_DIR/_build" "$RELEASES"
exec 9>"$APP_DIR/_build/deploy.lock"
flock -n 9 || { echo 'Another deployment is running' >&2; exit 1; }

# This is a trusted operator-owned file in shell-compatible KEY=value syntax.
# Never enable shell tracing here: it contains production credentials.
set -a
source "$ENV_FILE"
set +a
: "${SECRET_KEY_BASE:?SECRET_KEY_BASE is required}"
: "${PHX_HOST:?PHX_HOST is required}"
APP_PORT="${PORT:-4001}"
[[ "$APP_PORT" =~ ^[0-9]+$ ]] || { echo 'Invalid port' >&2; exit 2; }
[[ ! -e "$CURRENT" || -L "$CURRENT" ]] || { echo 'current must be a symlink, refusing to overwrite a directory' >&2; exit 1; }
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
revision="$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD)"
TARGET="$RELEASES/$stamp-$revision"
previous="$(readlink -f "$CURRENT" 2>/dev/null || true)"

cd "$APP_DIR"
printf 'Building release %s\n' "$stamp-$revision"
mix deps.get --only prod
MIX_ENV=prod mix compile --warnings-as-errors
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --path "$TARGET"
if "$BUILD_ONLY"; then printf 'Build verified: %s\n' "$TARGET"; exit 0; fi

# Migrate the former in-place release once, keeping it available for rollback.
if [[ ! -L "$CURRENT" && -x "$APP_DIR/_build/prod/rel/evolving_minds/bin/evolving_minds" ]]; then
  previous="$RELEASES/$stamp-baseline"
  cp -a "$APP_DIR/_build/prod/rel/evolving_minds" "$previous"
fi


unit_tmp="$(mktemp "$APP_DIR/_build/unit.XXXXXX")"
python3 - "$REPO_ROOT/deploy/evolving-minds.service" "$unit_tmp" "$REPO_ROOT" "$APP_DIR" "$ENV_FILE" "$RUN_USER" "$RUN_GROUP" <<'PY'
import pathlib, sys
source, target, repo, app, env, user, group = sys.argv[1:]
text = pathlib.Path(source).read_text()
for key, value in {'REPO_ROOT':repo,'APP_DIR':app,'ENV_FILE':env,'RUN_USER':user,'RUN_GROUP':group}.items():
    text = text.replace('@'+key+'@', value)
pathlib.Path(target).write_text(text)
PY
if [[ -e "/etc/systemd/system/$SERVICE_NAME" ]]; then
  cp "/etc/systemd/system/$SERVICE_NAME" "$RELEASES/$stamp-service.backup"
fi
switch_release() { ln -sfn "$1" "$CURRENT.next"; mv -Tf "$CURRENT.next" "$CURRENT"; }
rollback() {
  trap - ERR
  echo 'Deployment failed; restoring the previous release.' >&2
  sudo systemctl stop "$SERVICE_NAME" || true
  if [[ -n "$previous" && -x "$previous/bin/evolving_minds" ]]; then
    switch_release "$previous"
    sudo systemctl start "$SERVICE_NAME" || true
  fi
  exit 1
}
trap rollback ERR

# Stop through the existing unit before changing either its binary or cookie.
if systemctl is-active --quiet "$SERVICE_NAME"; then
  if [[ -L "$CURRENT" ]]; then active_bin="$CURRENT/bin/evolving_minds"; else active_bin="$APP_DIR/_build/prod/rel/evolving_minds/bin/evolving_minds"; fi
  "$active_bin" rpc 'case EvolvingMinds.Persistence.save_now() do :ok -> :ok; error -> raise inspect(error) end' > /dev/null
  sudo systemctl stop "$SERVICE_NAME"
fi
if [[ -s "$APP_DIR/data/world.snapshot" ]]; then
  cp --reflink=auto --preserve=mode,timestamps "$APP_DIR/data/world.snapshot" "$RELEASES/$stamp-world.snapshot"
fi
sudo install -m 644 "$unit_tmp" "/etc/systemd/system/$SERVICE_NAME"
rm -f "$unit_tmp"
sudo systemctl daemon-reload
switch_release "$TARGET"
sudo systemctl start "$SERVICE_NAME"
for attempt in $(seq 1 30); do
  body="$(curl -fsS --max-time 3 -H "Host: $PHX_HOST" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$APP_PORT/healthz" 2>/dev/null || true)"
  if [[ "$body" == '{"status":"ok"}' ]]; then
    trap - ERR
    printf 'Deployment healthy: %s (%s)\n' "$revision" "$SERVICE_NAME"
    printf 'Previous release: %s\n' "$previous"
    exit 0
  fi
  sleep 1
done
rollback
