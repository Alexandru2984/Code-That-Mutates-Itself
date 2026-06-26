defmodule EvolvingMindsWeb.HealthControllerTest do
  use EvolvingMindsWeb.ConnCase, async: true

  test "GET /healthz", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
