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
      case restore() do
        :corrupt ->
          {:stop, :invalid_snapshot}

        _ ->
          Process.send_after(self(), :save, @save_interval_ms)
          {:ok, %{}}
      end
    else
      {:ok, %{}}
    end
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
      |> Enum.map(
        &Map.take(&1, [
          :id,
          :name,
          :tribe,
          :traits,
          :energy,
          :generation,
          :parent_id,
          :born_at,
          :kills
        ])
      )

    ids = MapSet.new(entities, & &1.id)

    snapshot = %{
      version: @version,
      saved_at: DateTime.utc_now(),
      epoch: Environment.current_epoch(),
      entities: entities,
      memories:
        Enum.filter(:ets.tab2list(:entity_memories), fn {id, _} -> MapSet.member?(ids, id) end),
      all_time: EvolvingMinds.AllTimeStats.export(),
      ancestry: EvolvingMinds.Ancestry.export()
    }

    file = path()
    tmp = file <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(file)),
         :ok <- File.write(tmp, :erlang.term_to_binary(snapshot), [:sync]),
         :ok <- File.chmod(tmp, 0o600),
         :ok <- File.rename(tmp, file) do
      :ok
    else
      error ->
        Logger.warning("World snapshot failed: #{inspect(error)}")
        error
    end
  end

  defp restore do
    with {:ok, snapshot} <- EvolvingMinds.Snapshot.read(path()),
         true <- World.get_all_entities() == [] do
      for entity <- snapshot.entities do
        World.spawn_entity(Keyword.new(entity))
      end

      for {id, memories} <- snapshot.memories do
        Memory.restore(id, memories)
      end

      if all_time = Map.get(snapshot, :all_time) do
        EvolvingMinds.AllTimeStats.import(all_time)
      end

      if ancestry = Map.get(snapshot, :ancestry) do
        EvolvingMinds.Ancestry.import(ancestry)
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

      false ->
        {:error, :world_not_empty}

      other ->
        Logger.warning(
          "World snapshot rejected (invalid data or unavailable file): #{inspect(other)}"
        )

        :corrupt
    end
  end
end
