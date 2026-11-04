defmodule EvolvingMindsWeb.LabLiveTest do
  use EvolvingMindsWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "lab renders accessible browser controls without creating shared minds", %{conn: conn} do
    before = MapSet.new(EvolvingMinds.World.get_all_entities())
    {:ok, view, html} = live(conn, "/lab")
    assert html =~ "Evolution Lab"
    assert html =~ "Experiments do not change the shared live world"
    assert has_element?(view, "#evolution-lab[phx-hook=EvolutionLab]")
    assert has_element?(view, "input[name=seed][maxlength='80']")
    assert has_element?(view, "canvas[role=img]")
    assert MapSet.subset?(MapSet.new(EvolvingMinds.World.get_all_entities()), before)
  end
end
