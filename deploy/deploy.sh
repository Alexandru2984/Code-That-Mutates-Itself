#!/usr/bin/env bash
#
# Build and roll out the Evolving Minds release on this host.
#
#   ./deploy/deploy.sh
#
# Expects /home/micu/testing_elixir/evolving_minds/.env.prod to exist
# (SECRET_KEY_BASE, PHX_HOST, PORT, PHX_SERVER=true).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/evolving_minds"
UNIT_SRC="$REPO_ROOT/deploy/evolving-minds.service"
UNIT_DST="/etc/systemd/system/evolving-minds.service"
PORT="$(grep -oE '^PORT=[0-9]+' "$APP_DIR/.env.prod" | cut -d= -f2)"
PORT="${PORT:-4001}"

cd "$APP_DIR"

echo "==> Fetching deps"
mix deps.get

echo "==> Compiling (prod)"
MIX_ENV=prod mix compile

echo "==> Building assets"
MIX_ENV=prod mix assets.deploy

echo "==> Building release"
MIX_ENV=prod mix release --overwrite

if ! cmp -s "$UNIT_SRC" "$UNIT_DST"; then
  echo "==> Installing systemd unit"
  sudo cp "$UNIT_SRC" "$UNIT_DST"
  sudo systemctl daemon-reload
  sudo systemctl enable evolving-minds.service
fi

echo "==> Restarting service"
sudo systemctl restart evolving-minds.service

echo "==> Waiting for health check on port $PORT"
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:$PORT/healthz" > /dev/null; then
    echo "==> Deploy OK: $(curl -s "http://127.0.0.1:$PORT/healthz")"
    exit 0
  fi
  sleep 2
done

echo "!! Health check failed; recent logs:" >&2
sudo journalctl -u evolving-minds.service --no-pager | tail -30 >&2
exit 1
