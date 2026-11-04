defmodule EvolvingMindsWeb.LabPageTest do
  use EvolvingMindsWeb.ConnCase, async: false

  test "lab renders accessible browser controls without creating shared minds", %{conn: conn} do
    before = MapSet.new(EvolvingMinds.World.get_all_entities())
    html = conn |> get("/lab") |> html_response(200)
    assert html =~ "Evolution Lab"
    refute html =~ ~s(id="offline-context-heading")
    assert html =~ ~s(property="og:image")
    assert html =~ ~s(name="robots" content="index, follow")
    assert html =~ "Experiments do not change the shared live world"
    assert html =~ ~s(id="evolution-lab")
    refute html =~ "data-phx-session"
    refute html =~ "csrf-token"
    assert html =~ ~s(name="seed")
    assert html =~ ~s(maxlength="80")
    assert html =~ ~s(<canvas role="img")
    assert MapSet.subset?(MapSet.new(EvolvingMinds.World.get_all_entities()), before)
  end
end
