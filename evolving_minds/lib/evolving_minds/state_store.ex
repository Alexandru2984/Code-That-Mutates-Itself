defmodule EvolvingMinds.StateStore do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:entity_states, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{}}
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

  def handle_call({:update_state, id, entity_state}, _from, state) do
    :ets.insert(:entity_states, {id, entity_state})
    {:reply, :ok, state}
  end

  def handle_call({:remove_state, id}, _from, state) do
    :ets.delete(:entity_states, id)
    {:reply, :ok, state}
  end
end
