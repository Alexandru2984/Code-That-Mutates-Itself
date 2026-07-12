defmodule EvolvingMinds.StateStore do
  @moduledoc """
  ETS-backed store of the latest observable state of every entity.

  Reads go straight to ETS; writes are serialized through this process.
  The store monitors every process that writes an entity state and purges
  that entity's state and memories when the writer terminates for any
  reason, so crashed entities cannot leave ghost entries behind.
  """

  use GenServer

  alias EvolvingMinds.Memory

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(:entity_states, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{refs: %{}, ids: %{}}}
  end

  def update_state(id, state) do
    GenServer.call(__MODULE__, {:update_state, id, state})
  end

  def get_state(id) do
    case :ets.lookup(:entity_states, id) do
      [{^id, state}] -> state
      [] -> nil
    end
  end

  def get_all_states() do
    :ets.tab2list(:entity_states) |> Enum.map(fn {_, state} -> state end)
  end

  def remove_state(id) do
    GenServer.call(__MODULE__, {:remove_state, id})
  end

  @impl true
  def handle_call({:update_state, id, entity_state}, {caller, _tag}, state) do
    :ets.insert(:entity_states, {id, entity_state})
    {:reply, :ok, track(state, id, caller)}
  end

  def handle_call({:remove_state, id}, _from, state) do
    :ets.delete(:entity_states, id)
    {:reply, :ok, untrack(state, id)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {id, refs} ->
        :ets.delete(:entity_states, id)
        Memory.forget(id)
        {:noreply, %{state | refs: refs, ids: Map.delete(state.ids, id)}}
    end
  end

  # Monitor the writer once per entity id so any kind of termination
  # (normal death or crash) triggers a purge.
  defp track(state, id, pid) do
    if Map.has_key?(state.ids, id) do
      state
    else
      ref = Process.monitor(pid)
      %{state | refs: Map.put(state.refs, ref, id), ids: Map.put(state.ids, id, ref)}
    end
  end

  defp untrack(state, id) do
    case Map.pop(state.ids, id) do
      {nil, _ids} ->
        state

      {ref, ids} ->
        Process.demonitor(ref, [:flush])
        %{state | ids: ids, refs: Map.delete(state.refs, ref)}
    end
  end
end
