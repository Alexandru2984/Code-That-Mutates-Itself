defmodule EvolvingMinds.TribeTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.EvolutionEngine
  alias EvolvingMinds.Memory
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  @hawk %{aggression: 1.0, curiosity: 0.1}

  defp spawn_entity(prefix, opts) do
    id = "#{prefix}-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id, opts)

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    {id, pid}
  end

  test "even a full hawk never attacks its own tribe" do
    {attacker_id, attacker_pid} = spawn_entity("LOYA", traits: @hawk, tribe: :solari)
    {target_id, _} = spawn_entity("LOYB", tribe: :solari)

    for _ <- 1..5, do: send(attacker_pid, :act)

    assert eventually(fn -> Memory.get_memories(target_id) != [] end)

    assert Enum.all?(
             Memory.get_memories(target_id),
             &match?({:greet, ^attacker_id}, &1)
           )
  end

  test "a full hawk always attacks the other tribe" do
    {attacker_id, attacker_pid} = spawn_entity("WARA", traits: @hawk, tribe: :solari)
    {target_id, _} = spawn_entity("WARB", tribe: :umbra)

    for _ <- 1..5, do: send(attacker_pid, :act)

    assert eventually(fn -> Memory.get_memories(target_id) != [] end)

    assert Enum.all?(
             Memory.get_memories(target_id),
             &match?({:attack, ^attacker_id}, &1)
           )
  end

  test "children inherit their parent's tribe" do
    {parent_id, _} = spawn_entity("TRIB", tribe: :umbra)

    parent_state = StateStore.get_state(parent_id)
    assert {:ok, child_id, ^parent_id} = EvolutionEngine.reproduce([parent_state])

    assert StateStore.get_state(child_id).tribe == :umbra

    # The child must not outlive the test: on slow machines a leaked
    # entity starts acting and corrupts later tests' energy math.
    case Registry.lookup(EvolvingMinds.EntityRegistry, child_id) do
      [{child_pid, _}] ->
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, child_pid)

      [] ->
        :ok
    end
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
