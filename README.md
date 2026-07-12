# Evolving Minds

An experimental artificial-life simulation built with **Elixir** and **Phoenix LiveView**. A population of "entities" (digital minds) runs as independent BEAM processes that interact, mutate their personality traits, die of exhaustion, and get replaced by new generations — all observable live in the browser.

## 🧠 Core Concept

Each entity is a `GenServer` with two traits, **aggression** and **curiosity**, and a behavior function derived from them. Entities act on randomized timers: they greet or attack a random peer, occasionally mutate their traits (and with them, their behavior), and spend energy doing it. When energy runs out, the entity dies and the Evolution Engine keeps the population alive with fresh spawns.

Behaviors are plain Elixir closures built from traits — the UI shows the equivalent source for each mind, but nothing is `eval`-ed at runtime.

### Key Features

- **Trait-driven behavior**: each mind's message handling is generated from its traits and regenerated when mutations push traits across thresholds.
- **Emergent social graph**: entities exchange native BEAM messages (greet, attack, share knowledge); the dashboard surfaces the strongest connections.
- **Energy & decay**: actions cost energy; death and reproduction keep the population evolving.
- **Crash-safe state**: a monitoring state store purges dead entities' state and memories no matter how they terminated.
- **Real-time dashboard**: a Phoenix LiveView UI fed by a single PubSub snapshot broadcaster — cost per tick is constant regardless of how many browsers are watching.

## 🛠️ Architecture

The repository is a small monorepo:

```
evolving_minds_core/   # the simulation library (no web dependencies)
evolving_minds/        # the Phoenix LiveView app, depends on core via path
```

### `evolving_minds_core`

| Module | Role |
| --- | --- |
| `EvolvingMinds.Entity` | The actor representing a single mind |
| `EvolvingMinds.MutationEngine` | Builds behavior closures (and display source) from traits |
| `EvolvingMinds.EvolutionEngine` | Seeds and replenishes the population |
| `EvolvingMinds.World` | Spawning, registry lookups, message passing |
| `EvolvingMinds.StateStore` | ETS state snapshots; monitors entities and purges on death |
| `EvolvingMinds.Memory` | ETS-backed interaction history with decay |
| `EvolvingMinds.Stats` / `GlobalEvents` | Trend history and the global event feed |

### `evolving_minds`

| Module | Role |
| --- | --- |
| `EvolvingMindsWeb.WorldPublisher` | Single 2s ticker broadcasting world snapshots over PubSub |
| `EvolvingMindsWeb.WorldLive` | The dashboard LiveView (subscribes to snapshots) |
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

The app runs behind Nginx (WebSocket proxying for LiveView) with TLS via Let's Encrypt/Certbot. Runtime configuration is environment-driven (`config/runtime.exs`):

| Variable | Purpose |
| --- | --- |
| `SECRET_KEY_BASE` | Required. Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Public hostname (drives `check_origin` and HSTS URLs) |
| `PORT` | HTTP port the app binds (default 4000) |
| `PHX_BIND_IP` | Bind address (default `127.0.0.1`, keep it behind the proxy) |
| `PHX_CHECK_ORIGIN` | Comma-separated origin allowlist (defaults to the host) |
| `PHX_SERVER` | Set to start the endpoint from a release |
| `WORLD_PUBLIC_CONTROLS` | Opt-in: lets visitors inject energy into entities |
| `DNS_CLUSTER_QUERY` | Optional DNS-based clustering |

Build assets before deploying: `mix assets.deploy`.

## 🧪 Experiments

This is a playground for exploring emergent behavior in a concurrent, functional environment. The "intelligence" of the entities is procedural and randomized, designed to test the limits of actor-based simulation within the safety of the BEAM virtual machine.

---
Built with 💚, Elixir, and Phoenix.
