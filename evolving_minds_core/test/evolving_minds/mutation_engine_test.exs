defmodule EvolvingMinds.MutationEngineTest do
  use ExUnit.Case, async: true

  alias EvolvingMinds.MutationEngine

  describe "compile_behavior/1" do
    test "aggressive, curious traits answer greetings with attack or knowledge" do
      behavior = MutationEngine.compile_behavior(%{aggression: 0.9, curiosity: 0.9})

      for _ <- 1..50 do
        assert behavior.({:greet, "x"}) in [{:attack, "x"}, {:share_knowledge, "x"}]
      end
    end

    test "passive, incurious traits answer greetings with greet or ignore" do
      behavior = MutationEngine.compile_behavior(%{aggression: 0.1, curiosity: 0.1})

      for _ <- 1..50 do
        assert behavior.({:greet, "x"}) in [{:greet, "x"}, {:ignore, "x"}]
      end
    end

    test "aggressive minds fight back, passive minds flee" do
      hawk = MutationEngine.compile_behavior(%{aggression: 0.9, curiosity: 0.5})
      dove = MutationEngine.compile_behavior(%{aggression: 0.1, curiosity: 0.5})

      assert hawk.({:attack, "x"}) == {:attack, "x"}
      assert dove.({:attack, "x"}) == {:flee, "x"}
    end

    test "curious minds reciprocate knowledge, incurious ones just greet" do
      curious = MutationEngine.compile_behavior(%{aggression: 0.5, curiosity: 0.9})
      incurious = MutationEngine.compile_behavior(%{aggression: 0.5, curiosity: 0.1})

      assert curious.({:share_knowledge, "x"}) == {:share_knowledge, "x"}
      assert incurious.({:share_knowledge, "x"}) == {:greet, "x"}
    end

    test "unknown interactions are ignored" do
      behavior = MutationEngine.compile_behavior(%{aggression: 0.5, curiosity: 0.5})

      assert behavior.(:garbage) == {:ignore, nil}
    end
  end

  describe "generate_behavior/1" do
    test "source mirrors the responses the compiled behavior gives" do
      source = MutationEngine.generate_behavior(%{aggression: 0.9, curiosity: 0.9})

      assert source =~ ":attack"
      assert source =~ ":share_knowledge"

      source = MutationEngine.generate_behavior(%{aggression: 0.1, curiosity: 0.1})

      assert source =~ ":greet"
      assert source =~ ":ignore"
    end
  end

  describe "inherit/1" do
    test "children stay within jitter range and valid bounds" do
      parent = %{aggression: 0.95, curiosity: 0.05}

      for _ <- 1..200 do
        child = MutationEngine.inherit(parent)

        assert child.aggression >= 0.0 and child.aggression <= 1.0
        assert child.curiosity >= 0.0 and child.curiosity <= 1.0
        assert abs(child.aggression - parent.aggression) <= 0.15
        assert abs(child.curiosity - parent.curiosity) <= 0.15
      end
    end
  end

  describe "mutate/3" do
    test "keeps traits within [0.0, 1.0] across many generations" do
      initial = %{aggression: 1.0, curiosity: 0.0}
      source = MutationEngine.generate_behavior(initial)
      behavior = MutationEngine.compile_behavior(initial)

      Enum.reduce(1..200, {initial, source, behavior}, fn _, {traits, src, fun} ->
        {new_traits, new_src, new_fun} = MutationEngine.mutate(traits, src, fun)

        assert new_traits.aggression >= 0.0 and new_traits.aggression <= 1.0
        assert new_traits.curiosity >= 0.0 and new_traits.curiosity <= 1.0

        {new_traits, new_src, new_fun}
      end)
    end
  end
end
