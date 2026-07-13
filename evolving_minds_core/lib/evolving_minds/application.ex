defmodule EvolvingMinds.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Registry, keys: :unique, name: EvolvingMinds.EntityRegistry},
        EvolvingMinds.Memory,
        EvolvingMinds.StateStore,
        EvolvingMinds.GlobalEvents,
        EvolvingMinds.Stats,
        EvolvingMinds.AllTimeStats,
        EvolvingMinds.Ancestry,
        EvolvingMinds.Environment,
        {DynamicSupervisor, strategy: :one_for_one, name: EvolvingMinds.EntitySupervisor},
        # Persistence restores the world before the EvolutionEngine decides
        # whether seeding is needed, and snapshots it on shutdown (children
        # stop in reverse order, so entities are still alive when it saves).
        EvolvingMinds.Persistence
      ] ++ evolution_children()

    opts = [strategy: :one_for_one, name: EvolvingMinds.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # The EvolutionEngine seeds and continuously mutates the population.
  # Tests disable it so they run against a world they fully control.
  defp evolution_children do
    if Application.get_env(:evolving_minds_core, :start_evolution, true) do
      [EvolvingMinds.EvolutionEngine]
    else
      []
    end
  end
end
