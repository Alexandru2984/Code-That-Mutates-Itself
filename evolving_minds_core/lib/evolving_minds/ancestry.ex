defmodule EvolvingMinds.Ancestry do
  @moduledoc """
  The book of every mind that ever lived: name, lineage, life span, and
  fate — fed by the simulation's telemetry and persisted with the world.

  Records are pruned oldest-dead-first once the book grows past its cap,
  so dynasties stay readable and snapshots stay small.
  """

  use GenServer

  @handler_id "evolving-minds-ancestry"

  @events [
    [:evolving_minds, :entity, :spawn],
    [:evolving_minds, :entity, :death]
  ]

  @cap 2000
  @keep 1200
  @max_lineage_depth 30

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get(id) do
    case :ets.lookup(:ancestry, id) do
      [{^id, record}] -> record
      [] -> nil
    end
  end

  @doc "Walks the parent chain starting from (and including) `id`."
  def lineage(id), do: lineage(id, @max_lineage_depth, [])

  defp lineage(nil, _depth, acc), do: Enum.reverse(acc)
  defp lineage(_id, 0, acc), do: Enum.reverse(acc)

  defp lineage(id, depth, acc) do
    case get(id) do
      nil -> Enum.reverse(acc)
      record -> lineage(record.parent_id, depth - 1, [record | acc])
    end
  end

  def children(id) do
    :ets.match_object(:ancestry, {:_, %{parent_id: id}})
    |> Enum.map(fn {_id, record} -> record end)
    |> Enum.sort_by(& &1.born_at)
  end

  def all do
    :ets.tab2list(:ancestry) |> Enum.map(fn {_id, record} -> record end)
  end

  @doc "Snapshot export for persistence."
  def export, do: all()

  @doc "Restores records from a persisted snapshot."
  def import(records) when is_list(records) do
    GenServer.call(__MODULE__, {:import, records})
  end

  @doc false
  def handle_telemetry(event, _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:event, event, metadata})
  end

  @impl true
  def init(_) do
    :ets.new(:ancestry, [:set, :protected, :named_table, read_concurrency: true])
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_telemetry/4, nil)
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  @impl true
  def handle_call({:import, records}, _from, state) do
    for record <- records, do: :ets.insert(:ancestry, {record.id, record})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:event, [:evolving_minds, :entity, :spawn], metadata}, state) do
    record = %{
      id: metadata.id,
      name: metadata[:name],
      tribe: metadata[:tribe],
      parent_id: metadata[:parent_id],
      generation: Map.get(metadata, :generation, 1),
      born_at: System.system_time(:second),
      died_at: nil,
      cause: nil,
      killer_id: nil
    }

    :ets.insert(:ancestry, {record.id, record})
    prune()
    {:noreply, state}
  end

  def handle_cast({:event, [:evolving_minds, :entity, :death], metadata}, state) do
    case get(metadata.id) do
      nil ->
        :ok

      record ->
        :ets.insert(
          :ancestry,
          {record.id,
           %{
             record
             | died_at: System.system_time(:second),
               cause: metadata[:cause],
               killer_id: metadata[:killer_id]
           }}
        )
    end

    {:noreply, state}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  defp prune do
    size = :ets.info(:ancestry, :size)

    if size > @cap do
      :ets.tab2list(:ancestry)
      |> Enum.filter(fn {_id, record} -> record.died_at end)
      |> Enum.sort_by(fn {_id, record} -> record.died_at end)
      |> Enum.take(size - @keep)
      |> Enum.each(fn {id, _record} -> :ets.delete(:ancestry, id) end)
    end
  end
end
