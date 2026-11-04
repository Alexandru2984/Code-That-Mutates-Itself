defmodule EvolvingMindsWeb.ObservatoryLiveTest do
  use EvolvingMindsWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias EvolvingMinds.{StateStore, World}
  alias EvolvingMindsWeb.WorldPublisher

  setup do
    World.pause()
    on_exit(fn -> World.resume() end)
    :ok
  end

  defp mind(name, opts \\ []) do
    {:ok, pid} = World.spawn_entity([name: name] ++ opts)
    id = World.id_of(pid)

    on_exit(fn ->
      if Process.alive?(pid),
        do: DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
    end)

    id
  end

  test "name, tribe and condition filters combine and reset", %{conn: conn} do
    id = mind("UniqueSolar", tribe: :solari)
    other = mind("UniqueShadow", tribe: :umbra)
    {:ok, view, _} = live(conn, "/")

    view
    |> form("#filter-form",
      filters: %{query: "uniquesolar", tribe: "solari", status: "thriving", sort: "oldest"}
    )
    |> render_change()

    assert has_element?(view, "#entity-#{id}")
    refute has_element?(view, "#entity-#{other}")
    render_click(view, "clear_filters", %{})
    assert has_element?(view, "#entity-#{other}")
  end

  test "watchlist filters persist across world updates and reject invalid IDs", %{conn: conn} do
    id = mind("WatchedMind")
    other = mind("OtherMind")
    {:ok, view, _} = live(conn, "/")

    render_click(view, "restore_watchlist", %{
      "ids" => [id, id, 123, %{}, String.duplicate("x", 200)]
    })

    render_click(view, "only_watched", %{})
    assert has_element?(view, "#entity-#{id}")
    refute has_element?(view, "#entity-#{other}")
    send(view.pid, {:world_update, WorldPublisher.snapshot()})
    assert has_element?(view, "#entity-#{id} .star-button[aria-pressed=true]")
    render_click(view, "clear_watchlist", %{})
    assert has_element?(view, "#entity-#{other}")
  end

  test "comparison has a three-mind cap and can be cleared", %{conn: conn} do
    ids = for i <- 1..4, do: mind("Compare#{i}")
    {:ok, view, _} = live(conn, "/")
    for id <- Enum.take(ids, 3), do: render_click(view, "toggle_compare", %{"id" => id})

    assert length(
             view
             |> element("#comparison")
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find(".comparison-item")
           ) == 3

    assert render_click(view, "toggle_compare", %{"id" => List.last(ids)}) =~
             "Compare up to three"

    render_click(view, "clear_comparison", %{})
    refute has_element?(view, "#comparison")
  end

  test "pausing observation freezes cards while retaining the latest update", %{conn: conn} do
    id = mind("PausedMind")
    {:ok, view, _} = live(conn, "/")
    render_click(view, "toggle_observation", %{})
    snapshot = WorldPublisher.snapshot()

    snapshot = %{
      snapshot
      | entities:
          Enum.map(snapshot.entities, fn e -> if e.id == id, do: %{e | energy: 12}, else: e end)
    }

    send(view.pid, {:world_update, snapshot})
    assert view |> element("#entity-#{id} .energy-label strong") |> render() =~ "100%"
    render_click(view, "toggle_observation", %{})
    assert view |> element("#entity-#{id} .energy-label strong") |> render() =~ "12%"
    assert StateStore.get_state(id).energy == 100
  end

  test "deep links open a dossier and map and leader views are interactive", %{conn: conn} do
    id = mind("LinkedMind")
    {:ok, view, html} = live(conn, "/?mind=#{id}")
    assert html =~ "Mind Dossier"
    render_click(view, "close_entity", %{})
    render_click(view, "set_view", %{"view" => "map"})
    assert has_element?(view, ".map-mind[phx-value-id='#{id}']")
    render_click(view, "set_view", %{"view" => "leaders"})
    assert has_element?(view, ".ranking")
  end

  test "world export is public data and contains no behavior functions or private tallies", %{
    conn: conn
  } do
    response = conn |> get("/api/world") |> json_response(200)
    assert response["version"] == 1
    refute Map.has_key?(response["records"], "kills_by")
    refute Map.has_key?(response["records"], "children_by")
    assert Enum.all?(response["entities"], &(not Map.has_key?(&1, "behavior_fn")))
  end

  test "network links open dossiers and respect the visible population", %{conn: conn} do
    first = mind("NetworkAlpha")
    second = mind("NetworkBeta")
    {:ok, view, _} = live(conn, "/")
    snapshot = %{WorldPublisher.snapshot() | top_interactions: [{[first, second], 6}]}
    send(view.pid, {:world_update, snapshot})
    render_click(view, "set_view", %{"view" => "network"})
    assert has_element?(view, "#social-network .network-node", "NetworkAlpha")
    assert has_element?(view, "#social-network .connection-list", "6 memories")
    view |> form("#filter-form", filters: %{query: "NetworkAlpha"}) |> render_change()
    refute has_element?(view, "#social-network .network-node")
    assert render(view) =~ "No connections in this selection"
  end
end
