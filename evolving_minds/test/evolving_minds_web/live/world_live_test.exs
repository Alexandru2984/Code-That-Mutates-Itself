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

  test "GET / renders the dashboard shell (disconnected render)", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Evolving"
    assert response =~ "Autonomous Heuristic Simulator"
    assert response =~ "Filter entity ID"
    assert response =~ "Energy high"
    assert response =~ "Visible"
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

  test "dead entities drop out of the grid on world updates", %{conn: conn} do
    {id, pid, cleanup} = spawn_test_entity("GONE")
    on_exit(cleanup)

    {:ok, view, html} = live(conn, "/")
    assert html =~ String.slice(id, 0, 8)

    DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
    assert eventually(fn -> StateStore.get_state(id) == nil end)

    send(view.pid, {:world_update, WorldPublisher.snapshot()})
    refute render(view) =~ String.slice(id, 0, 8)
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
    # first to make the +20 observable. Draining goes through adjust_energy:
    # acts now send messages with energy consequences to other entities.
    World.adjust_energy(id, -25)
    assert eventually(fn -> energy_of(id) == 75 end)

    # test.exs sets public_controls: true
    render_click(view, "inject_energy", %{"id" => id})

    # inject_energy is a cast; wait for the entity to process it.
    assert eventually(fn -> energy_of(id) == 95 end)
  end

  test "detail panel opens, tracks, and closes", %{conn: conn} do
    {id, _pid, cleanup} = spawn_test_entity("DTLS")
    on_exit(cleanup)

    {:ok, view, _html} = live(conn, "/")

    html = render_click(view, "select_entity", %{"id" => id})
    assert html =~ "Mind Dossier"
    assert html =~ "primordial spawn"
    assert html =~ "Active Heuristic"

    html = render_click(view, "close_entity", %{})
    refute html =~ "Mind Dossier"
  end

  test "detail panel reports a death while open", %{conn: conn} do
    {id, pid, cleanup} = spawn_test_entity("DEAD")
    on_exit(cleanup)

    {:ok, view, _html} = live(conn, "/")
    assert render_click(view, "select_entity", %{"id" => id}) =~ "Mind Dossier"

    DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
    assert eventually(fn -> StateStore.get_state(id) == nil end)

    send(view.pid, {:world_update, WorldPublisher.snapshot()})
    assert render(view) =~ "This mind has died"
  end

  test "about modal explains the world and toggles", %{conn: conn} do
    # Phrases unique to the modal body — the meta tags in <head> also
    # mention the simulation, so assertions must not collide with them.
    {:ok, view, html} = live(conn, "/")
    refute html =~ "fleeing pacifist pays"

    html = render_click(view, "toggle_about", %{})
    assert html =~ "fleeing pacifist pays"
    assert html =~ "frequency-dependent"

    refute render_click(view, "toggle_about", %{}) =~ "fleeing pacifist pays"
  end

  test "sidebar shows charts and hall of fame", %{conn: conn} do
    {_id, _pid, cleanup} = spawn_test_entity("CHRT")
    on_exit(cleanup)

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Trait Distribution"
    assert html =~ "Hall of Fame"
    assert html =~ "Population"
  end

  test "inject_energy is rate limited per client", %{conn: conn} do
    entities =
      for i <- 1..6 do
        {id, pid, cleanup} = spawn_test_entity("RL#{i}")
        on_exit(cleanup)
        {id, pid}
      end

    {:ok, view, _html} = live(conn, "/")

    # Drain everyone to 75 so injections are observable below the cap.
    # Draining goes through adjust_energy: acts now send messages with
    # energy consequences to other entities.
    for {id, _pid} <- entities, do: World.adjust_energy(id, -25)
    assert eventually(fn -> Enum.all?(entities, fn {id, _} -> energy_of(id) == 75 end) end)

    results =
      for {id, _pid} <- entities do
        render_click(view, "inject_energy", %{"id" => id})
      end

    # The first five injections land (+20; acts can only lower energy, so
    # anything above 75 proves the injection happened)...
    {first_five, [{last_id, _}]} = Enum.split(entities, 5)

    for {id, _} <- first_five do
      assert eventually(fn -> energy_of(id) > 75 end)
    end

    # ...while the sixth is rejected and the client is told why.
    Process.sleep(100)
    assert energy_of(last_id) <= 75
    assert List.last(results) =~ "Rate limit reached"
  end

  test "the event feed tells the story with names", %{conn: conn} do
    EvolvingMinds.GlobalEvents.report_event(%{
      type: :death,
      entity_id: "STORY-VICTIM",
      name: "Testor",
      cause: :killed,
      killer_id: "STORY-KILLER",
      killer_name: "Slayer"
    })

    EvolvingMinds.GlobalEvents.report_event(%{
      type: :reproduction,
      entity_id: "STORY-CHILD",
      name: "Novix",
      parent_id: "STORY-PARENT",
      parent_name: "Velna",
      generation: 12
    })

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Testor was slain by Slayer"
    assert html =~ "Velna begat Novix (gen 12)"
  end

  test "cards show the mind's name", %{conn: conn} do
    id = "CNAM-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id, name: "Korvax")

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Korvax"
    assert html =~ String.slice(id, 0, 8)
  end

  test "visitors can spawn minds, rate limited with a population cap", %{conn: conn} do
    before_ids = MapSet.new(World.get_all_entities())

    on_exit(fn ->
      for id <- World.get_all_entities(), not MapSet.member?(before_ids, id) do
        case Registry.lookup(EvolvingMinds.EntityRegistry, id) do
          [{pid, _}] -> DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
          [] -> :ok
        end
      end
    end)

    {:ok, view, _html} = live(conn, "/")

    html = render_click(view, "spawn_mind", %{})
    assert html =~ "A new mind awakens"

    html = render_click(view, "spawn_mind", %{})
    assert html =~ "A new mind awakens"

    assert eventually(fn ->
             length(World.get_all_entities()) >= MapSet.size(before_ids) + 2
           end)

    # Third spawn inside the window hits the limit.
    html = render_click(view, "spawn_mind", %{})
    assert html =~ "needs a moment"
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
