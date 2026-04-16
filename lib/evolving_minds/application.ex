defmodule EvolvingMinds.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EvolvingMindsWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:evolving_minds, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EvolvingMinds.PubSub},
      {Registry, keys: :unique, name: EvolvingMinds.EntityRegistry},
      EvolvingMinds.Memory,
      {DynamicSupervisor, strategy: :one_for_one, name: EvolvingMinds.EntitySupervisor},
      EvolvingMinds.EvolutionEngine,
      # Start to serve requests, typically the last entry
      EvolvingMindsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EvolvingMinds.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EvolvingMindsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
