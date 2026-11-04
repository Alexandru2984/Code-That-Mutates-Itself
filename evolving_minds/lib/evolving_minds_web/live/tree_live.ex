defmodule EvolvingMindsWeb.TreeLive do
  use EvolvingMindsWeb, :live_view
  alias EvolvingMinds.{Ancestry, World}
  alias EvolvingMindsWeb.Observatory
  @page_size 40

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Dynasties & Genealogy",
       query: "",
       life: "all",
       tribe: "all",
       view: "recent",
       page: 1,
       family_id: nil,
       visitor_key: session["visitor_key"]
     )
     |> load(), layout: {EvolvingMindsWeb.Layouts, :screen}}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    if EvolvingMindsWeb.RateLimiter.allow?(
         {:tree_refresh, socket.assigns.visitor_key},
         10,
         10_000
       ),
       do: {:noreply, load(socket)},
       else:
         {:noreply, put_flash(socket, :error, "Please wait a moment before refreshing again.")}
  end

  def handle_event("filter", %{"filters" => f}, socket) when is_map(f) do
    socket =
      assign(socket,
        query: Observatory.text(f["query"], 100),
        life: if(f["life"] in ["all", "alive", "dead"], do: f["life"], else: "all"),
        tribe: if(f["tribe"] in ["all", "solari", "umbra"], do: f["tribe"], else: "all"),
        page: 1
      )

    {:noreply, project(socket)}
  end

  def handle_event("view", %{"view" => view}, socket) when view in ["recent", "family"],
    do: {:noreply, socket |> assign(view: view, page: 1) |> project()}

  def handle_event("page", %{"direction" => direction}, socket)
      when direction in ["next", "previous"] do
    page = socket.assigns.page + if(direction == "next", do: 1, else: -1)
    {:noreply, socket |> assign(:page, min(max(page, 1), socket.assigns.pages)) |> project()}
  end

  def handle_event("focus_family", %{"id" => id}, socket)
      when is_binary(id) and byte_size(id) <= 128 do
    if Enum.any?(socket.assigns.families, &(&1.id == id)),
      do: {:noreply, socket |> assign(family_id: id, page: 1) |> project()},
      else: {:noreply, socket}
  end

  def handle_event("clear_family", _, socket),
    do: {:noreply, socket |> assign(family_id: nil, page: 1) |> project()}

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp load(socket) do
    records = Ancestry.all()
    living = MapSet.new(World.get_all_entities())
    records = Enum.map(records, &Map.put(&1, :alive, MapSet.member?(living, &1.id)))

    families = EvolvingMindsWeb.Dynasties.summarize(records)

    family_id =
      if Enum.any?(families, &(&1.id == socket.assigns.family_id)), do: socket.assigns.family_id

    socket
    |> assign(
      records: records,
      recent_rows: records |> Enum.sort_by(& &1.born_at, :desc) |> Enum.map(&{&1, 0}),
      family_rows: forest(records),
      families: families,
      family_id: family_id,
      total: length(records),
      alive: Enum.count(records, & &1.alive),
      names: Map.new(records, &{&1.id, &1.name}),
      refreshed_at: DateTime.utc_now()
    )
    |> project()
  end

  defp project(socket) do
    query = String.downcase(socket.assigns.query)
    family = Enum.find(socket.assigns.families, &(&1.id == socket.assigns.family_id))

    rows =
      if socket.assigns.view == "family",
        do: socket.assigns.family_rows,
        else: socket.assigns.recent_rows

    rows =
      Enum.filter(rows, fn {r, _} ->
        (is_nil(family) or MapSet.member?(family.member_ids, r.id)) and
          (String.contains?(String.downcase(r.name || ""), query) or
             String.contains?(String.downcase(r.id), query)) and
          (socket.assigns.tribe == "all" or to_string(r.tribe) == socket.assigns.tribe) and
          (socket.assigns.life == "all" or socket.assigns.life == "alive" == r.alive)
      end)

    pages = max(ceil(length(rows) / @page_size), 1)
    page = min(socket.assigns.page, pages)

    assign(socket,
      family: family,
      rows: Enum.slice(rows, (page - 1) * @page_size, @page_size),
      matches: length(rows),
      pages: pages,
      page: page
    )
  end

  # A visited set and depth bound tolerate legacy/cyclic ancestry; pagination
  # caps rendered rows, and indentation is capped separately for small screens.
  defp forest(records) do
    children = Enum.group_by(records, & &1.parent_id)
    ids = MapSet.new(records, & &1.id)

    roots =
      records
      |> Enum.filter(&(is_nil(&1.parent_id) or not MapSet.member?(ids, &1.parent_id)))
      |> Enum.sort_by(& &1.born_at, :desc)

    {rows, _seen} = walk(Enum.map(roots ++ records, &{&1, 0}), children, MapSet.new(), [])
    Enum.reverse(rows)
  end

  defp walk([], _, seen, rows), do: {rows, seen}

  defp walk([{record, depth} | rest], children, seen, rows) do
    if MapSet.member?(seen, record.id) or depth > 64 do
      walk(rest, children, seen, rows)
    else
      next =
        Map.get(children, record.id, [])
        |> Enum.sort_by(& &1.born_at)
        |> Enum.map(&{&1, depth + 1})

      walk(next ++ rest, children, MapSet.put(seen, record.id), [{record, depth} | rows])
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="observatory">
      <header class="site-header">
        <a href="/" class="brand" aria-label="Evolving Minds home"><span
          class="brand-mark"
          aria-hidden="true"
        >◎</span><span>Evolving <strong>Minds</strong><small>THE LIVING OBSERVATORY</small></span></a><nav aria-label="Main navigation">
          <.link navigate={~p"/"}>Observatory</.link><.link navigate={~p"/tree"} class="nav-active">Dynasties</.link>
          <.link navigate={~p"/lab"}>Evolution Lab</.link>
        </nav><span class="connection-state"><i></i>Ancestry book</span>
      </header>
      <main id="main-content" class="observatory-main tree-main">
        <section class="tree-intro">
          <p class="eyebrow">EVERY LIFE LEAVES A TRACE</p><h1>The Dynasties</h1><p>
            Meet the ancestors. Follow their descendants. Discover how a world remembers.
          </p><div class="tree-totals">
            <span><strong>{@total}</strong> minds recorded</span><span><strong>{@alive}</strong> alive</span><span><strong>{@total -
              @alive}</strong>
            past lives</span>
          </div>
        </section>
        <section :if={@families != []} class="dynasty-overview" aria-labelledby="families-heading">
          <div class="section-heading">
            <h2 id="families-heading">Living legacies</h2><span>{length(@families)} retained families</span>
          </div>
          <p class="muted">
            Families with the most living members appear first. Counts include only the retained history, including each family's earliest known mind.
          </p>
          <div class="dynasty-grid">
            <article :for={family <- Enum.take(@families, 3)} class="panel dynasty-card">
              <p class="eyebrow">
                {if family.alive > 0, do: "LIVING LINEAGE", else: "REMEMBERED LINEAGE"}
              </p><h3>{family.name}</h3>
              <dl>
                <div>
                  <dt>Living members</dt><dd>{family.alive}</dd>
                </div><div>
                  <dt>Recorded lives</dt><dd>{family.total}</dd>
                </div><div>
                  <dt>Highest generation</dt><dd>{family.max_generation}</dd>
                </div>
              </dl>
              <p :if={family.incomplete} class="muted">
                An earlier ancestor is no longer in the retained book.
              </p><p :if={family.cyclic} class="muted">
                A loop was found in this family's legacy records.
              </p>
              <button
                class="button button-quiet"
                phx-click="focus_family"
                phx-value-id={family.id}
                aria-pressed={to_string(@family_id == family.id)}
              >Explore this family →</button>
            </article>
          </div>
        </section>
        <section class="panel genealogy-panel" aria-labelledby="book-heading">
          <div class="section-heading">
            <h2 id="book-heading">The ancestry book</h2><button
              class="button button-quiet"
              phx-click="refresh"
            >↻ Refresh</button>
          </div><p class="muted">
            Last refreshed {Calendar.strftime(@refreshed_at, "%H:%M:%S")} UTC. The book keeps up to 2,000 recent records; older ancestors may be pruned.
          </p>
          <div class="explore-toolbar">
            <div class="view-tabs" role="group" aria-label="Genealogy view">
              <button
                phx-click="view"
                phx-value-view="recent"
                class={if @view == "recent", do: "active"}
                aria-pressed={to_string(@view == "recent")}
              >Recent lives</button><button
                phx-click="view"
                phx-value-view="family"
                class={if @view == "family", do: "active"}
                aria-pressed={to_string(@view == "family")}
              >Family tree</button>
            </div><span class="muted">{@matches} matches</span>
          </div>
          <form id="tree-filter-form" phx-change="filter" phx-submit="filter" class="tree-filters">
            <div>
              <label class="sr-only" for="tree-search">Search ancestry by name or ID</label><input
                id="tree-search"
                type="search"
                name="filters[query]"
                value={@query}
                maxlength="100"
                placeholder="Search name or ID"
                phx-debounce="250"
              />
            </div><div>
              <label class="sr-only" for="tree-life">Life status</label><select
                id="tree-life"
                name="filters[life]"
              ><option
                :for={
                  {v, label} <- [
                    {"all", "All lives"},
                    {"alive", "Living minds"},
                    {"dead", "Past lives"}
                  ]
                }
                value={v}
                selected={@life == v}
              >
                {label}
              </option></select>
            </div><div>
              <label class="sr-only" for="tree-tribe">Tribe</label><select
                id="tree-tribe"
                name="filters[tribe]"
              ><option
                :for={{v, label} <- [{"all", "All tribes"}, {"solari", "Solari"}, {"umbra", "Umbra"}]}
                value={v}
                selected={@tribe == v}
              >
                {label}
              </option></select>
            </div>
          </form>
          <div :if={@family} class="family-focus" role="status">
            <p>
              Showing the family of <strong>{@family.name}</strong>
              · {@family.total} retained lives. Search and filters apply within this family.
            </p><button phx-click="clear_family" class="text-button">Show all families</button>
          </div>
          <div class="ancestry-rows">
            <article
              :for={{r, depth} <- @rows}
              class={"ancestry-row #{if r.alive, do: "is-alive"}"}
              style={"--depth: #{min(depth, 4)}"}
            >
              <span class={"ancestry-dot #{if r.alive, do: "alive-dot"}"} aria-hidden="true"></span><div class="ancestry-identity">
                <h3>
                  <.link navigate={~p"/?#{[mind: r.id]}"}>{r.name || String.slice(r.id, 0, 8)}</.link><span class={
                    to_string(r.tribe)
                  }>{r.tribe}</span>
                </h3><p>
                  <%= if r.parent_id do %>
                    Child of
                    <.link navigate={~p"/?#{[mind: r.parent_id]}"}>{@names[r.parent_id] ||
                      String.slice(r.parent_id, 0, 8)}</.link>
                  <% else %>
                    First of its line
                  <% end %>
                </p>
              </div><span class="ancestry-generation">Gen {r.generation}</span><span class={"ancestry-status #{if r.alive, do: "cool"}"}>{if r.alive,
                do: "Alive",
                else: r.cause || "Past life"}</span>
            </article>
          </div>
          <div :if={@rows == []} class="empty-state">
            <h3>No records match</h3><p>The book is empty or your filters exclude every mind.</p>
          </div>
          <nav class="pagination" aria-label="Ancestry pages">
            <button
              class="button button-quiet"
              phx-click="page"
              phx-value-direction="previous"
              disabled={@page == 1}
            >← Previous</button><span>Page {@page} of {@pages}</span><button
              class="button button-quiet"
              phx-click="page"
              phx-value-direction="next"
              disabled={@page >= @pages}
            >Next →</button>
          </nav>
        </section><footer class="site-footer">
          <span>EVOLVING MINDS · THE ANCESTRY BOOK</span><.link navigate={~p"/"}>Return to the living world ↗</.link>
        </footer>
      </main>
    </div>
    """
  end
end
