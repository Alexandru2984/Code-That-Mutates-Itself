defmodule EvolvingMinds.GlobalEvents do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, []}
  end

  def report_event(event) do
    GenServer.cast(__MODULE__, {:report, event})
  end

  def get_recent_events(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_recent, limit})
  end

  def handle_cast({:report, event}, state) do
    timestamp = DateTime.utc_now()
    new_event = Map.put(event, :timestamp, timestamp)
    new_state = Enum.take([new_event | state], 50) # Keep last 50
    {:noreply, new_state}
  end

  def handle_call({:get_recent, limit}, _from, state) do
    {:reply, Enum.take(state, limit), state}
  end
end
