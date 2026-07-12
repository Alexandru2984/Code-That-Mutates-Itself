defmodule EvolvingMinds.InteractionTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.GlobalEvents
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  # Passive minds flee attacks and reciprocate knowledge.
  @dove %{aggression: 0.1, curiosity: 0.9}
  # Aggressive minds fight back.
  @hawk %{aggression: 0.9, curiosity: 0.1}

  defp spawn_at(prefix, traits, energy) do
    id = "#{prefix}-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id, traits: traits)

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    # Drain via direct adjustment: no acts, no side interactions.
    World.adjust_energy(id, energy - 100)
    assert eventually(fn -> energy_of(id) == energy end)
    id
  end

  test "attacking a dove robs it and rewards the attacker" do
    victim = spawn_at("DOVE", @dove, 75)
    attacker = spawn_at("HAWK", @hawk, 75)

    World.send_message(victim, :attack, attacker)

    assert eventually(fn -> energy_of(victim) == 69 end)
    assert eventually(fn -> energy_of(attacker) == 83 end)
  end

  test "attacking a hawk starts a war that bleeds both sides" do
    victim = spawn_at("HWKV", @hawk, 75)
    attacker = spawn_at("HWKA", @hawk, 75)

    World.send_message(victim, :attack, attacker)

    assert eventually(fn -> energy_of(victim) == 65 end)
    assert eventually(fn -> energy_of(attacker) == 65 end)
  end

  test "sharing knowledge with a curious mind compounds for both" do
    receiver = spawn_at("CURI", @dove, 75)
    sender = spawn_at("SNDR", @dove, 75)

    World.send_message(receiver, :share_knowledge, sender)

    assert eventually(fn -> energy_of(receiver) == 81 end)
    assert eventually(fn -> energy_of(sender) == 81 end)
  end

  test "a mind can be killed by an attack" do
    victim = spawn_at("KILL", @dove, 5)

    World.send_message(victim, :attack, "GHOST-ATTACKER")

    assert eventually(fn -> StateStore.get_state(victim) == nil end)

    assert Enum.any?(
             GlobalEvents.get_recent_events(50),
             &(&1.type == :death and &1.entity_id == victim and &1.cause == :killed)
           )
  end

  test "a fatal energy adjustment kills too" do
    victim = spawn_at("DRAN", @dove, 50)

    World.adjust_energy(victim, -200)

    assert eventually(fn -> StateStore.get_state(victim) == nil end)
  end

  defp energy_of(id) do
    case StateStore.get_state(id) do
      nil -> nil
      state -> state.energy
    end
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
