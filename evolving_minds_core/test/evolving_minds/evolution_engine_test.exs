defmodule EvolvingMinds.EvolutionEngineTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.EvolutionEngine
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  # The engine is disabled in test config; this test starts one on purpose
  # and cleans up every entity it seeded.
  test "seeds an initial population when the world is empty" do
    # Seeding only happens in an empty world, and registry entries of
    # entities terminated by earlier tests disappear asynchronously —
    # so empty the world explicitly and wait for it.
    cleanup_new_entities(MapSet.new())
    assert eventually(fn -> World.get_all_entities() == [] end)

    pid = start_supervised!(EvolutionEngine)

    assert eventually(fn -> length(World.get_all_entities()) >= 5 end)

    stop_supervised!(EvolutionEngine)
    refute Process.alive?(pid)

    cleanup_new_entities(MapSet.new())
  end

  test "reproduction spawns a child inheriting the parent's lineage" do
    before_ids = MapSet.new(World.get_all_entities())
    parent_id = "PRNT-#{System.unique_integer([:positive])}"

    parent_traits = %{aggression: 0.9, curiosity: 0.1}

    {:ok, parent_pid} =
      World.spawn_entity(parent_id, traits: parent_traits, generation: 7)

    on_exit(fn ->
      if Process.alive?(parent_pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, parent_pid)
      end
    end)

    parent_state = StateStore.get_state(parent_id)
    assert {:ok, child_id, ^parent_id} = EvolutionEngine.reproduce([parent_state])

    child = StateStore.get_state(child_id)
    assert child.generation == 8
    assert child.parent_id == parent_id
    # Children resemble their parent: birth jitter is bounded by ±0.15.
    assert abs(child.traits.aggression - parent_traits.aggression) <= 0.15
    assert abs(child.traits.curiosity - parent_traits.curiosity) <= 0.15

    cleanup_new_entities(MapSet.put(before_ids, parent_id))
  end

  defp cleanup_new_entities(before_ids) do
    for id <- World.get_all_entities(), not MapSet.member?(before_ids, id) do
      case Registry.lookup(EvolvingMinds.EntityRegistry, id) do
        [{entity_pid, _}] ->
          DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, entity_pid)

        [] ->
          :ok
      end
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
