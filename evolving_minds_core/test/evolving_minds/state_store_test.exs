defmodule EvolvingMinds.StateStoreTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.Memory
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  test "purges state and memories when an entity crashes" do
    entity_id = "crash-test-#{System.unique_integer([:positive])}"

    {:ok, pid} = World.spawn_entity(entity_id)
    Memory.remember(entity_id, {:greet, "someone"})

    assert StateStore.get_state(entity_id) != nil
    assert Memory.get_memories(entity_id) != []

    # Simulate an abnormal crash: no death path runs inside the entity.
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    # The purge is asynchronous; wait for the monitor in StateStore to fire.
    assert eventually(fn -> StateStore.get_state(entity_id) == nil end)
    assert eventually(fn -> Memory.get_memories(entity_id) == [] end)
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
