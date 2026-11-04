# Operations and recovery

## Runtime inventory

- Unit: `evolving-minds-canary.service`, dedicated user/group `evolving-minds` (no login or privileged groups).
- Environment: `/etc/evolving-minds/evolving-minds.env` (root:micu, 0640).
- HTTP origin: `127.0.0.1:4001`. The public hostname is `elixir.micutu.com`.
- Working directory: `evolving_minds/`; private data directory owned by `evolving-minds`, 0700; snapshot 0600.
- Release: `current` symlink → private `.releases/<time>-<revision>`.
- Nginx site: `/etc/nginx/sites-available/elixir.micutu.com`.
- Local backups: `/srv/backups/evolving-minds`, daily systemd timer, 14 days.
- Encrypted offsite backups: `evolving-minds-offsite.timer`, every six hours with
  up to five minutes of jitter, `gdrive-vps-crypt:apps/elixir.micutu.com`, 30 days.

## Deploy

Run both test suites, formatting checks and `mix hex.audit` before deploying.
`deploy/deploy.sh --build-only` compiles a real production release without stopping
the running service. `deploy/deploy.sh` builds a separate payload, saves the world,
stops the existing unit gracefully, copies its final snapshot, installs the rendered
unit, switches `current` atomically, and requires a successful readiness response.
Failure rolls back to the preceding release. The script never overwrites the active
release while building. Retain at least one verified older payload and snapshot.

`deploy/isolate-runtime.sh` performs the one-time service identity migration and
keeps a root-readable checkpoint of units, ACLs and the final snapshot. It also
adapts the local backup service and tests an actual backup before declaring success.
Regular deploys retain the installed service identity and grant that identity only
read/execute access to the new release payload. The runtime cannot change code,
read the operator environment file, or access this checkout's Git metadata.
The system manager loads runtime values before applying the filesystem sandbox.
Snapshot copies made by the operator now require sudo; deploy handles this explicitly.

Overrides: `EVOLVING_MINDS_SERVICE`, `EVOLVING_MINDS_ENV`, `EVOLVING_MINDS_USER`,
`EVOLVING_MINDS_GROUP`. The trusted environment file uses shell-compatible
`KEY=value` syntax. Keep shell tracing disabled. Do not paste its contents in logs.

The versioned Nginx files belong to this vhost only. Install `nginx-limits.conf`
under `/etc/nginx/conf.d/evolving-minds-limits.conf` and `nginx-proxy.conf` under
`/etc/nginx/snippets/evolving-minds-proxy.conf` before installing `nginx.conf` as the
site file. Back up existing files first. Run `sudo nginx -t` before reloading;
restore the copies if validation fails. Preserve the shared Cloudflare real_ip
configuration and origin allowlist. Do not modify other domains.

After deploy check HTTPS `/`, `/tree`, `/lab`, `/offline`, `/healthz`, `/robots.txt`, `/sitemap.xml`,
an unauthenticated `/admin/world`, cookie flags, and an actual LiveView connection.
Review recent unit logs for snapshot restore errors and restarts. Verify that the
lab has no app session cookie or CSRF/LiveView token and that an offline preparation
and reload works through the public hostname. Check `/service-worker` has no-store
at Cloudflare, not just at the origin: the original .js endpoint was observed with
a rewritten four-hour browser TTL. The canonical versioned endpoint now uses
browser and CDN no-store controls. The legacy .js route is not used by new setups.

Run `python3 deploy/verify-production.py` for repeatable public HTTP checks.
It checks canonical metadata, security headers, cookie flags on live pages, stateless lab documents, worker/manifest contracts, readiness, discovery
and protected paths, without credentials or world mutations. Browser flows are
covered by `cd e2e && npm test`, against isolated fixtures with persistence disabled.

Administrative pages have a separate CSP and receive no injected analytics script.
The public analytics configuration remains restricted to the existing configured origins.
Nginx preserves the application's CSP for admin so LiveDashboard's response-specific
nonces reach the browser. Do not replace that policy with a static `script-src 'self'`
header: its inline bootstrap would stop working. A strict fallback covers responses
without an application CSP. The browser suite tests a real authenticated dashboard mount.

## Rollback

1. Identify the previous directory reported by the deploy script; check it contains
   `bin/evolving_minds`. Do not use an arbitrary path from visitor input.
2. `sudo systemctl stop evolving-minds-canary.service` before changing `current`.
3. Create `current.next` as a symlink to that directory and `mv -Tf current.next current`.
4. `sudo systemctl start evolving-minds-canary.service`; require `/healthz` = 200
   with `{"status":"ok"}`. Send Host and X-Forwarded-Proto headers for origin checks.
