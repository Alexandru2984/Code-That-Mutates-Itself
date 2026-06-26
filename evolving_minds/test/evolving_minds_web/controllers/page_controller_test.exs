defmodule EvolvingMindsWeb.PageControllerTest do
  use EvolvingMindsWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Evolving"
    assert response =~ "Autonomous Heuristic Simulator"
    assert response =~ "Filter entity ID"
    assert response =~ "Energy high"
    assert response =~ "Visible"
  end
end
