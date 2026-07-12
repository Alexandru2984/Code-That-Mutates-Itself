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
        {DynamicSupervisor, strategy: :one_for_one, name: EvolvingMinds.EntitySupervisor}
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
