defmodule EvolvingMinds.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: EvolvingMinds.EntityRegistry},
      EvolvingMinds.Memory,
      {DynamicSupervisor, strategy: :one_for_one, name: EvolvingMinds.EntitySupervisor},
      EvolvingMinds.EvolutionEngine
    ]

    opts = [strategy: :one_for_one, name: EvolvingMinds.Supervisor]
    Supervisor.start_link(children, opts)
  end
end