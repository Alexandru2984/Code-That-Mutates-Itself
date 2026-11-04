defmodule EvolvingMindsWeb.RateLimiter do
  @moduledoc "Bounded, node-wide sliding windows shared by all HTTP and LiveView connections."
  use GenServer

  @max_keys 10_000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def allow?(key, limit, window_ms) do
    GenServer.call(__MODULE__, {:allow, key, limit, window_ms})
  end

  @impl true
  def init(state) do
    Process.send_after(self(), :prune, 60_000)
    {:ok, state}
  end

  @impl true
  def handle_call({:allow, key, limit, window}, _from, state) do
    now = System.monotonic_time(:millisecond)
    {history, _expiry} = Map.get(state, key, {[], now})
    recent = Enum.filter(history, &(&1 > now - window))

    if length(recent) >= limit or (not Map.has_key?(state, key) and map_size(state) >= @max_keys) do
      {:reply, false, state}
    else
      {:reply, true, Map.put(state, key, {[now | recent], now + window})}
    end
  end

  @impl true
  def handle_info(:prune, state) do
    now = System.monotonic_time(:millisecond)
    Process.send_after(self(), :prune, 60_000)
    {:noreply, Map.reject(state, fn {_key, {_history, expiry}} -> expiry <= now end)}
  end
end
