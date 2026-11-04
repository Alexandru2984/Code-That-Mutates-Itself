defmodule EvolvingMindsWeb.WorldPublisher do
  @moduledoc """
  Single world ticker for the UI.

  Every `@interval` it builds one snapshot of the simulation and broadcasts
  it over PubSub to every connected LiveView, instead of each client polling
  the stores on its own timer. Snapshot cost is therefore O(1) in the number
  of connected clients.
  """

  use GenServer

  alias EvolvingMinds.GlobalEvents
  alias EvolvingMinds.Memory
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.Stats

  @topic "world:update"
  @interval 2_000
  @memories_per_entity 2

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(EvolvingMinds.PubSub, @topic)
  end

  def current_snapshot do
    case :ets.lookup(__MODULE__, :snapshot) do
      [{:snapshot, snapshot, _at}] -> snapshot
      [] -> snapshot()
    end
  end

  def ready? do
    case :ets.lookup(__MODULE__, :snapshot) do
      [{:snapshot, _, at}] -> System.monotonic_time(:millisecond) - at < 15_000
      _ -> false
    end
  rescue
    ArgumentError -> false
  end

  @doc """
  Builds the current world snapshot on demand (used for first render and
  for immediate feedback after user actions).
  """
  def snapshot do
    entities =
      StateStore.get_all_states()
      # The compiled behavior closure is process-internal; the UI only
      # renders the source, so keep it out of broadcast payloads.
      |> Enum.map(&Map.delete(&1, :behavior_fn))

    %{
      entities: entities,
      memories:
        Map.new(entities, fn entity ->
          {entity.id, Enum.take(Memory.get_memories(entity.id), @memories_per_entity)}
        end),
      global_events: GlobalEvents.get_recent_events(30),
      stats: Stats.get_history(),
      top_interactions: Stats.get_top_interactions(),
      epoch: EvolvingMinds.Environment.current_epoch(),
      all_time: EvolvingMinds.AllTimeStats.get_stats() |> Map.drop([:kills_by, :children_by])
    }
  end

  @impl true
  def init(state) do
    :ets.new(__MODULE__, [:named_table, :protected, read_concurrency: true])
    :ets.insert(__MODULE__, {:snapshot, snapshot(), System.monotonic_time(:millisecond)})
    :timer.send_interval(@interval, :tick)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    snapshot = snapshot()
    :ets.insert(__MODULE__, {:snapshot, snapshot, System.monotonic_time(:millisecond)})
    Phoenix.PubSub.broadcast(EvolvingMinds.PubSub, @topic, {:world_update, snapshot})
    {:noreply, state}
  end
end
