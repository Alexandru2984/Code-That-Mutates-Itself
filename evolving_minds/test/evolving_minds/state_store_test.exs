defmodule EvolvingMinds.StateStoreTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.StateStore

  test "stores and removes entity state through the owner process" do
    entity_id = "state-test-#{System.unique_integer([:positive])}"
    state = %{id: entity_id, energy: 42}

    assert :ok = StateStore.update_state(entity_id, state)
    assert StateStore.get_state(entity_id) == state

    assert :ok = StateStore.remove_state(entity_id)
    assert StateStore.get_state(entity_id) == nil
  end
end
