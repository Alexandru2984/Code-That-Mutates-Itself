defmodule EvolvingMinds.AncestryTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.Ancestry
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  defp spawn_entity(prefix, opts \\ []) do
    id = "#{prefix}-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id, opts)

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    {id, pid}
  end

  test "every spawn is recorded in the book" do
    {id, _pid} = spawn_entity("BOOK", name: "Velna", generation: 4)

    assert eventually(fn -> Ancestry.get(id) != nil end)

    record = Ancestry.get(id)
    assert record.name == "Velna"
    assert record.generation == 4
    assert record.died_at == nil
  end

  test "lineage walks the parent chain and children are listed" do
    {parent_id, _} = spawn_entity("LINP", name: "Velna")
    {child_id, _} = spawn_entity("LINC", name: "Norix", parent_id: parent_id, generation: 2)

    assert eventually(fn -> Ancestry.get(child_id) != nil end)

    assert [%{name: "Norix"}, %{name: "Velna"}] = Ancestry.lineage(child_id)
    assert eventually(fn -> Enum.any?(Ancestry.children(parent_id), &(&1.id == child_id)) end)
  end

  test "death closes the record with cause and killer" do
    {id, _pid} = spawn_entity("FATE", traits: %{aggression: 0.1, curiosity: 0.1})
    assert eventually(fn -> Ancestry.get(id) != nil end)

    World.adjust_energy(id, -200, "REAPER-1")
    assert eventually(fn -> StateStore.get_state(id) == nil end)

    assert eventually(fn ->
             match?(
               %{died_at: died, cause: :killed, killer_id: "REAPER-1"} when died != nil,
               Ancestry.get(id)
             )
           end)
  end

  test "export/import round-trips records" do
    {id, _pid} = spawn_entity("PORT", name: "Portis")
    assert eventually(fn -> Ancestry.get(id) != nil end)

    exported = Ancestry.export()
    assert Enum.any?(exported, &(&1.id == id))
    assert :ok = Ancestry.import(exported)
    assert Ancestry.get(id).name == "Portis"
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
