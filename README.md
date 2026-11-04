# Evolving Minds

An experimental artificial-life simulation built with **Elixir** and **Phoenix LiveView**. A population of "entities" (digital minds) runs as independent BEAM processes that interact, mutate their personality traits, die of exhaustion, and get replaced by new generations — all observable live in the browser.

## 🧠 Core Concept

Each entity is a `GenServer` with two inherited traits, **aggression** and **curiosity**, and a behavior function derived from them. Entities act on randomized timers and every interaction settles in **energy**: robbing a fleeing pacifist pays, wars bleed both sides, and knowledge-sharing between curious minds compounds. Run out of energy and you die — of exhaustion, or by someone's hand.

Behaviors are plain Elixir closures built from traits — the UI shows the equivalent source for each mind, but nothing is `eval`-ed at runtime.

### Key Features

- **A real interaction economy** (hawk–dove dynamics): fight/flee and reciprocity responses are trait thresholds, so selection pressure is frequency-dependent.
- **True inheritance**: reproduction draws parents proportionally to their energy; children carry jittered traits, a generation number, and their parent's id.
- **Environmental epochs**: the world cycles through abundance, normal, and famine, changing how expensive it is to act.
- **A persistent world**: the population, memories, epoch, and all-time records survive restarts and deploys via atomic snapshots.
- **Hall of Fame**: births, deaths by cause, mutations, max generation, and the oldest mind ever — remembered forever.
- **Dynasties**: rank retained families by living members, inspect generation records and focus a whole family while combining search, tribe and life filters. Pruned ancestors are marked explicitly.
- **Mind Dossier**: click any card for lineage, age, full memory stream, and the heuristic source it runs.
- **Visitor participation** (optional): node-wide, per-IP energy and spawn budgets that survive tabs and reconnects, plus a hard population cap.
- **Responsive observatory**: name/ID search, tribe and condition filters, rankings, trait map, interactive social network, trait and generation distributions.
- **Personal exploration**: browser-persisted watchlists, three-mind comparisons, observation pause and shareable dossiers.
- **Evolution Lab**: private seeded experiments with four scenarios, adjustable traits/environment, playback, inspection and safe JSON import/export. Keep six named snapshots locally, compare three with population traces, rename/remove/undo saves, and export history or comparisons as CSV. Three guided field missions track local milestones; share links reproduce the starting conditions without uploading experiment data.
- **Recovery health**: an authenticated, responsive administration panel shows snapshot, local archive and verified encrypted offsite freshness without exposing credentials or transfer logs.
- **Search and sharing**: canonical metadata, sitemap, robots directives, and a social preview image.
- **Crash-safe state**: a monitoring state store purges dead entities' state and memories no matter how they terminated.
- **Real-time dashboard**: LiveView streams fed by a single PubSub snapshot broadcaster — per-tick cost is constant in connected browsers, and only changed cards ship over the wire.
- **Admin god mode**: pause the world, force epochs, spawn or terminate minds, snapshot on demand, plus Phoenix LiveDashboard — all behind basic auth.

## 🛠️ Architecture

The repository is a small monorepo:

```
evolving_minds_core/   # the simulation library (no web dependencies)
evolving_minds/        # the Phoenix LiveView app, depends on core via path
```

### `evolving_minds_core`

| Module | Role |
| --- | --- |
| `EvolvingMinds.Entity` | The actor representing a single mind; resolves the interaction economy |
| `EvolvingMinds.MutationEngine` | Builds behavior closures (and display source) from traits; birth jitter |
| `EvolvingMinds.EvolutionEngine` | Seeds empty worlds; fitness-weighted reproduction |
| `EvolvingMinds.Environment` | Epoch cycling (abundance/normal/famine) via `:persistent_term` |
| `EvolvingMinds.Persistence` | Atomic world snapshots + restore at boot |
| `EvolvingMinds.AllTimeStats` | All-time records, fed by the simulation's telemetry |
| `EvolvingMinds.World` | Spawning, registry lookups, messaging, pause/resume |
| `EvolvingMinds.StateStore` | ETS state snapshots; monitors entities and purges on death |
| `EvolvingMinds.Memory` | ETS-backed interaction history with decay |
| `EvolvingMinds.Stats` / `GlobalEvents` | Trend history and the global event feed |

### `evolving_minds`

| Module | Role |
| --- | --- |
| `EvolvingMindsWeb.WorldPublisher` | Single 2s ticker broadcasting world snapshots over PubSub |
| `EvolvingMindsWeb.WorldLive` | The dashboard LiveView (streams grid, charts, dossier, about) |
| `EvolvingMindsWeb.AdminLive` | God-mode panel at `/admin/world` (basic auth) |
| `EvolvingMindsWeb.HealthController` | `GET /healthz` for monitoring |

## ⚙️ Development

The web application requires Elixir 1.15+; the tested production and CI toolchain is Elixir 1.18.3 / OTP 27. Node.js 24 is used for JavaScript and browser verification.

```bash
cd evolving_minds
mix setup        # deps + assets
mix phx.server   # http://localhost:4000
```

The dev server binds to `127.0.0.1` on purpose — on a remote machine, tunnel with `ssh -L 4000:localhost:4000 <host>`.

