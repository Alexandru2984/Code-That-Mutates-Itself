defmodule EvolvingMinds.PersistenceTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.Memory
  alias EvolvingMinds.Persistence
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "em-snapshot-#{System.unique_integer([:positive])}"
      )

    previous = Application.get_env(:evolving_minds_core, :snapshot_path)
    Application.put_env(:evolving_minds_core, :snapshot_path, tmp)

    on_exit(fn ->
      File.rm(tmp)

      if previous do
        Application.put_env(:evolving_minds_core, :snapshot_path, previous)
      else
        Application.delete_env(:evolving_minds_core, :snapshot_path)
      end
    end)

    %{tmp: tmp}
  end

  test "round-trips the world across a wipe" do
    id = "PRST-#{System.unique_integer([:positive])}"
    traits = %{aggression: 0.42, curiosity: 0.24}

    {:ok, pid} = World.spawn_entity(id, traits: traits, generation: 3)

    on_exit(fn ->
      case Registry.lookup(EvolvingMinds.EntityRegistry, id) do
        [{live_pid, _}] ->
          DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, live_pid)

        [] ->
          :ok
      end
    end)

    World.adjust_energy(id, -40)
    assert eventually(fn -> StateStore.get_state(id).energy == 60 end)
    Memory.remember(id, {:greet, "old-friend"})

    assert :ok = Persistence.save_now()

    # Wipe: stop the entity (terminate_child sends :shutdown, which
    # transient children do NOT restart from) and wait for the purge.
    :ok = DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
    assert eventually(fn -> StateStore.get_state(id) == nil end)
    # The memory purge follows the state purge inside the same :DOWN
    # handler, so it can lag by a call round-trip.
    assert eventually(fn -> Memory.get_memories(id) == [] end)

    assert {:ok, restored} = Persistence.restore_now()
    assert restored >= 1

    assert eventually(fn -> StateStore.get_state(id) != nil end)
    state = StateStore.get_state(id)
    assert state.energy == 60
    assert state.traits == traits
    assert state.generation == 3
    assert is_function(state.behavior_fn, 1)

    assert Memory.get_memories(id) == [{:greet, "old-friend"}]
  end

  test "restore without a snapshot is a clean no-op" do
    assert Persistence.restore_now() == :no_snapshot
  end

  test "a corrupt snapshot is ignored", %{tmp: tmp} do
    File.write!(tmp, "definitely not a snapshot")
    assert Persistence.restore_now() == :corrupt
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(20)
        eventually(fun, attempts - 1)
    end
  end
end
