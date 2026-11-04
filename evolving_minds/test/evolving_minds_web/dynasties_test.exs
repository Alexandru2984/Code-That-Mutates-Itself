defmodule EvolvingMindsWeb.DynastiesTest do
  use ExUnit.Case, async: true
  alias EvolvingMindsWeb.Dynasties

  defp record(id, parent, generation, alive),
    do: %{
      id: id,
      parent_id: parent,
      name: id,
      tribe: :solari,
      generation: generation,
      alive: alive
    }

  test "family counts include dead ancestors and rank by living members" do
    records = [
      record("a", nil, 1, false),
      record("b", "a", 2, true),
      record("c", "b", 3, true),
      record("d", nil, 1, true)
    ]

    [family, other] = Dynasties.summarize(Enum.reverse(records))
    assert family.id == "a"
    assert family.total == 3
    assert family.alive == 2
    assert family.max_generation == 3
    assert family.member_ids == MapSet.new(["a", "b", "c"])
    refute family.incomplete
    assert other.id == "d"
  end

  test "pruned ancestors mark a retained family incomplete without losing descendants" do
    [family] =
      Dynasties.summarize([
        record("child", "pruned", 12, false),
        record("heir", "child", 13, true)
      ])

    assert family.id == "child"
    assert family.incomplete
    assert family.total == 2
    refute family.cyclic
  end

  test "legacy ancestry loops have one representative independent of traversal order" do
    records = [
      record("a-descendant", "z", 4, true),
      record("z", "y", 3, false),
      record("y", "z", 2, false)
    ]

    [family] = Dynasties.summarize(records)
    assert family.id == "y"
    assert family.cyclic
    assert family.total == 3
    assert Dynasties.summarize(Enum.reverse(records)) == [family]
  end

  test "the full retention limit resolves a long family without truncating its ancestry" do
    records =
      for i <- 1..2000, do: record("mind-#{i}", if(i > 1, do: "mind-#{i - 1}"), i, i == 2000)

    assert [%{id: "mind-1", total: 2000, max_generation: 2000, alive: 1}] =
             Dynasties.summarize(Enum.reverse(records))

    assert Dynasties.summarize([]) == []
  end
end