### Tests

```bash
(cd evolving_minds_core && mix test)
(cd evolving_minds && mix test)
```

Tests disable the Evolution Engine (`:start_evolution` config) so they control their world.
CI checks formatting, compilation warnings, Elixir tests, dependency advisories,
JavaScript simulation invariants, a production release, and real Chromium flows.
GitHub Actions use pinned revisions and read-only repository permissions.

```bash
node --test evolving_minds/assets/js/*.test.mjs
cd e2e
npm ci --ignore-scripts
npx playwright install chromium
npm test
```

Browser fixtures bind only to loopback, require `MIX_ENV=test`, and explicitly disable
persistence and evolution. They exercise responsive layouts, local watchlists,
shared dossiers, live DOM ordering, genealogy, lab replay/export/import, saved
comparisons, CSV escaping, undo and offline stepping. They do not use the production snapshot. To use an existing compatible
Chromium binary, set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`.

Audit findings and residual risks are in [Security audit](docs/SECURITY_AUDIT.md);
delivery stages and future work are in [Product plan](docs/PLAN.md).

## 🚀 Production

The active VPS runs `evolving-minds-canary.service` from this checkout, with
runtime configuration in `/etc/evolving-minds/evolving-minds.env` and persistent
data in `evolving_minds/data/`. Nginx and Cloudflare protect the origin.

```bash
./deploy/deploy.sh --build-only  # production build, no live service changes
./deploy/deploy.sh               # isolated release, world backup, atomic switch, readiness, rollback
```

Release payloads and rollback snapshots are private, ignored files in `.releases/`.
The `current` symlink selects the active release. The deploy script preserves the
existing systemd hardening and migrates the old release on its first run.
See [Operations](docs/OPERATIONS.md) for deployment, rollback and incident handling.

### Backups

The active `evolving-minds-backup.timer` runs daily, keeping verified gzip snapshots
and SHA-256 checksums locally in `/srv/backups/evolving-minds` for 14 days. An
optional off-host rclone script is included, but requires an explicit
`WORLD_BACKUP_REMOTE`; it is not the active backup mechanism on this VPS.

A backup on the same VPS does not protect against loss of the entire server.
Validate restoration and configure a separate storage destination before relying
on this as disaster recovery. Never restore over a running simulation.

### Runtime configuration

Environment-driven (`config/runtime.exs`), loaded by systemd from `.env.prod` (not committed):

| Variable | Purpose |
| --- | --- |
| `SECRET_KEY_BASE` | Required. Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Public hostname (drives `check_origin` and HSTS URLs) |
| `PORT` | HTTP port the app binds (default 4000) |
| `PHX_BIND_IP` | Bind address (default `127.0.0.1`, keep it behind the proxy) |
| `PHX_CHECK_ORIGIN` | Comma-separated origin allowlist (defaults to the host) |
| `PHX_SERVER` | Set to start the endpoint from a release |
| `WORLD_PUBLIC_CONTROLS` | Opt-in: lets visitors inject energy and spawn minds (rate limited) |
| `ADMIN_USER` / `ADMIN_PASS` | Enable `/admin/world` + `/admin/dashboard` (404 when unset) |
| `DNS_CLUSTER_QUERY` | Optional DNS-based clustering |


## 📦 The Data

Everything the world knows lives in one versioned snapshot (`data/world.snapshot`, Erlang External Term Format, written atomically). Real excerpts from the running world:

```elixir
%{
  version: 1,
  saved_at: ~U[2026-07-13 14:14:01Z],
  epoch: :famine,
  entities: [
    %{
      id: "EF7CA0491778174E",
      name: "Faeluvax",
      tribe: :solari,
      generation: 2,
      parent_id: "1745A426CBE9D561",
      traits: %{aggression: 0.488, curiosity: 0.243},
      energy: 27,
      kills: 0,
      born_at: 1783951971
    },
    # ...one per living mind (behavior closures are never serialized —
    # they rebuild from traits on restore)
  ],
  memories: [{"EF7CA049...", [greet: "1745A426...", attack: "140769..."]}, ...],
  ancestry: [
    # every mind that ever lived, pruned oldest-dead-first past 2000
    %{
      id: "FD2C01E2CF73612A",
      name: "Jorra",
      tribe: :solari,
      generation: 1,
      parent_id: nil,
      born_at: 1783951541,
      died_at: 1783951594,
      cause: :killed,
      killer_id: "140769461943CBD1"   # Oskien did it
    },
    # ...
  ],
  all_time: %{
    births: 4166,
    deaths: 4159,
    deaths_by_cause: %{killed: 2259, exhaustion: 1900},
    max_generation: 19,
    most_feared: %{id: "140769461943CBD1", name: "Oskien", kills: 3},
    # ...mutations, interactions, oldest, most_prolific
  }
}
```

## 🧪 Experiments

This is a playground for exploring emergent behavior in a concurrent, functional environment. The "intelligence" of the entities is procedural and randomized, designed to test the limits of actor-based simulation within the safety of the BEAM virtual machine.

---
Built with 💚, Elixir, and Phoenix.