5. Keep the current snapshot unless a documented schema migration requires a
   restore. A code rollback and a world rollback are separate decisions.

## Restore a world

Stop the service. Preserve the rejected/current snapshot before replacing it.
Verify the backup checksum and gzip integrity; decompress to a temporary file.
Validate its structure with `EvolvingMinds.Snapshot.read/1` in a process with
persistence and evolution disabled. Copy it to `data/world.snapshot` as `evolving-minds`,
mode 0600, then start the service and check the restore count and readiness.
Snapshots are ETF data, never executable imports. Compressed ETF is rejected;
decompress the backup's gzip wrapper first. Malformed snapshots fail startup so
they cannot silently be overwritten by a newly seeded world.

## Detection and incident response

Proposed monitor rules: 3 consecutive readiness failures within 60 seconds;
snapshot older than 120 seconds; repeated unit restarts; sustained HTTP 429/401
on admin; unexpected successful admin activity. Route alerts to the VPS owner.
These are operating targets, not a claim that an external alert service is configured.

## Encrypted offsite backup

The selected destination is the existing encrypted Google Drive remote, scoped by
the job to `apps/elixir.micutu.com`. `deploy/setup-offsite.sh` installs the service,
performs a real upload/download verification and enables its six-hour timer.
Failed setup restores the previous managed files and timer enablement/activity;
files created only by an incomplete first install are removed during rollback.
It provisions only the crypt section and its Drive dependency from the operator's
rclone config; other remotes are not copied. Existing provider OAuth permissions
are unchanged. The root credential is `/etc/evolving-minds/backup-rclone.conf`, 0600.
systemd loads it into the offsite unit; refreshed tokens live in that unit's private
state directory. No credentials are committed, printed or included in world archives.

The offsite job runs as `evolving-minds-offsite`, separate from the web UID, with
read-only ACL access to local archives. The web process cannot read its credentials.
The local backup job is required to succeed before upload. The helper
`/usr/local/libexec/evolving-minds/stage-offsite.py` opens shared files with
O_NOFOLLOW, checks regular-file type, freshness, sizes and a strict checksum
record, then freezes the exact archive in the offsite UID's private state.
Compressed input is capped at 8 MB and expansion at 4 MB. Remote operations use
only that verified private copy, so changing a shared path cannot swap the upload
after validation. Each archive is uploaded,
downloaded through crypt, compared byte for byte and checked as gzip before its
checksum and `latest.json` manifest are published. Only matching application archives
older than 30 days in this exact remote prefix are pruned. `latest.json` is retained.

Recover without touching the live world:

```bash
sudo -u evolving-minds-offsite python3 deploy/fetch-offsite.py \
  --output /var/lib/evolving-minds-offsite/recovered-world.snapshot
```

The output must not already exist. The helper validates manifest fields, decrypted
size, checksum and gzip expansion limits. Validate the recovered ETF with the core
validator before installing it into stopped production. An archive fetched from
this remote was booted successfully in an isolated release during this session.

Inspect `systemctl status evolving-minds-offsite.service` and its timer for failures.
Sanitized status is published in `/var/lib/evolving-minds-offsite/status.json`,
readable by the app through a file-specific ACL. Credential and detailed error files
remain private. This status and the journal do not replace external alert delivery.

The authenticated `/admin/world` panel displays snapshot, local archive and offsite
freshness. Thresholds are 120 seconds, 30 hours and 8 hours respectively. Missing,
malformed, future-dated and failed-transfer records remain visibly unhealthy;
no transfer logs, filenames or credentials are sent to the browser. Checks refresh
with the admin world's normal updates. They establish freshness, not a fresh restore
test on every page view. The offsite writer independently verifies each transfer.

On suspected unauthorized control: disable public controls and admin credentials,
restart the unit to invalidate connected sessions, preserve logs and a private
snapshot copy, and isolate this vhost at Nginx/Cloudflare if abuse continues.
Rotate admin credentials and SECRET_KEY_BASE through the environment file when
compromise is suspected. The latter invalidates all browser sessions. Rebuild from
a reviewed revision and verify backups before restoring service. Review analytics
injection and other software running as the same Unix user when assessing exposure.

Do not publish logs containing credentials, cookies, query tokens or environment
values. There has been no destructive incident exercise on the live world in this
session. Local backups and simulated restoration tests do not establish recovery
from complete VPS loss; a separate host/storage restore exercise remains necessary.

A real local backup was additionally booted in an isolated release on loopback
port 4004 during this delivery, successfully restoring 7 minds. Production data
was not replaced. This confirms that artifact's restore path, not off-host disaster recovery.
