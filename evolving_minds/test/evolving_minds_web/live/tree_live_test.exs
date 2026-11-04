defmodule EvolvingMindsWeb.TreeLiveTest do
  use EvolvingMindsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EvolvingMinds.Ancestry
  alias EvolvingMinds.World

  defp spawn_entity(prefix, opts) do
    id = "#{prefix}-#{System.unique_integer([:positive])}"
    {:ok, pid} = World.spawn_entity(id, opts)

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
      end
    end)

    id
  end

  test "renders dynasties with parent-child nesting", %{conn: conn} do
    parent_id = spawn_entity("TRPA", name: "Velnatree")
    child_id = spawn_entity("TRCH", name: "Norixtree", parent_id: parent_id, generation: 2)

    # Ancestry is fed by async telemetry casts.
    assert eventually(fn -> Ancestry.get(child_id) != nil end)

    {:ok, _view, html} = live(conn, "/tree")

    assert html =~ "Dynasties"
    assert html =~ "Velnatree"
    assert html =~ "Norixtree"
    assert html =~ "minds recorded"
  end

  test "dossier lineage chain shows ancestor names", %{conn: conn} do
    parent_id = spawn_entity("LNPA", name: "Velnaline")
    child_id = spawn_entity("LNCH", name: "Norixline", parent_id: parent_id, generation: 2)

    assert eventually(fn -> Ancestry.get(child_id) != nil end)

    {:ok, view, _html} = live(conn, "/")
    html = render_click(view, "select_entity", %{"id" => child_id})

    assert html =~ "Mind Dossier"
    assert html =~ "Velnaline"
    assert html =~ "View full genealogy"
  end

  test "family focus combines with filters and invalid identifiers leave it unchanged", %{
    conn: conn
  } do
    parent = spawn_entity("FMPA", name: "FamilyRoot")
    child = spawn_entity("FMCH", name: "FamilyHeir", parent_id: parent, generation: 2)
    assert eventually(fn -> Ancestry.get(child) != nil end)
    {:ok, view, _html} = live(conn, "/tree")
    render_click(view, "focus_family", %{"id" => parent})
    assert has_element?(view, ".family-focus", "FamilyRoot")
    assert has_element?(view, ".ancestry-identity h3", "FamilyHeir")
    render_click(view, "focus_family", %{"id" => "unknown"})
    assert has_element?(view, ".family-focus", "FamilyRoot")

    render_change(element(view, "#tree-filter-form"), %{
      "filters" => %{"query" => "FamilyHeir", "life" => "all", "tribe" => "all"}
    })

    assert has_element?(view, ".ancestry-identity h3", "FamilyHeir")
    refute has_element?(view, ".ancestry-identity h3", "FamilyRoot")
    render_click(view, "clear_family", %{})
    refute has_element?(view, ".family-focus")
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
