# EvolvingMinds Core

The simulation library for [Evolving Minds](../README.md): entities, mutation, evolution, world messaging, and the ETS-backed stores — with no web dependencies.

The Phoenix app in `../evolving_minds` consumes this as a path dependency; the library also runs standalone:

```bash
mix deps.get
iex -S mix
```

```elixir
iex> EvolvingMinds.spawn_entity("my-mind")
iex> EvolvingMinds.get_all_entities()
iex> EvolvingMinds.StateStore.get_state("my-mind")
```

The supervision tree starts the registry, stores, entity supervisor, and — unless `config :evolving_minds_core, start_evolution: false` (used by tests) — the Evolution Engine, which seeds and replenishes the population.

## Tests

```bash
mix test
```
