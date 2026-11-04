defmodule EvolvingMindsWeb.SecurityTest do
  use EvolvingMindsWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EvolvingMindsWeb.{AdminAuth, ClientIdentity, RateLimiter}

  test "administrative mounts reject a public or forged session" do
    socket = %Phoenix.LiveView.Socket{endpoint: EvolvingMindsWeb.Endpoint}
    assert {:halt, denied} = AdminAuth.on_mount(:require_admin, %{}, %{}, socket)
    assert denied.redirected == {:redirect, %{to: "/", status: 302}}

    assert {:halt, _} =
             AdminAuth.on_mount(:require_admin, %{}, %{"admin_access" => "forged"}, socket)
  end

  test "public, admin and dashboard have distinct LiveView sessions" do
    sessions =
      EvolvingMindsWeb.Router.__routes__()
      |> Enum.filter(&(&1.path in ["/", "/admin/world", "/admin/dashboard/:page"]))
      |> Enum.map(&elem(&1.metadata.phoenix_live_view, 3).name)

    assert Enum.uniq(sessions) |> length() == 3
  end

  test "credential rotation revokes an already connected admin", %{conn: conn} do
    original = Application.fetch_env!(:evolving_minds, :admin_credentials)
    on_exit(fn -> Application.put_env(:evolving_minds, :admin_credentials, original) end)
    conn = put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:secret"))
    {:ok, view, _} = live(conn, "/admin/world")

    Application.put_env(:evolving_minds, :admin_credentials,
      username: "admin",
      password: "rotated"
    )

    render_click(view, "save_snapshot", %{})
    assert_redirect(view, "/")
  end

  test "malformed administrative commands are rejected without crashing", %{conn: conn} do
    conn = put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:secret"))
    {:ok, view, _} = live(conn, "/admin/world")

    for count <- ["0", "-1", "1000000000", "abc", [], 5] do
      assert render_click(view, "spawn", %{"count" => count}) =~ "Invalid command"
    end

    assert render_click(view, "set_epoch", %{"epoch" => "unknown-atom"}) =~ "Invalid epoch"
    assert Process.alive?(view.pid)
  end

  test "rate windows are atomic under concurrency and expire" do
    key = {:test, make_ref()}

    results =
      1..20 |> Task.async_stream(fn _ -> RateLimiter.allow?(key, 3, 50) end) |> Enum.to_list()

    assert Enum.count(results, &(&1 == {:ok, true})) == 3
    Process.sleep(60)
    assert RateLimiter.allow?(key, 3, 50)
  end

  test "untrusted peers cannot spoof budget identity with proxy headers", %{conn: conn} do
    original = ClientIdentity.key(conn)
    assert conn |> put_req_header("x-real-ip", "1.2.3.4") |> ClientIdentity.key() == original
  end

  test "public action budgets survive opening another LiveView", %{conn: conn} do
    before = MapSet.new(EvolvingMinds.World.get_all_entities())

    on_exit(fn ->
      for id <- EvolvingMinds.World.get_all_entities(), not MapSet.member?(before, id) do
        for {pid, _} <- Registry.lookup(EvolvingMinds.EntityRegistry, id),
            do: DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    {:ok, first, _} = live(conn, "/")
    assert render_click(first, "spawn_mind", %{}) =~ "A new mind awakens"
    assert render_click(first, "spawn_mind", %{}) =~ "A new mind awakens"
    {:ok, second, _} = live(conn, "/")
    assert render_click(second, "spawn_mind", %{}) =~ "needs a moment"
  end
end
