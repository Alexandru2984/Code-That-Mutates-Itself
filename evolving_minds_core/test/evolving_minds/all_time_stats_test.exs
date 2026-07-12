defmodule EvolvingMinds.AllTimeStatsTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.AllTimeStats
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  test "counts births and tracks the highest generation" do
    before = AllTimeStats.get_stats()

    id = "HIST-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id, generation: 42)

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    assert eventually(fn ->
             stats = AllTimeStats.get_stats()
             stats.births >= before.births + 1 and stats.max_generation >= 42
           end)
  end

  test "records deaths by cause and the oldest mind" do
    before = AllTimeStats.get_stats()

    id = "REAP-#{System.unique_integer([:positive])}"
    {:ok, _pid} = World.spawn_entity(id, traits: %{aggression: 0.1, curiosity: 0.1})

    World.adjust_energy(id, -200)
    assert eventually(fn -> StateStore.get_state(id) == nil end)

    assert eventually(fn ->
             stats = AllTimeStats.get_stats()

             stats.deaths >= before.deaths + 1 and
               Map.get(stats.deaths_by_cause, :killed, 0) >=
                 Map.get(before.deaths_by_cause, :killed, 0) + 1 and
               stats.oldest != nil
           end)
  end

  test "import restores exported counters" do
    exported = AllTimeStats.export()
    modified = %{exported | mutations: exported.mutations + 1000}

    assert :ok = AllTimeStats.import(modified)
    assert AllTimeStats.get_stats().mutations == exported.mutations + 1000

    # Restore reality so other tests keep monotonic expectations.
    assert :ok = AllTimeStats.import(exported)
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
