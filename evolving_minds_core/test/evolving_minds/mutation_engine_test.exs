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

    test "fixed responses are trait-independent" do
      behavior = MutationEngine.compile_behavior(%{aggression: 0.5, curiosity: 0.5})

      assert behavior.({:attack, "x"}) == {:flee, "x"}
      assert behavior.({:share_knowledge, "x"}) == {:greet, "x"}
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
