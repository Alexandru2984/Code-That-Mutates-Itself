defmodule EvolvingMinds.Environment do
  @moduledoc """
  The world's climate: epochs change how expensive it is to act.

  | epoch      | act cost |
  |------------|----------|
  | :abundance | 3        |
  | :normal    | 5        |
  | :famine    | 8        |

  The current epoch lives in `:persistent_term` so entities read it for
  free on every act. Epochs cycle automatically (weighted toward
  `:normal`) unless `:cycle_epochs` is disabled — tests and the admin
  panel drive it manually through `set_epoch/1`.
  """

  use GenServer
  require Logger

  @epochs [:abundance, :normal, :famine]
  @act_costs %{abundance: 3, normal: 5, famine: 8}
  @default_interval_ms 60_000
  @key {__MODULE__, :epoch}

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def current_epoch do
    :persistent_term.get(@key, :normal)
  end

  def act_cost do
    Map.fetch!(@act_costs, current_epoch())
  end

  def epochs, do: @epochs

  def set_epoch(epoch) when epoch in @epochs do
    GenServer.call(__MODULE__, {:set_epoch, epoch})
  end

  @impl true
  def init(_) do
    :persistent_term.put(@key, :normal)

    if Application.get_env(:evolving_minds_core, :cycle_epochs, true) do
      Process.send_after(self(), :cycle, interval_ms())
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call({:set_epoch, epoch}, _from, state) do
    apply_epoch(epoch)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cycle, state) do
    apply_epoch(random_epoch())
    Process.send_after(self(), :cycle, interval_ms())
    {:noreply, state}
  end

  defp apply_epoch(epoch) do
    previous = current_epoch()

    if epoch != previous do
      :persistent_term.put(@key, epoch)

      EvolvingMinds.GlobalEvents.report_event(%{
        type: :epoch_change,
        detail: epoch_narrative(epoch)
      })

      :telemetry.execute([:evolving_minds, :epoch, :change], %{count: 1}, %{
        epoch: epoch,
        previous: previous
      })

      Logger.info("Epoch shifted: #{previous} -> #{epoch}")
    end
  end

  defp epoch_narrative(:famine), do: "The world slipped into famine"
  defp epoch_narrative(:abundance), do: "An age of abundance began"
  defp epoch_narrative(:normal), do: "The world returned to balance"

  # Weighted toward stability: half the rolls keep the world normal.
  defp random_epoch do
    case :rand.uniform(4) do
      1 -> :abundance
      2 -> :famine
      _ -> :normal
    end
  end

  defp interval_ms do
    Application.get_env(:evolving_minds_core, :epoch_interval_ms, @default_interval_ms)
  end
end
