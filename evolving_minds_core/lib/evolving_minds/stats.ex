defmodule EvolvingMinds.Stats do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :timer.send_interval(5000, :collect)
    {:ok, %{history: [], top_interactions: []}}
  end

  def get_history(limit \\ 20) do
    GenServer.call(__MODULE__, {:get_history, limit})
  end

  def get_top_interactions(limit \\ 5) do
    GenServer.call(__MODULE__, {:get_top_interactions, limit})
  end

  def handle_info(:collect, state) do
    entities = EvolvingMinds.StateStore.get_all_states()

    if entities == [] do
      {:noreply, state}
    else
      avg_aggression = Enum.map(entities, & &1.traits.aggression) |> avg()
      avg_curiosity = Enum.map(entities, & &1.traits.curiosity) |> avg()

      data_point = %{
        timestamp: DateTime.utc_now(),
        avg_aggression: avg_aggression,
        avg_curiosity: avg_curiosity,
        population: length(entities)
      }

      new_history = Enum.take([data_point | state.history], 100)
      new_top = EvolvingMinds.Memory.get_top_interactions()
      {:noreply, %{state | history: new_history, top_interactions: new_top}}
    end
  end

  def handle_call({:get_history, limit}, _from, state) do
    {:reply, Enum.take(state.history, limit), state}
  end

  def handle_call({:get_top_interactions, limit}, _from, state) do
    {:reply, Enum.take(state.top_interactions, limit), state}
  end

  defp avg([]), do: 0.0
  defp avg(list), do: Enum.sum(list) / length(list)
end
