defmodule EvolvingMindsWeb.WorldLiveTest do
  use EvolvingMindsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World
  alias EvolvingMindsWeb.WorldPublisher

  # Each test gets its own prefix: the UI renders only the first 8 chars of
  # an id, so a shared prefix would make entities from other tests (e.g. in
  # the Global Events feed) satisfy assertions about this test's entity.
  defp spawn_test_entity(prefix) do
    id = "#{prefix}-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id)

    on_exit_kill = fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end

    {id, pid, on_exit_kill}
  end

  test "renders the world dashboard with entities", %{conn: conn} do
    {id, _pid, cleanup} = spawn_test_entity("RNDR")
    on_exit(cleanup)

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Evolving"
    assert html =~ String.slice(id, 0, 8)
  end

  test "world updates re-render entity data", %{conn: conn} do
    {id, _pid, cleanup} = spawn_test_entity("UPDT")
    on_exit(cleanup)

    {:ok, view, _html} = live(conn, "/")

    send(view.pid, {:world_update, WorldPublisher.snapshot()})
    assert render(view) =~ String.slice(id, 0, 8)
  end

  test "filter narrows visible entities", %{conn: conn} do
    {id, _pid, cleanup} = spawn_test_entity("FLTR")
    on_exit(cleanup)

    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("form[phx-change=filter_entities]")
      |> render_change(%{"filters" => %{"query" => "no-such-entity", "sort" => "energy_desc"}})

    refute html =~ String.slice(id, 0, 8)
    assert html =~ "No entities match"

    html =
      view
      |> element("form[phx-change=filter_entities]")
      |> render_change(%{"filters" => %{"query" => id, "sort" => "energy_desc"}})

    assert html =~ String.slice(id, 0, 8)
  end

  test "inject_energy is applied when public controls are enabled", %{conn: conn} do
    {id, pid, cleanup} = spawn_test_entity("NRGY")
    on_exit(cleanup)

    {:ok, view, _html} = live(conn, "/")

    # Entities spawn at 100 energy and injection is capped there, so drain
    # first (5 acts x -5) to make the +20 observable.
    for _ <- 1..5, do: send(pid, :act)
    assert eventually(fn -> energy_of(id) == 75 end)

    # test.exs sets public_controls: true
    render_click(view, "inject_energy", %{"id" => id})

    # inject_energy is a cast; wait for the entity to process it.
    assert eventually(fn -> energy_of(id) == 95 end)
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
