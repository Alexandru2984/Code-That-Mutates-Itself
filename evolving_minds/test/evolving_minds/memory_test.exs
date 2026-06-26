defmodule EvolvingMinds.MemoryTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.Memory

  test "forgets memories for removed entities" do
    entity_id = "memory-test-#{System.unique_integer([:positive])}"

    assert :ok = Memory.remember(entity_id, {:greet, "sender"})
    assert [{:greet, "sender"}] = Memory.get_memories(entity_id)

    assert :ok = Memory.forget(entity_id)
    assert [] = Memory.get_memories(entity_id)
  end
end
