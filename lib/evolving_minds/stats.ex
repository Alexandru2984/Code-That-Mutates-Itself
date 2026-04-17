defmodule EvolvingMinds.Stats do
  use GenServer

  alias EvolvingMinds.World

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :timer.send_interval(5000, :collect)
    {:ok, []}
  end

  def get_history(limit \\ 20) do
    GenServer.call(__MODULE__, {:get_history, limit})
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
      
      new_state = Enum.take([data_point | state], 100)
      {:noreply, new_state}
    end
  end

  def handle_call({:get_history, limit}, _from, state) do
    {:reply, Enum.take(state, limit), state}
  end

  defp avg([]), do: 0.0
  defp avg(list), do: Enum.sum(list) / length(list)
end
