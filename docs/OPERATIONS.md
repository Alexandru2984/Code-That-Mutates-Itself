# Operations and recovery

## Runtime inventory

- Unit: `evolving-minds-canary.service`, user/group `micu`.
- Environment: `/etc/evolving-minds/evolving-minds.env` (root:micu, 0640).
- HTTP origin: `127.0.0.1:4001`. The public hostname is `elixir.micutu.com`.
- Working directory: `evolving_minds/`; world: `data/world.snapshot`, 0600.
- Release: `current` symlink → private `.releases/<time>-<revision>`.
- Nginx site: `/etc/nginx/sites-available/elixir.micutu.com`.
- Local backups: `/srv/backups/evolving-minds`, daily systemd timer, 14 days.

## Deploy

Run both test suites, formatting checks and `mix hex.audit` before deploying.
`deploy/deploy.sh --build-only` compiles a real production release without stopping
the running service. `deploy/deploy.sh` builds a separate payload, saves the world,
stops the existing unit gracefully, copies its final snapshot, installs the rendered
unit, switches `current` atomically, and requires a successful readiness response.
Failure rolls back to the preceding release. The script never overwrites the active
release while building. Retain at least one verified older payload and snapshot.

Overrides: `EVOLVING_MINDS_SERVICE`, `EVOLVING_MINDS_ENV`, `EVOLVING_MINDS_USER`,
`EVOLVING_MINDS_GROUP`. The trusted environment file uses shell-compatible
`KEY=value` syntax. Keep shell tracing disabled. Do not paste its contents in logs.

The versioned Nginx files belong to this vhost only. Install `nginx-limits.conf`
under `/etc/nginx/conf.d/evolving-minds-limits.conf` and `nginx-proxy.conf` under
`/etc/nginx/snippets/evolving-minds-proxy.conf` before installing `nginx.conf` as the
site file. Back up existing files first. Run `sudo nginx -t` before reloading;
restore the copies if validation fails. Preserve the shared Cloudflare real_ip
configuration and origin allowlist. Do not modify other domains.

After deploy check HTTPS `/`, `/tree`, `/healthz`, `/robots.txt`, `/sitemap.xml`,
an unauthenticated `/admin/world`, cookie flags, and an actual LiveView connection.
Review recent unit logs for snapshot restore errors and restarts.

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
persistence and evolution disabled. Copy it to `data/world.snapshot` as `micu`,
mode 0600, then start the service and check the restore count and readiness.
Snapshots are ETF data, never executable imports. Compressed ETF is rejected;
decompress the backup's gzip wrapper first. Malformed snapshots fail startup so
they cannot silently be overwritten by a newly seeded world.

## Detection and incident response

Proposed monitor rules: 3 consecutive readiness failures within 60 seconds;
snapshot older than 120 seconds; repeated unit restarts; sustained HTTP 429/401
on admin; unexpected successful admin activity. Route alerts to the VPS owner.
These are operating targets, not a claim that an external alert service is configured.

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
