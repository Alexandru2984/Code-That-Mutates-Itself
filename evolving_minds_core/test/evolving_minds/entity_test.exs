defmodule EvolvingMinds.EntityTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.GlobalEvents
  alias EvolvingMinds.Memory
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  defp spawn_entity(prefix) do
    id = "#{prefix}-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id)

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    {id, pid}
  end

  test "spawns registered with full energy and traits in range" do
    {id, _pid} = spawn_entity("SPWN")

    assert id in World.get_all_entities()

    state = StateStore.get_state(id)
    assert state.energy == 100
    assert state.traits.aggression >= 0.0 and state.traits.aggression <= 1.0
    assert state.traits.curiosity >= 0.0 and state.traits.curiosity <= 1.0
    assert is_binary(state.behavior_source)
    assert is_function(state.behavior_fn, 1)
  end

  test "records received messages in memory" do
    {id, _pid} = spawn_entity("MEMO")

    World.send_message(id, :greet, "TESTER")

    assert eventually(fn -> {:greet, "TESTER"} in Memory.get_memories(id) end)
  end

  test "dies of exhaustion after enough actions and is fully purged" do
    {id, pid} = spawn_entity("DETH")
    ref = Process.monitor(pid)

    # 20 acts x -5 energy: the 20th act brings energy to 0 and stops the
    # entity. No other entities exist, so acts send no messages.
    for _ <- 1..20, do: send(pid, :act)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000

    assert eventually(fn -> StateStore.get_state(id) == nil end)
    assert eventually(fn -> Memory.get_memories(id) == [] end)
    # Registry entries are removed asynchronously after process death.
    assert eventually(fn -> id not in World.get_all_entities() end)

    assert Enum.any?(
             GlobalEvents.get_recent_events(50),
             &(&1.type == :death and &1.entity_id == id and &1.cause == :exhaustion)
           )
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
