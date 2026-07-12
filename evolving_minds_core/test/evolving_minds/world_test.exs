defmodule EvolvingMinds.WorldTest do
  use ExUnit.Case, async: false

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

  test "send_message to an unknown entity is a no-op" do
    assert :ok = World.send_message("does-not-exist", :greet, "TESTER")
  end

  test "get_random_entity excludes the requesting entity" do
    {id, _pid} = spawn_entity("RAND")

    case World.get_random_entity(id) do
      # Other tests may have live entities; the only guarantee is exclusion.
      nil -> assert true
      other -> assert other != id
    end
  end

  test "spawning a duplicate id fails" do
    {id, pid} = spawn_entity("DUPL")

    assert {:error, {:already_started, ^pid}} = World.spawn_entity(id)
  end
end
