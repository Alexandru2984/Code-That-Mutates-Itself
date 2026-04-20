defmodule EvolvingMinds.Memory do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:entity_memories, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  def remember(entity_id, interaction) do
    current = case :ets.lookup(:entity_memories, entity_id) do
      [{^entity_id, memories}] -> memories
      [] -> []
    end
    # Decay: keep only last 100 memories
    new_memories = Enum.take([interaction | current], 100)
    :ets.insert(:entity_memories, {entity_id, new_memories})
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
        # Sort to treat (A->B) and (B->A) as the same connection if we want undirected,
        # but let's keep it directed for now or just count pairs.
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
end