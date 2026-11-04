defmodule EvolvingMinds.CapacityTest do
  use ExUnit.Case, async: false

  test "concurrent spawns cannot exceed the engine population cap" do
    before_ids = MapSet.new(EvolvingMinds.World.get_all_entities())

    on_exit(fn ->
      for id <- EvolvingMinds.World.get_all_entities(), not MapSet.member?(before_ids, id) do
        for {pid, _} <- Registry.lookup(EvolvingMinds.EntityRegistry, id),
            do: DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    results =
      1..60
      |> Task.async_stream(fn _ -> EvolvingMinds.World.spawn_entity() end, max_concurrency: 20)
      |> Enum.to_list()

    assert Enum.any?(results, &match?({:ok, {:error, :max_children}}, &1))

    assert length(EvolvingMinds.World.get_all_entities()) ==
             EvolvingMinds.EvolutionEngine.max_population()
  end
end
