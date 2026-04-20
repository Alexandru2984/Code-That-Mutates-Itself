defmodule EvolvingMinds.StateStore do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:entity_states, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  def update_state(id, state) do
    :ets.insert(:entity_states, {id, state})
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
    :ets.delete(:entity_states, id)
  end
end
