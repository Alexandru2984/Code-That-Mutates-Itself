defmodule EvolvingMinds.AllTimeStats do
  @moduledoc """
  The world's history book: all-time counters and records, fed by the
  simulation's own telemetry events and persisted with the snapshot.
  """

  use GenServer

  @handler_id "evolving-minds-all-time-stats"

  @events [
    [:evolving_minds, :entity, :spawn],
    [:evolving_minds, :entity, :death],
    [:evolving_minds, :entity, :mutation],
    [:evolving_minds, :entity, :interaction]
  ]

  @initial %{
    births: 0,
    deaths: 0,
    deaths_by_cause: %{exhaustion: 0, killed: 0},
    mutations: 0,
    interactions: %{attack: 0, greet: 0, share_knowledge: 0},
    max_generation: 1,
    oldest: nil
  }

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_stats, do: GenServer.call(__MODULE__, :get)

  @doc "Snapshot export for persistence."
  def export, do: get_stats()

  @doc "Restores counters from a persisted snapshot."
  def import(stats) when is_map(stats) do
    GenServer.call(__MODULE__, {:import, stats})
  end

  @doc false
  def handle_telemetry(event, _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:event, event, metadata})
  end

  @impl true
  def init(_) do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_telemetry/4, nil)
    {:ok, @initial}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  def handle_call({:import, stats}, _from, _state) do
    {:reply, :ok, Map.merge(@initial, stats)}
  end

  @impl true
  def handle_cast({:event, [:evolving_minds, :entity, :spawn], metadata}, state) do
    state =
      state
      |> Map.update!(:births, &(&1 + 1))
      |> Map.update!(:max_generation, &max(&1, Map.get(metadata, :generation, 1)))

    {:noreply, state}
  end

  def handle_cast({:event, [:evolving_minds, :entity, :death], metadata}, state) do
    cause = Map.get(metadata, :cause, :exhaustion)
    age = Map.get(metadata, :age, 0)

    state =
      state
      |> Map.update!(:deaths, &(&1 + 1))
      |> update_in([:deaths_by_cause, cause], &((&1 || 0) + 1))
      |> record_oldest(metadata[:id], age)

    {:noreply, state}
  end

  def handle_cast({:event, [:evolving_minds, :entity, :mutation], _metadata}, state) do
    {:noreply, Map.update!(state, :mutations, &(&1 + 1))}
  end

  def handle_cast({:event, [:evolving_minds, :entity, :interaction], metadata}, state) do
    type = Map.get(metadata, :type, :greet)
    {:noreply, update_in(state, [:interactions, type], &((&1 || 0) + 1))}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  defp record_oldest(state, id, age) do
    case state.oldest do
      nil -> %{state | oldest: %{id: id, age: age}}
      %{age: record} when age > record -> %{state | oldest: %{id: id, age: age}}
      _ -> state
    end
  end
end
