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
    oldest: nil,
    most_feared: nil,
    most_prolific: nil,
    kills_by: %{},
    children_by: %{}
  }

  # kills_by/children_by are pruned so persisted snapshots stay small.
  @tally_cap 200
  @tally_keep 50

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
      |> record_child(metadata[:parent_id])

    {:noreply, state}
  end

  def handle_cast({:event, [:evolving_minds, :entity, :death], metadata}, state) do
    cause = Map.get(metadata, :cause, :exhaustion)
    age = Map.get(metadata, :age, 0)

    state =
      state
      |> Map.update!(:deaths, &(&1 + 1))
      |> update_in([:deaths_by_cause, cause], &((&1 || 0) + 1))
      |> record_oldest(metadata[:id], metadata[:name], age)
      |> record_kill(metadata[:killer_id], metadata[:killer_name])

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

  defp record_oldest(state, id, name, age) do
    case state.oldest do
      nil -> %{state | oldest: %{id: id, name: name, age: age}}
      %{age: record} when age > record -> %{state | oldest: %{id: id, name: name, age: age}}
      _ -> state
    end
  end

  defp record_kill(state, nil, _name), do: state

  defp record_kill(state, killer_id, killer_name) do
    kills_by =
      state.kills_by
      |> Map.update(killer_id, %{name: killer_name, count: 1}, fn entry ->
        %{entry | name: killer_name || entry.name, count: entry.count + 1}
      end)
      |> prune()

    entry = kills_by[killer_id]

    most_feared =
      case state.most_feared do
        %{kills: record} when record >= entry.count -> state.most_feared
        _ -> %{id: killer_id, name: entry.name, kills: entry.count}
      end

    %{state | kills_by: kills_by, most_feared: most_feared}
  end

  defp record_child(state, nil), do: state

  defp record_child(state, parent_id) do
    children_by =
      state.children_by
      |> Map.update(parent_id, %{name: nil, count: 1}, &%{&1 | count: &1.count + 1})
      |> prune()

    entry = children_by[parent_id]
    name = entry.name || lookup_name(parent_id)
    children_by = Map.put(children_by, parent_id, %{entry | name: name})

    most_prolific =
      case state.most_prolific do
        %{children: record} when record >= entry.count -> state.most_prolific
        _ -> %{id: parent_id, name: name, children: entry.count}
      end

    %{state | children_by: children_by, most_prolific: most_prolific}
  end

  defp lookup_name(id) do
    case EvolvingMinds.StateStore.get_state(id) do
      %{name: name} -> name
      _ -> nil
    end
  end

  defp prune(tally) when map_size(tally) > @tally_cap do
    tally
    |> Enum.sort_by(fn {_id, %{count: count}} -> count end, :desc)
    |> Enum.take(@tally_keep)
    |> Map.new()
  end

  defp prune(tally), do: tally
end
