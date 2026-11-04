defmodule EvolvingMindsWeb.OfflineControllerTest do
  use EvolvingMindsWeb.ConnCase, async: true
  alias EvolvingMindsWeb.OfflineAssets

  test "offline document is identical across visitors and carries no session or LiveView bootstrap" do
    first = build_conn() |> get("/offline")

    second =
      build_conn()
      |> put_req_cookie("_evolving_minds_key", "untrusted-cookie")
      |> get("/offline?mind=private")

    assert html_response(first, 200) == html_response(second, 200)
    assert first.resp_cookies == %{}
    assert second.resp_cookies == %{}
    body = html_response(first, 200)
    refute body =~ "csrf-token"
    refute body =~ "data-phx-session"
    refute body =~ "/assets/app.js"
    assert body =~ "Your lab works without a connection"
    assert body =~ "offline_lab"
    assert get_resp_header(first, "x-offline-shell") == ["1"]
    assert get_resp_header(first, "x-offline-version") == [OfflineAssets.cache_id()]
    assert get_resp_header(first, "content-security-policy") |> hd() =~ "script-src 'self'"
    assert get_resp_header(first, "x-robots-tag") == ["noindex, follow"]
  end

  test "manifest references real install icons and limits the app to this origin", %{conn: conn} do
    conn = get(conn, "/manifest.webmanifest")
    data = conn.resp_body |> Jason.decode!()
    assert data["start_url"] == "/lab"
    assert data["scope"] == "/"
    assert data["display"] == "standalone"

    for icon <- data["icons"] do
      assert String.starts_with?(icon["src"], "/images/")

      assert File.regular?(
               Path.join(
                 Application.app_dir(:evolving_minds, "priv/static"),
                 String.trim_leading(icon["src"], "/")
               )
             )

      assert icon["sizes"] in ["192x192", "512x512"]
    end

    assert conn.resp_cookies == %{}
  end

  test "worker has an explicit cache version, update policy and no unresolved template values", %{
    conn: conn
  } do
    conn = get(conn, "/service-worker.js")
    assert response(conn, 200) =~ OfflineAssets.cache_id()
    refute conn.resp_body =~ "__OFFLINE_"
    assert get_resp_header(conn, "cache-control") == ["no-cache, no-transform"]
    assert get_resp_header(conn, "service-worker-allowed") == ["/"]
    assert conn.resp_cookies == %{}
    assert length(OfflineAssets.resources()) == 7

    refute Enum.any?(
             OfflineAssets.resources(),
             &String.starts_with?(&1.url, ["/admin", "/api", "/live"])
           )
  end
end
