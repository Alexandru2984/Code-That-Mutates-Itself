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
- **Mind Dossier**: click any card for lineage, age, full memory stream, and the heuristic source it runs.
- **Visitor participation** (optional): rate-limited energy injections and mind-spawning for the public.
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

Prerequisites: Elixir 1.14+ / OTP 25+ (CI runs 1.18 / OTP 27).

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

Tests disable the Evolution Engine (`:start_evolution` config) so they run against a world they fully control. CI enforces `mix format --check-formatted`, `mix compile --warnings-as-errors`, and both test suites.

## 🚀 Production

The app ships as a **mix release** managed by systemd behind Nginx (WebSocket proxying for LiveView) with TLS via Let's Encrypt/Certbot. Everything deploy-related is versioned in `deploy/`:

```bash
./deploy/deploy.sh   # deps + prod compile + assets + release + unit sync + restart + health check
```

Runtime configuration is environment-driven (`config/runtime.exs`), loaded by systemd from `.env.prod` (not committed):

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


## 🧪 Experiments

This is a playground for exploring emergent behavior in a concurrent, functional environment. The "intelligence" of the entities is procedural and randomized, designed to test the limits of actor-based simulation within the safety of the BEAM virtual machine.

---
Built with 💚, Elixir, and Phoenix.
