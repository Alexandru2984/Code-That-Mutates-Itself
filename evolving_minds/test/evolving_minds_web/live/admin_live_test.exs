defmodule EvolvingMindsWeb.AdminLiveTest do
  use EvolvingMindsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  defp authed(conn) do
    put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:secret"))
  end

  test "admin area requires credentials", %{conn: conn} do
    conn = get(conn, "/admin/world")
    assert conn.status == 401
  end

  test "wrong credentials are rejected", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Basic " <> Base.encode64("admin:wrong"))
      |> get("/admin/world")

    assert conn.status == 401
  end

  test "renders god mode with valid credentials", %{conn: conn} do
    {:ok, _view, html} = conn |> authed() |> live("/admin/world")

    assert html =~ "God mode enabled"
    assert html =~ "Population"
  end

  test "live dashboard is mounted behind auth", %{conn: conn} do
    conn = conn |> authed() |> get("/admin/dashboard")
    assert redirected_to(conn) =~ "/admin/dashboard/"
  end

  test "pause and resume control the world", %{conn: conn} do
    on_exit(fn -> World.resume() end)

    {:ok, view, _html} = conn |> authed() |> live("/admin/world")

    html = render_click(view, "pause", %{})
    assert html =~ "World paused."
    assert World.paused?()

    html = render_click(view, "resume", %{})
    assert html =~ "World resumed."
    refute World.paused?()
  end

  test "terminates a mind by id", %{conn: conn} do
    id = "ADMK-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id)

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    {:ok, view, _html} = conn |> authed() |> live("/admin/world")

    html =
      view
      |> element("#kill-form")
      |> render_submit(%{"kill" => %{"id" => id}})

    assert html =~ "terminated"
    assert eventually(fn -> StateStore.get_state(id) == nil end)

    # Unknown ids get a clear error.
    html =
      view
      |> element("#kill-form")
      |> render_submit(%{"kill" => %{"id" => "no-such-mind"}})

    assert html =~ "No living mind"
  end

  test "sets the epoch", %{conn: conn} do
    on_exit(fn -> EvolvingMinds.Environment.set_epoch(:normal) end)

    {:ok, view, _html} = conn |> authed() |> live("/admin/world")

    html = render_click(view, "set_epoch", %{"epoch" => "famine"})
    assert html =~ "Epoch set to famine."
    assert EvolvingMinds.Environment.current_epoch() == :famine
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
