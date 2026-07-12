defmodule EvolvingMinds.TelemetryTest do
  use ExUnit.Case, async: false

  alias EvolvingMinds.World

  @events [
    [:evolving_minds, :entity, :spawn],
    [:evolving_minds, :entity, :death],
    [:evolving_minds, :entity, :mutation]
  ]

  setup do
    test_pid = self()
    handler_id = "telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      @events,
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "entity lifecycle emits spawn, mutation, and death events" do
    id = "TLMT-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id)

    assert_receive {:telemetry, [:evolving_minds, :entity, :spawn], %{count: 1}, %{id: ^id}}

    # Mutation fires with 20% probability per act; keep energy topped up and
    # act until it lands (P(miss 200 times) ~ 4e-20).
    for _ <- 1..200 do
      send(pid, :act)
      GenServer.cast(pid, :inject_energy)
    end

    assert_receive {:telemetry, [:evolving_minds, :entity, :mutation], %{count: 1}, %{id: ^id}},
                   3_000

    # Now drain to death: stop refilling and keep acting.
    ref = Process.monitor(pid)
    for _ <- 1..30, do: send(pid, :act)

    assert_receive {:telemetry, [:evolving_minds, :entity, :death], %{count: 1}, %{id: ^id}},
                   3_000

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3_000
  end
end
