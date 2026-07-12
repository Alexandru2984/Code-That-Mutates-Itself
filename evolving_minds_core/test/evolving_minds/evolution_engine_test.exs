defmodule EvolvingMinds.EvolutionEngineTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.EvolutionEngine
  alias EvolvingMinds.World

  # The engine is disabled in test config; this test starts one on purpose
  # and cleans up every entity it seeded.
  test "seeds an initial population on startup" do
    before_ids = MapSet.new(World.get_all_entities())

    pid = start_supervised!(EvolutionEngine)

    assert eventually(fn ->
             length(World.get_all_entities()) >= MapSet.size(before_ids) + 5
           end)

    stop_supervised!(EvolutionEngine)
    refute Process.alive?(pid)

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
