defmodule EvolvingMindsWeb.ObservatoryTest do
  use ExUnit.Case, async: true
  alias EvolvingMindsWeb.Observatory

  test "histogram includes both endpoints without losing or inventing minds" do
    entities = for aggression <- [0.0, 0.1, 0.99, 1.0], do: %{traits: %{aggression: aggression}}
    bins = Observatory.histogram(entities, :aggression)
    assert length(bins) == 10
    assert Enum.sum(Enum.map(bins, & &1.count)) == 4
    assert hd(bins).count == 1
    assert List.last(bins).count == 2
    assert List.last(bins).height == 100
    assert Enum.all?(Observatory.histogram([], :aggression), &(&1.count == 0))
  end

  test "generation chart bounds and scales the generations actually shown" do
    entities = List.duplicate(%{generation: 1}, 20) ++ Enum.map(2..14, &%{generation: &1})
    bins = Observatory.generations(entities)
    assert length(bins) == 12
    assert hd(bins).generation == 3
    assert Enum.all?(bins, &(&1.height == 100))
  end
end
