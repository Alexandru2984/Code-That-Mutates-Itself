defmodule EvolvingMinds.Memory do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:entity_memories, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  def remember(entity_id, interaction) do
    GenServer.call(__MODULE__, {:remember, entity_id, interaction})
  end

  def forget(entity_id) do
    GenServer.call(__MODULE__, {:forget, entity_id})
  end

  @doc "Bulk-loads an entity's memories (world restores after restarts)."
  def restore(entity_id, memories) when is_list(memories) do
    GenServer.call(__MODULE__, {:restore, entity_id, memories})
  end

  def get_memories(entity_id) do
    case :ets.lookup(:entity_memories, entity_id) do
      [{^entity_id, memories}] -> memories
      [] -> []
    end
  end

  def get_top_interactions(limit \\ 5) do
    :ets.tab2list(:entity_memories)
    |> Enum.flat_map(fn {id, memories} ->
      Enum.map(memories, fn {type, sender} ->
        # Sort to treat both directions as the same social connection.
        pair = Enum.sort([id, sender])
        {pair, type}
      end)
    end)
    |> Enum.group_by(fn {pair, _} -> pair end)
    |> Enum.map(fn {pair, occurrences} ->
      {pair, length(occurrences)}
    end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(limit)
  end

  def handle_call({:remember, entity_id, interaction}, _from, state) do
    current =
      case :ets.lookup(:entity_memories, entity_id) do
        [{^entity_id, memories}] -> memories
        [] -> []
      end

    # Decay: keep only last 100 memories
    new_memories = Enum.take([interaction | current], 100)
    :ets.insert(:entity_memories, {entity_id, new_memories})
    {:reply, :ok, state}
  end

  def handle_call({:forget, entity_id}, _from, state) do
    :ets.delete(:entity_memories, entity_id)
    {:reply, :ok, state}
  end

  def handle_call({:restore, entity_id, memories}, _from, state) do
    :ets.insert(:entity_memories, {entity_id, Enum.take(memories, 100)})
    {:reply, :ok, state}
  end
end
