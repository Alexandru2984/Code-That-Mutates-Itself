defmodule EvolvingMindsTest do
  use ExUnit.Case

  test "spawns entities that register in the world" do
    {:ok, pid} = EvolvingMinds.spawn_entity("TEST_FACADE_ENTITY")

    assert "TEST_FACADE_ENTITY" in EvolvingMinds.get_all_entities()

    DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
  end
end
