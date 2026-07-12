defmodule EvolvingMinds.EnvironmentTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.Environment
  alias EvolvingMinds.GlobalEvents
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  setup do
    on_exit(fn -> Environment.set_epoch(:normal) end)
    :ok
  end

  test "epochs change the cost of acting" do
    assert Environment.current_epoch() == :normal
    assert Environment.act_cost() == 5

    Environment.set_epoch(:famine)
    assert Environment.act_cost() == 8

    Environment.set_epoch(:abundance)
    assert Environment.act_cost() == 3
  end

  test "epoch changes are reported to the event feed" do
    Environment.set_epoch(:famine)

    assert Enum.any?(
             GlobalEvents.get_recent_events(50),
             &(&1.type == :epoch_change and &1.detail =~ "famine")
           )
  end

  test "acting during a famine drains more energy" do
    Environment.set_epoch(:famine)

    id = "FMNE-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id, traits: %{aggression: 0.1, curiosity: 0.1})

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    send(pid, :act)

    assert eventually(fn -> StateStore.get_state(id).energy == 92 end)
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
