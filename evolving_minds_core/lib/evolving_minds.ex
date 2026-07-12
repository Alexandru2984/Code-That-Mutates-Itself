defmodule EvolvingMinds do
  @moduledoc """
  Public API for the Evolving Minds simulation.

  The simulation runs a population of `EvolvingMinds.Entity` processes
  supervised under a `DynamicSupervisor`. Entities act on timers, exchange
  messages, mutate their traits, and eventually die of exhaustion, at which
  point the `EvolvingMinds.EvolutionEngine` replenishes the population.

  Observers read world state through `EvolvingMinds.StateStore`,
  `EvolvingMinds.Memory`, `EvolvingMinds.Stats`, and
  `EvolvingMinds.GlobalEvents`.
  """

  defdelegate spawn_entity(), to: EvolvingMinds.World
  defdelegate spawn_entity(id), to: EvolvingMinds.World
  defdelegate get_all_entities(), to: EvolvingMinds.World
  defdelegate send_message(target_id, type, sender_id), to: EvolvingMinds.World
  defdelegate inject_energy(target_id), to: EvolvingMinds.World
end
