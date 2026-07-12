defmodule EvolvingMinds.Persistence do
  @moduledoc """
  Makes the world survive restarts.

  Periodically (and on graceful shutdown) writes an atomic snapshot of
  the population — traits, energy, lineage, memories, epoch — and
  restores it at boot, respawning every mind exactly where it left off.
  Behavior closures are never serialized; they are rebuilt from traits.

  Disabled in tests (`:persistence` config); `save_now/0` and
  `restore_now/0` drive it manually there and from the admin panel.
  """

  use GenServer
  require Logger

  alias EvolvingMinds.Environment
  alias EvolvingMinds.Memory
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  @save_interval_ms 30_000
  @version 1

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def save_now, do: GenServer.call(__MODULE__, :save)
  def restore_now, do: GenServer.call(__MODULE__, :restore)

  @impl true
  def init(_) do
    # Trap exits so terminate/2 runs and we snapshot on graceful shutdown.
    Process.flag(:trap_exit, true)

    if enabled?() do
      restore()
      Process.send_after(self(), :save, @save_interval_ms)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call(:save, _from, state), do: {:reply, save(), state}
  def handle_call(:restore, _from, state), do: {:reply, restore(), state}

  @impl true
  def handle_info(:save, state) do
    save()
    Process.send_after(self(), :save, @save_interval_ms)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    if enabled?(), do: save()
    :ok
  end

  defp enabled? do
    Application.get_env(:evolving_minds_core, :persistence, true)
  end

  defp path do
    Application.get_env(:evolving_minds_core, :snapshot_path, "data/world.snapshot")
  end

  defp save do
    entities =
      StateStore.get_all_states()
      |> Enum.map(&Map.take(&1, [:id, :traits, :energy, :generation, :parent_id, :born_at]))

    snapshot = %{
      version: @version,
      saved_at: DateTime.utc_now(),
      epoch: Environment.current_epoch(),
      entities: entities,
      memories: :ets.tab2list(:entity_memories),
      all_time: EvolvingMinds.AllTimeStats.export()
    }

    file = path()
    tmp = file <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(file)),
         :ok <- File.write(tmp, :erlang.term_to_binary(snapshot)),
         :ok <- File.rename(tmp, file) do
      :ok
    else
      error ->
        Logger.warning("World snapshot failed: #{inspect(error)}")
        error
    end
  end

  defp restore do
    with {:ok, binary} <- File.read(path()),
         %{version: @version} = snapshot <- decode(binary) do
      for entity <- snapshot.entities do
        World.spawn_entity(Keyword.new(entity))
      end

      for {id, memories} <- snapshot.memories do
        Memory.restore(id, memories)
      end

      if all_time = Map.get(snapshot, :all_time) do
        EvolvingMinds.AllTimeStats.import(all_time)
      end

      Environment.set_epoch(snapshot.epoch)

      Logger.info(
        "World restored: #{length(snapshot.entities)} minds " <>
          "from snapshot taken at #{snapshot.saved_at}"
      )

      {:ok, length(snapshot.entities)}
    else
      {:error, :enoent} ->
        :no_snapshot

      other ->
        Logger.warning("World snapshot unreadable, starting fresh: #{inspect(other)}")
        :corrupt
    end
  end

  defp decode(binary) do
    :erlang.binary_to_term(binary)
  rescue
    _ -> :corrupt
  end
end
