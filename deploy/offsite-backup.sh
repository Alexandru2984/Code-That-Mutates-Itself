#!/usr/bin/env bash
# Copy only this application's verified archives to its encrypted remote prefix.
set -Eeuo pipefail
umask 077
RUN_STATE="${STATE_DIRECTORY:-/var/lib/evolving-minds-offsite}"
LOCAL_DIR="${LOCAL_BACKUP_DIR:-/srv/backups/evolving-minds}"
REMOTE="${BACKUP_REMOTE:-gdrive-vps-crypt:apps/elixir.micutu.com}"
SEED="${CREDENTIALS_DIRECTORY:?systemd credentials are required}/rclone.conf"
[[ "$REMOTE" == 'gdrive-vps-crypt:apps/elixir.micutu.com' ]] || { echo 'Unexpected backup destination' >&2; exit 1; }
mkdir -p "$RUN_STATE/cache"
exec 9>"$RUN_STATE/backup.lock"
flock -n 9 || { echo 'Another offsite backup is running' >&2; exit 1; }
# The web process can read this one metadata file, not credentials or logs.
setfacl -m u:evolving-minds:--x "$RUN_STATE"
phase=initialise
archive_name=''
archive_hash=''
archive_size=0
publish_status() {
  python3 - "$RUN_STATE/status.json" "$1" "$phase" "$archive_name" "$archive_hash" "$archive_size" <<'PY'
import datetime, json, os, pathlib, sys, tempfile
path=pathlib.Path(sys.argv[1]);kind,phase,name,digest,size=sys.argv[2:]
previous={}
try:
    if path.stat().st_size<=4096: previous=json.loads(path.read_text())
except (OSError,ValueError): pass
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
value={'version':1,'status':kind,'checked_at':now,'phase':phase,
       'last_verified_at':now if kind=='ok' else previous.get('last_verified_at')}
if kind=='ok': value.update(archive=name,sha256=digest,bytes=int(size))
fd,tmp=tempfile.mkstemp(prefix='.status-',dir=path.parent)
with os.fdopen(fd,'w') as handle:
    json.dump(value,handle);handle.flush();os.fsync(handle.fileno())
os.chmod(tmp,0o600);os.replace(tmp,path)
PY
  setfacl -m u:evolving-minds:r-- "$RUN_STATE/status.json"
}
failed() { trap - ERR; publish_status error || true; echo "Encrypted offsite backup failed during $phase; inspect its private service log." >&2; exit 1; }
trap failed ERR
seed_hash="$(sha256sum "$SEED" | cut -d' ' -f1)"
if [[ ! -f "$RUN_STATE/rclone.conf" || ! -f "$RUN_STATE/credential.sha256" || "$(cat "$RUN_STATE/credential.sha256")" != "$seed_hash" ]]; then
  install -m 600 "$SEED" "$RUN_STATE/rclone.conf"
  printf '%s' "$seed_hash" > "$RUN_STATE/credential.sha256"
fi
: > "$RUN_STATE/rclone.log"
remote() {
  /usr/bin/rclone --config "$RUN_STATE/rclone.conf" --cache-dir "$RUN_STATE/cache" \
    --log-file "$RUN_STATE/rclone.log" --log-level ERROR --retries 2 --low-level-retries 3 \
    --contimeout 10s --timeout 30s --max-transfer 16Mi --cutoff-mode hard "$@"
}
phase=local_archive
archive="$(python3 - "$LOCAL_DIR" <<'PY'
import pathlib, re, sys, time
files=[path for path in pathlib.Path(sys.argv[1]).glob('world-*.snapshot.gz')
       if re.fullmatch(r'world-\d{4}-\d{2}-\d{2}T\d{6}(?:\.\d+)?Z\.snapshot\.gz',path.name)
       and path.is_file() and not path.is_symlink()]
if not files:raise SystemExit('No local backup archive')
latest=max(files,key=lambda path:path.stat().st_mtime)
if time.time()-latest.stat().st_mtime>30*3600:raise SystemExit('Local archive is stale')
if not 0<latest.stat().st_size<=8_000_000:raise SystemExit('Unexpected local archive size')
print(latest)
PY
)"
archive_name="$(basename "$archive")"
sha256sum -c "$archive.sha256" > /dev/null
gzip -t "$archive"
archive_hash="$(sha256sum "$archive" | cut -d' ' -f1)"
archive_size="$(stat -c %s "$archive")"
printf '%s  %s\n' "$archive_hash" "$archive_name" > "$RUN_STATE/archive.sha256"
phase=upload
remote copyto "$archive" "$REMOTE/$archive_name"
phase=download_verify
remote copyto "$REMOTE/$archive_name" "$RUN_STATE/roundtrip.snapshot.gz"
cmp -s "$archive" "$RUN_STATE/roundtrip.snapshot.gz"
gzip -t "$RUN_STATE/roundtrip.snapshot.gz"
rm -f "$RUN_STATE/roundtrip.snapshot.gz"
phase=manifest
remote copyto "$RUN_STATE/archive.sha256" "$REMOTE/$archive_name.sha256"
python3 - "$RUN_STATE/latest.json" "$archive_name" "$archive_hash" "$archive_size" <<'PY'
import datetime,json,pathlib,sys
path,name,digest,size=sys.argv[1:]
pathlib.Path(path).write_text(json.dumps({'version':1,'archive':name,'sha256':digest,
    'bytes':int(size),'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}))
PY
remote copyto "$RUN_STATE/latest.json" "$REMOTE/latest.json"
phase=retention
remote delete "$REMOTE" --min-age 30d --include 'world-20*.snapshot.gz' --include 'world-20*.snapshot.gz.sha256'
phase=complete
publish_status ok
trap - ERR
printf 'Encrypted offsite backup verified by download: %s (%s bytes); retention 30 days.\n' "$archive_name" "$archive_size"
