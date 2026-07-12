defmodule EvolvingMinds.StateStoreTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.Memory
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  test "purges state and memories when a writer dies abnormally" do
    entity_id = "crash-test-#{System.unique_integer([:positive])}"

    # An unsupervised writer: unlike a supervised entity, nothing restarts
    # it, so the purge is the only thing that can touch the row.
    writer = spawn_writer(entity_id, %{id: entity_id, energy: 50})
    Memory.remember(entity_id, {:greet, "someone"})

    assert StateStore.get_state(entity_id) != nil
    assert Memory.get_memories(entity_id) != []

    Process.exit(writer, :kill)

    # The purge is asynchronous; wait for the monitor in StateStore to fire.
    assert eventually(fn -> StateStore.get_state(entity_id) == nil end)
    assert eventually(fn -> Memory.get_memories(entity_id) == [] end)
  end

  test "a new writer takes over an id without being purged by the old writer's death" do
    entity_id = "takeover-test-#{System.unique_integer([:positive])}"

    # Two live writers for the same id: the second write re-points the
    # monitor, exactly what happens when a supervisor restarts an entity
    # before the old incarnation's :DOWN is processed.
    old_writer = spawn_writer(entity_id, %{id: entity_id, energy: 10})
    _new_writer = spawn_writer(entity_id, %{id: entity_id, energy: 99})

    Process.exit(old_writer, :kill)

    # The old writer's death must not purge the new writer's state.
    Process.sleep(100)
    assert %{energy: 99} = StateStore.get_state(entity_id)
  end

  test "purges state and memories on natural death (stop :normal)" do
    entity_id = "death-test-#{System.unique_integer([:positive])}"

    {:ok, pid} = World.spawn_entity(entity_id)
    assert StateStore.get_state(entity_id) != nil

    ref = Process.monitor(pid)
    DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

    assert eventually(fn -> StateStore.get_state(entity_id) == nil end)
  end

  test "stores and removes entity state through the owner process" do
    entity_id = "state-test-#{System.unique_integer([:positive])}"
    state = %{id: entity_id, energy: 42}

    assert :ok = StateStore.update_state(entity_id, state)
    assert StateStore.get_state(entity_id) == state

    assert :ok = StateStore.remove_state(entity_id)
    assert StateStore.get_state(entity_id) == nil
  end

  # Spawns an unsupervised process that writes the given state and then
  # sleeps until killed. Returns once the write has landed.
  defp spawn_writer(entity_id, entity_state) do
    parent = self()

    writer =
      spawn(fn ->
        StateStore.update_state(entity_id, entity_state)
        send(parent, {:written, self()})
        Process.sleep(:infinity)
      end)

    assert_receive {:written, ^writer}
    writer
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
