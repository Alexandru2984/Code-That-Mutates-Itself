defmodule EvolvingMinds.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: EvolvingMinds.EntityRegistry},
      EvolvingMinds.Memory,
      EvolvingMinds.StateStore,
      EvolvingMinds.GlobalEvents,
      EvolvingMinds.Stats,
      {DynamicSupervisor, strategy: :one_for_one, name: EvolvingMinds.EntitySupervisor},
      EvolvingMinds.EvolutionEngine
    ]

    opts = [strategy: :one_for_one, name: EvolvingMinds.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
