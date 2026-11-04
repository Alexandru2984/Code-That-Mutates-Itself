defmodule EvolvingMindsWeb.WorldLive do
  use EvolvingMindsWeb, :live_view

  alias EvolvingMinds.{Ancestry, Memory, StateStore, World}
  alias EvolvingMindsWeb.{Observatory, RateLimiter, WorldPublisher}

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: WorldPublisher.subscribe()

    socket =
      socket
      |> assign(
        filters: Observatory.filters(%{}),
        only_watched: false,
        watched: [],
        compared: [],
        view: "grid",
        event_filter: "all",
        observation_paused: false,
        latest_snapshot: nil,
        prev_visible: [],
        selected_id: nil,
        selected: nil,
        show_about: false,
        visitor_key: session["visitor_key"],
        page_title: "Live Observatory",
        public_controls: Application.get_env(:evolving_minds, :public_controls, false)
      )
      |> stream_configure(:entities, dom_id: &"entity-#{&1.id}")
      |> apply_snapshot(WorldPublisher.snapshot(), reset: true)

    {:ok, socket, layout: {EvolvingMindsWeb.Layouts, :screen}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    id = if Observatory.id?(params["mind"]), do: params["mind"], else: nil
    selected = build_selected(id)
    title = if selected, do: "#{selected.name} · Mind Dossier", else: "Live Observatory"
    {:noreply, assign(socket, selected_id: id, selected: selected, page_title: title)}
  end

  @impl true
  def handle_info({:world_update, snapshot}, socket) do
    if socket.assigns.observation_paused do
      {:noreply, assign(socket, :latest_snapshot, snapshot)}
    else
      {:noreply, apply_snapshot(socket, snapshot)}
    end
  end

  @impl true
  def handle_event("inject_energy", %{"id" => id}, socket)
      when is_binary(id) and byte_size(id) <= 128 do
    cond do
      not controls_enabled?(socket) ->
        {:noreply, socket}

      is_nil(StateStore.get_state(id)) ->
        {:noreply, put_flash(socket, :error, "This mind is no longer alive.")}

      not allowed?(socket, :inject, 5, 10_000) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Rate limit reached — let the minds breathe for a few seconds."
         )}

      true ->
        World.inject_energy(id)
        {:noreply, socket}
    end
  end

  def handle_event("spawn_mind", _params, socket) do
    cond do
      not controls_enabled?(socket) ->
        {:noreply, socket}

      not allowed?(socket, :spawn, 2, 60_000) ->
        {:noreply, put_flash(socket, :error, "The world needs a moment between new minds.")}

      true ->
        case World.spawn_entity() do
          {:ok, pid} ->
            id = World.id_of(pid)
            name = (StateStore.get_state(id) || %{})[:name] || String.slice(id, 0, 8)

            EvolvingMinds.GlobalEvents.report_event(%{
              type: :birth,
              entity_id: id,
              name: name,
              cause: :visitor
            })

            {:noreply,
             socket
             |> put_flash(:info, "A new mind awakens: #{name}")
             |> apply_snapshot(WorldPublisher.snapshot())}

          {:error, :max_children} ->
            {:noreply,
             put_flash(socket, :error, "The world is full — wait for natural selection.")}

          _ ->
            {:noreply, put_flash(socket, :error, "A mind could not awaken. Try again shortly.")}
        end
    end
  end

  def handle_event("select_entity", %{"id" => id}, socket)
      when is_binary(id) and byte_size(id) <= 128,
      do: {:noreply, push_patch(socket, to: ~p"/?#{[mind: id]}")}

  def handle_event("close_entity", _, socket), do: {:noreply, push_patch(socket, to: ~p"/")}

  def handle_event("toggle_about", _, socket),
    do: {:noreply, assign(socket, :show_about, not socket.assigns.show_about)}

  def handle_event("filter_entities", %{"filters" => filters}, socket) when is_map(filters),
    do:
      {:noreply,
       socket |> assign(:filters, Observatory.filters(filters)) |> refresh_stream(reset: true)}

  def handle_event("clear_filters", _, socket),
    do:
      {:noreply,
       socket
       |> assign(filters: Observatory.filters(%{}), only_watched: false)
       |> refresh_stream(reset: true)}

  def handle_event("set_view", %{"view" => view}, socket) when view in ["grid", "map", "leaders"],
    do: {:noreply, assign(socket, :view, view)}

  def handle_event("filter_events", %{"type" => type}, socket)
      when type in ["all", "death", "reproduction", "mutation", "epoch_change", "birth"],
      do: {:noreply, assign(socket, :event_filter, type)}

  def handle_event("toggle_observation", _, socket) do
    paused = not socket.assigns.observation_paused
    socket = assign(socket, :observation_paused, paused)

    {:noreply,
     if(paused,
       do: socket,
       else: apply_snapshot(socket, socket.assigns.latest_snapshot || WorldPublisher.snapshot())
     )}
  end

  def handle_event("toggle_watch", %{"id" => id}, socket)
      when is_binary(id) and byte_size(id) <= 128 do
    watched = socket.assigns.watched

    cond do
      id in watched ->
        {:noreply, socket |> assign(:watched, List.delete(watched, id)) |> refresh_stream()}

      length(watched) >= 12 ->
        {:noreply, put_flash(socket, :error, "Your watchlist has room for 12 minds.")}

      true ->
        {:noreply, socket |> assign(:watched, watched ++ [id]) |> refresh_stream()}
    end
  end

  def handle_event("restore_watchlist", %{"ids" => ids}, socket) when is_list(ids) do
    watched = ids |> Enum.take(12) |> Enum.filter(&Observatory.id?/1) |> Enum.uniq()
    {:noreply, socket |> assign(:watched, watched) |> refresh_stream()}
  end

  def handle_event("only_watched", _, socket),
    do:
      {:noreply,
       socket
       |> assign(:only_watched, not socket.assigns.only_watched)
       |> refresh_stream(reset: true)}

  def handle_event("clear_watchlist", _, socket),
    do:
      {:noreply,
       socket |> assign(watched: [], only_watched: false) |> refresh_stream(reset: true)}

  def handle_event("toggle_compare", %{"id" => id}, socket)
      when is_binary(id) and byte_size(id) <= 128 do
    ids = socket.assigns.compared

    cond do
      id in ids ->
        {:noreply, socket |> assign(:compared, List.delete(ids, id)) |> refresh_stream()}

      length(ids) >= 3 ->
        {:noreply, put_flash(socket, :error, "Compare up to three minds at a time.")}

      true ->
        {:noreply, socket |> assign(:compared, ids ++ [id]) |> refresh_stream()}
    end
  end

  def handle_event("clear_comparison", _, socket),
    do: {:noreply, socket |> assign(:compared, []) |> refresh_stream()}

  def handle_event(_, _, socket), do: {:noreply, put_flash(socket, :error, "Invalid action.")}

  defp controls_enabled?(socket),
    do:
      socket.assigns.public_controls and
        Application.get_env(:evolving_minds, :public_controls, false) and
        is_binary(socket.assigns.visitor_key)

  defp allowed?(socket, action, limit, window),
    do:
      RateLimiter.allow?({action, socket.assigns.visitor_key}, limit, window) and
        RateLimiter.allow?({:global, action}, limit * 100, window)

  defp apply_snapshot(socket, snapshot, opts \\ []) do
    entities =
      Enum.map(snapshot.entities, &Map.put(&1, :memories, Map.get(snapshot.memories, &1.id, [])))

    socket
    |> assign(
      entities: entities,
      global_events: snapshot.global_events,
      stats: snapshot.stats,
      top_interactions: snapshot.top_interactions,
      epoch: snapshot.epoch,
      all_time: snapshot.all_time,
      summary: Observatory.summary(entities),
      selected: build_selected(socket.assigns.selected_id),
      latest_snapshot: nil,
      total_population: length(entities)
    )
    |> refresh_stream(opts)
  end

  defp refresh_stream(socket, opts \\ []) do
    visible =
      Observatory.visible(
        socket.assigns.entities,
        socket.assigns.filters,
        socket.assigns.watched,
        socket.assigns.only_watched
      )
      |> Enum.map(
        &Map.merge(&1, %{
          watched: &1.id in socket.assigns.watched,
          compared: &1.id in socket.assigns.compared
        })
      )

    previous = socket.assigns.prev_visible

    socket =
      assign(socket,
        prev_visible: visible,
        visible_count: length(visible),
        visible_entities: visible
      )

    if Keyword.get(opts, :reset, false),
      do: stream(socket, :entities, visible, reset: true),
      else: diff_stream(socket, previous, visible)
  end

  defp diff_stream(socket, previous, visible) do
    prev = previous |> Enum.with_index() |> Map.new(fn {e, i} -> {e.id, {e, i}} end)
    ids = MapSet.new(visible, & &1.id)

    socket =
      Enum.reduce(previous, socket, fn e, acc ->
        if MapSet.member?(ids, e.id), do: acc, else: stream_delete(acc, :entities, e)
      end)

    visible
    |> Enum.with_index()
    |> Enum.reduce(socket, fn {e, i}, acc ->
      if prev[e.id] == {e, i}, do: acc, else: stream_insert(acc, :entities, e, at: i)
    end)
  end

  defp build_selected(nil), do: nil

  defp build_selected(id) do
    case StateStore.get_state(id) do
      nil ->
        case Ancestry.get(id) do
          nil ->
            nil

          record ->
            Map.merge(record, %{
              alive: false,
              age: max((record.died_at || System.system_time(:second)) - record.born_at, 0)
            })
        end

      state ->
        state
        |> Map.delete(:behavior_fn)
        |> Map.merge(%{
          alive: true,
          memories: Memory.get_memories(id),
          age: max(System.system_time(:second) - state.born_at, 0),
          ancestors: Enum.drop(Ancestry.lineage(id), 1)
        })
    end
  end

  defp lookup(entities, id),
    do:
      Enum.find(entities, &(&1.id == id)) || Ancestry.get(id) ||
        %{id: id, name: String.slice(id, 0, 8)}

  defp pct(trait), do: round(trait * 100)
  defp format_age(value), do: Observatory.age(value)
  defp filtered_events(events, "all"), do: events
  defp filtered_events(events, filter), do: Enum.filter(events, &(to_string(&1.type) == filter))

  defp line_points(stats, field) do
    values = Enum.reverse(stats)

    max_value =
      if field == :population,
        do: max(Enum.max(Enum.map(values, & &1.population), fn -> 1 end), 1),
        else: 1

    values
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {value, i} ->
      "#{i * 100 / max(length(values) - 1, 1)},#{95 - Map.fetch!(value, field) / max_value * 85}"
    end)
  end

  # The event feed reads as a story; every branch degrades gracefully
  # for events recorded before names existed.
  defp event_sentence(%{type: :death} = event) do
    victim = event[:name] || fallback_name(event)

    cond do
      event[:killer_name] -> "#{victim} was slain by #{event.killer_name}"
      event[:killer_id] -> "#{victim} was slain by #{String.slice(event.killer_id, 0, 8)}"
      true -> "#{victim} died of #{event[:cause] || :exhaustion}"
    end
  end

  defp event_sentence(%{type: :mutation} = event) do
    "The mind of #{event[:name] || fallback_name(event)} mutated"
  end

  defp event_sentence(%{type: :reproduction} = event) do
    child = event[:name] || fallback_name(event)
    parent = event[:parent_name] || (event[:parent_id] && String.slice(event.parent_id, 0, 8))
    "#{parent || "A mind"} begat #{child} (gen #{event[:generation] || "?"})"
  end

  defp event_sentence(%{type: :birth, cause: :visitor} = event) do
    "A visitor summoned #{event[:name] || fallback_name(event)}"
  end

  defp event_sentence(%{type: :birth} = event), do: event[:detail] || "New minds emerged"
  defp event_sentence(event), do: event[:detail] || "The world stirred"

  defp fallback_name(%{entity_id: id}) when is_binary(id), do: String.slice(id, 0, 8)
  defp fallback_name(_event), do: "A mind"

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="observatory"
      class="observatory"
      phx-hook="Watchlist"
      data-watchlist={Jason.encode!(@watched)}
    >
      <header class="site-header">
        <a href="/" class="brand" aria-label="Evolving Minds home"><span
          class="brand-mark"
          aria-hidden="true"
        >◎</span><span>Evolving <strong>Minds</strong><small>THE LIVING OBSERVATORY</small></span></a>
        <nav aria-label="Main navigation">
          <a href="#explore" class="nav-active">Observatory</a><.link navigate={~p"/tree"}>Dynasties</.link>
          <.link navigate={~p"/lab"}>Lab</.link><button phx-click="toggle_about">Field guide
          <span aria-hidden="true">↗</span></button>
        </nav>
        <span class="connection-state"><i aria-hidden="true"></i><span class="when-connected">Live world</span><span class="when-disconnected">Reconnecting…</span></span>
      </header>
      <main id="main-content" class="observatory-main">
        <section class="world-intro" aria-labelledby="world-title">
          <div>
            <p class="eyebrow">
              AUTONOMOUS HEURISTIC SIMULATOR <span>• EXPERIMENT IN PROGRESS</span>
            </p><h1 id="world-title">A small world.<br /><span>Endless possibilities.</span></h1><p class="intro-copy">
              They meet, compete, cooperate, and evolve. Follow a digital mind. See which way life goes.
            </p>
          </div>
          <div class={"epoch-panel epoch-#{@epoch}"}>
            <span class="eyebrow">CURRENT ENVIRONMENT</span><span
              class="epoch-orbit"
              aria-hidden="true"
            >◌</span><h2>{String.capitalize(to_string(@epoch))}</h2><p>
              {case @epoch do
                :famine -> "Resources are scarce. Survival gets harder."
                :abundance -> "Energy is plentiful. A chance to flourish."
                _ -> "A delicate balance of risk and reward."
              end}
            </p><span class="epoch-cost">{Map.fetch!(%{normal: 5, abundance: 3, famine: 8}, @epoch)} energy per action</span>
          </div>
        </section>
        <section class="world-metrics" aria-label="World at a glance">
          <div>
            <span class="metric-label">Population</span><strong>{@total_population}<small>/ 50</small></strong><span>autonomous minds</span>
          </div>
          <div>
            <span class="metric-label">Average energy</span><strong>{@summary.energy}<small>%</small></strong><span>{@summary.critical} in critical condition</span>
          </div>
          <div>
            <span class="metric-label">Generation</span><strong>{@summary.generation}</strong><span>furthest living descendant</span>
          </div>
          <div class="tribe-metric">
            <span class="metric-label">Two tribes, one world</span><div class="tribe-numbers">
              <strong class="solari">{@summary.solari}<small>Solari</small></strong><strong class="umbra">{@summary.umbra}<small>Umbra</small></strong>
            </div><div
              class="tribe-balance"
              aria-label={"Solari #{@summary.solari}, Umbra #{@summary.umbra}"}
            >
              <span style={"width: #{if @total_population > 0, do: round(@summary.solari / @total_population * 100), else: 50}%"}></span>
            </div>
          </div>
        </section>
        <section
          :if={@compared != []}
          id="comparison"
          class="panel comparison"
          aria-labelledby="compare-heading"
        >
          <div class="section-heading">
            <h2 id="compare-heading">Compare minds <span>{length(@compared)}/3</span></h2><button
              class="text-button"
              phx-click="clear_comparison"
            >Clear comparison</button>
          </div>
          <div class="comparison-grid">
            <div :for={id <- @compared} class="comparison-item">
              <% mind = lookup(@entities, id) %>
              <div class="section-heading">
                <.link patch={~p"/?#{[mind: id]}"}>{mind.name || String.slice(id, 0, 8)}</.link><button
                  phx-click="toggle_compare"
                  phx-value-id={id}
                  aria-label={"Remove #{mind.name} from comparison"}
                >×</button>
              </div>
              <%= if mind[:traits] do %>
                <p><span>Energy</span><strong>{mind.energy}%</strong></p><p>
                  <span>Aggression</span><strong>{pct(mind.traits.aggression)}%</strong>
                </p><p><span>Curiosity</span><strong>{pct(mind.traits.curiosity)}%</strong></p><p>
                  <span>Generation</span><strong>{mind.generation}</strong>
                </p><p>
                  <span>Strategy</span><strong>{Observatory.personality(mind.traits)}</strong>
                </p>
              <% else %>
                <p>This mind has died</p>
              <% end %>
            </div>
          </div>
        </section>
        <div class="world-layout">
          <section id="explore" class="explore" aria-labelledby="explore-heading">
            <div class="section-heading explore-heading">
              <div>
                <p class="eyebrow">MEET THE POPULATION</p><h2 id="explore-heading">
                  Life, in real time<span class="count-badge">{@visible_count}</span>
                </h2>
              </div><div class="explore-actions">
                <button
                  class="button button-quiet"
                  phx-click="toggle_observation"
                  aria-pressed={to_string(@observation_paused)}
                >{if @observation_paused, do: "▶ Resume view", else: "Ⅱ Pause view"}</button><button
                  :if={@public_controls}
                  class="button button-primary"
                  phx-click="spawn_mind"
                >+ Spawn a Mind</button>
              </div>
            </div>
            <p :if={@observation_paused} class="notice" role="status">
              Observation paused. The shared world continues evolving. Resume to catch up.
            </p>
            <div class="explore-toolbar">
              <div class="view-tabs" role="group" aria-label="Observation view">
                <button
                  :for={
                    {label, view} <- [{"Minds", "grid"}, {"Trait map", "map"}, {"Leaders", "leaders"}]
                  }
                  phx-click="set_view"
                  phx-value-view={view}
                  class={if @view == view, do: "active"}
                  aria-pressed={to_string(@view == view)}
                >{label}</button>
              </div>
              <button
                class={"watch-filter #{if @only_watched, do: "active"}"}
                phx-click="only_watched"
                aria-pressed={to_string(@only_watched)}
              >☆ Watchlist <span>{length(@watched)}</span></button>
            </div>
            <form
              id="filter-form"
              phx-change="filter_entities"
              phx-submit="filter_entities"
              class="filter-form"
            >
              <div class="search-field">
                <label class="sr-only" for="mind-search">Search by name or entity ID</label><input
                  id="mind-search"
                  type="search"
                  name="filters[query]"
                  value={@filters.query}
                  placeholder="Search name or entity ID"
                  maxlength="100"
                  phx-debounce="250"
                />
              </div>
              <div>
                <label class="sr-only" for="tribe-filter">Tribe</label><select
                  id="tribe-filter"
                  name="filters[tribe]"
                ><option
                  :for={
                    {value, label} <- [
                      {"all", "All tribes"},
                      {"solari", "Solari"},
                      {"umbra", "Umbra"}
                    ]
                  }
                  value={value}
                  selected={@filters.tribe == value}
                >
                  {label}
                </option></select>
              </div>
              <div>
                <label class="sr-only" for="status-filter">Condition</label><select
                  id="status-filter"
                  name="filters[status]"
                ><option
                  :for={
                    {value, label} <- [
                      {"all", "All conditions"},
                      {"thriving", "Thriving · ≥75%"},
                      {"critical", "Critical · ≤25%"},
                      {"descendants", "Descendants"}
                    ]
                  }
                  value={value}
                  selected={@filters.status == value}
                >
                  {label}
                </option></select>
              </div>
              <div>
                <label class="sr-only" for="sort-filter">Sort minds</label><select
                  id="sort-filter"
                  name="filters[sort]"
                ><option
                  :for={
                    {value, label} <- [
                      {"energy_desc", "Energy high"},
                      {"energy_asc", "Energy low"},
                      {"aggression_desc", "Aggression"},
                      {"curiosity_desc", "Curiosity"},
                      {"generation_desc", "Generation"},
                      {"oldest", "Oldest first"}
                    ]
                  }
                  value={value}
                  selected={@filters.sort == value}
                >
                  {label}
                </option></select>
              </div>
            </form>
            <div class="results-label">
              <span>Visible {@visible_count} of {@total_population} minds</span><button
                class="text-button"
                phx-click="clear_filters"
              >Reset filters</button>
            </div>
            <div
              id="entities-grid"
              phx-update="stream"
              class={"minds-grid #{if @view != "grid", do: "hidden"}"}
            >
              <article
                :for={{dom_id, entity} <- @streams.entities}
                id={dom_id}
                class={"mind-card tribe-#{entity.tribe} #{if entity.watched, do: "is-watched"}"}
              >
                <div class="card-top">
                  <div class={"mind-avatar #{entity.tribe}"} aria-hidden="true">
                    {String.first(entity.name || "?")}
                  </div><div class="mind-identity">
                    <h3>
                      <.link patch={~p"/?#{[mind: entity.id]}"}>{entity.name || "Unnamed"}</.link>
                    </h3><span class={"tribe-label #{entity.tribe}"}>{entity.tribe}
                    <span>· Gen {entity.generation}</span></span>
                  </div><button
                    class={"star-button #{if entity.watched, do: "active"}"}
                    phx-click="toggle_watch"
                    phx-value-id={entity.id}
                    aria-label={"#{if entity.watched, do: "Unwatch", else: "Watch"} #{entity.name}"}
                    aria-pressed={to_string(entity.watched)}
                  >{if entity.watched, do: "★", else: "☆"}</button>
                </div>
                <div class="mind-caption">
                  <span>{Observatory.personality(entity.traits)}</span><code>{String.slice(
                    entity.id,
                    0,
                    8
                  )}</code>
                </div>
                <div class="energy-label">
                  <span><i class={if entity.energy <= 25, do: "critical-dot", else: "alive-dot"}></i>Vitality</span><strong class={
                    if entity.energy <= 25, do: "danger"
                  }>{entity.energy}%</strong>
                </div><meter
                  class={"energy-meter #{if entity.energy <= 25, do: "is-critical"}"}
                  min="0"
                  max="100"
                  value={entity.energy}
                  aria-label={"#{entity.name} energy"}
                >{entity.energy}%</meter>
                <div class="trait-pair">
                  <div>
                    <span>Aggression</span><strong class="warm">{pct(entity.traits.aggression)}<small>%</small></strong><div class="trait-track">
                      <span class="aggression" style={"width: #{pct(entity.traits.aggression)}%"}></span>
                    </div>
                  </div><div>
                    <span>Curiosity</span><strong class="cool">{pct(entity.traits.curiosity)}<small>%</small></strong><div class="trait-track">
                      <span class="curiosity" style={"width: #{pct(entity.traits.curiosity)}%"}></span>
                    </div>
                  </div>
                </div>
                <div class="recent-memory">
                  <%= if entity.memories == [] do %>
                    <span>A new story is beginning.</span>
                  <% else %>
                    <% {type, sender} = hd(entity.memories) %><span class={
                      if type == :attack, do: "warm", else: "cool"
                    }>{type}</span><span>← {String.slice(sender, 0, 6)}</span>
                  <% end %>
                </div>
                <div class="card-actions">
                  <button class="text-button" phx-click="select_entity" phx-value-id={entity.id}>Details
                  <span aria-hidden="true">↗</span></button><button
                    class={"compare-button #{if entity.compared, do: "active"}"}
                    phx-click="toggle_compare"
                    phx-value-id={entity.id}
                    aria-pressed={to_string(entity.compared)}
                  >{if entity.compared, do: "✓ Comparing", else: "+ Compare"}</button><button
                    :if={@public_controls}
                    class="energy-button"
                    phx-click="inject_energy"
                    phx-value-id={entity.id}
                    aria-label={"Give #{entity.name} 20 energy"}
                  >+ Energy</button>
                </div>
              </article>
            </div>
            <div :if={@view == "map"} class="panel trait-map-panel">
              <div class="section-heading">
                <h3>A world of personalities</h3><span>Tap a mind to explore</span>
              </div><div
                class="trait-map"
                role="group"
                aria-label="Interactive map: aggression increases rightward, curiosity upward"
              >
                <span class="map-quadrant q1">CURIOUS DIPLOMATS</span><span class="map-quadrant q2">CURIOUS WARRIORS</span><span class="map-quadrant q3">QUIET OBSERVERS</span><span class="map-quadrant q4">BOLD COMPETITORS</span><button
                  :for={e <- @visible_entities}
                  class={"map-mind #{e.tribe}"}
                  style={"left: #{5 + pct(e.traits.aggression) * 0.9}%; bottom: #{5 + pct(e.traits.curiosity) * 0.9}%"}
                  phx-click="select_entity"
                  phx-value-id={e.id}
                  title={"#{e.name}: #{pct(e.traits.aggression)}% aggression, #{pct(e.traits.curiosity)}% curiosity"}
                  aria-label={"Open #{e.name}: #{pct(e.traits.aggression)}% aggression, #{pct(e.traits.curiosity)}% curiosity"}
                ><span></span></button>
              </div><div class="map-axis"><span>↑ Curiosity</span><span>Aggression →</span></div><p class="muted">
                Each dot is a living mind. Solari are gold; Umbra are violet. Positions change as traits mutate.
              </p>
            </div>
            <div :if={@view == "leaders"} class="leaderboards">
              <section
                :for={
                  {title, field} <- [
                    {"Most energetic", :energy},
                    {"Most curious", :curiosity},
                    {"Furthest descendants", :generation}
                  ]
                }
                class="panel"
              >
                <h3>{title}</h3><ol class="ranking">
                  <li :for={
                    {e, index} <-
                      @visible_entities
                      |> Enum.sort_by(
                        &if(field == :curiosity, do: &1.traits.curiosity, else: Map.fetch!(&1, field)),
                        :desc
                      )
                      |> Enum.take(5)
                      |> Enum.with_index(1)
                  }>
                    <span class="rank">{index}</span><.link patch={~p"/?#{[mind: e.id]}"}>{e.name}<small class={
                      to_string(e.tribe)
                    }>{e.tribe}</small></.link><strong>{if field == :curiosity,
                      do: "#{pct(e.traits.curiosity)}%",
                      else: Map.fetch!(e, field)}</strong>
                  </li>
                </ol>
              </section>
            </div>
            <div :if={@visible_count == 0} class="empty-state">
              <span aria-hidden="true">◎</span><h3>No entities match</h3><p>
                Try another name, reset your filters, or wait for a new generation.
              </p><button class="button button-quiet" phx-click="clear_filters">Show all minds</button>
            </div>
            <section :if={@watched != []} class="panel watchlist-panel">
              <div class="section-heading">
                <h3>Your watchlist</h3><button class="text-button" phx-click="clear_watchlist">Clear watchlist</button>
              </div><p class="muted">
                Saved in this browser. Follow a story, even after a mind is gone.
              </p><div class="watchlist-items">
                <div :for={id <- @watched}>
                  <% mind = lookup(@entities, id) %><.link patch={~p"/?#{[mind: id]}"}>{mind.name ||
                    String.slice(id, 0, 8)}<small>{if Enum.any?(@entities, &(&1.id == id)),
                    do: "Alive",
                    else: "No longer living"}</small></.link><button
                    phx-click="toggle_watch"
                    phx-value-id={id}
                    aria-label={"Unwatch #{mind.name}"}
                  >×</button>
                </div>
              </div>
            </section>
          </section>
          <aside class="world-sidebar" aria-label="World stories and trends">
            <section class="panel events-panel">
              <div class="section-heading">
                <h2>World journal</h2><span class="live-label">Global Events</span>
              </div><label class="sr-only" for="event-type">Filter journal events</label><form
                id="event-filter-form"
                phx-change="filter_events"
              >
                <select id="event-type" name="type"><option
                  :for={
                    {value, label} <- [
                      {"all", "All stories"},
                      {"reproduction", "New generations"},
                      {"death", "Deaths"},
                      {"mutation", "Mutations"},
                      {"epoch_change", "Epoch changes"},
                      {"birth", "New arrivals"}
                    ]
                  }
                  value={value}
                  selected={@event_filter == value}
                >
                  {label}
                </option></select>
              </form><div class="journal-list">
                <article
                  :for={event <- filtered_events(@global_events, @event_filter)}
                  class={"journal-entry event-#{event.type}"}
                >
                  <div>
                    <span>{String.replace(to_string(event.type), "_", " ")}</span><time datetime={
                      DateTime.to_iso8601(event.timestamp)
                    }>{Calendar.strftime(event.timestamp, "%H:%M:%S")} UTC</time>
                  </div><p>{event_sentence(event)}</p>
                </article><p :if={filtered_events(@global_events, @event_filter) == []} class="muted">
                  No stories in this category yet. Keep watching.
                </p>
              </div>
            </section>
            <section class="panel trends-panel">
              <div class="section-heading">
                <h2>Evolution Trends</h2><span>last 100 seconds</span>
              </div><p class="chart-label">Trait Distribution · average over time</p><svg
                viewBox="0 0 100 100"
                preserveAspectRatio="none"
                class="trend-chart"
                role="img"
                aria-label="Aggression and curiosity averages over recent samples"
              ><line x1="0" y1="50" x2="100" y2="50" stroke="currentColor" stroke-dasharray="2 3" /><polyline
                points={line_points(@stats, :avg_aggression)}
                fill="none"
                stroke="#f3a66b"
                stroke-width="2"
                vector-effect="non-scaling-stroke"
              /><polyline
                points={line_points(@stats, :avg_curiosity)}
                fill="none"
                stroke="#75d9c5"
                stroke-width="2"
                vector-effect="non-scaling-stroke"
              /></svg><div class="chart-legend">
                <span class="warm">● Aggression</span><span class="cool">● Curiosity</span>
              </div><p :if={@stats == []} class="muted">Collecting the first samples…</p><p class="chart-label">
                Population
              </p><svg
                viewBox="0 0 100 100"
                preserveAspectRatio="none"
                class="population-chart"
                role="img"
                aria-label="Population over recent samples"
              ><polyline
                points={line_points(@stats, :population)}
                fill="none"
                stroke="#75d9c5"
                stroke-width="2"
                vector-effect="non-scaling-stroke"
              /></svg>
            </section>
            <section class="panel records-panel">
              <div class="section-heading">
                <h2>Hall of Fame</h2><span>all time</span>
              </div><dl class="record-counters">
                <div>
                  <dt>Births</dt><dd>{@all_time.births}</dd>
                </div><div>
                  <dt>Deaths</dt><dd>{@all_time.deaths}</dd>
                </div><div>
                  <dt>Mutations</dt><dd>{@all_time.mutations}</dd>
                </div><div>
                  <dt>Max generation</dt><dd>{@all_time.max_generation}</dd>
                </div>
              </dl><div
                :for={
                  {label, record, field} <- [
                    {"Oldest mind", @all_time.oldest, :age},
                    {"Most feared", @all_time.most_feared, :kills},
                    {"Most prolific", @all_time.most_prolific, :children}
                  ]
                }
                :if={record}
                class="record-holder"
              >
                <span>{label}<.link patch={~p"/?#{[mind: record.id]}"}>{record[:name] ||
                  String.slice(record.id, 0, 8)}</.link></span><strong>{if field == :age,
                  do: format_age(record[field]),
                  else: record[field]}</strong>
              </div>
            </section>
            <section class="field-note">
              <p class="eyebrow">A NOTE FROM THE FIELD</p><h3>
                Small choices.<br />Generations of consequences.
              </h3><p>
                Energy keeps a mind alive. Traits shape its choices. Its descendants carry a little of both.
              </p><button class="text-button" phx-click="toggle_about">Learn how this world works ↗</button>
            </section>
          </aside>
        </div>
        <footer class="site-footer">
          <span>EVOLVING MINDS <span>· A persistent experiment in artificial life</span></span><div>
            <a href="/api/world" download="evolving-minds.json">Export world JSON ↗</a><.link navigate={
              ~p"/tree"
            }>Explore dynasties ↗</.link>
          </div>
        </footer>
      </main>
      <div
        :if={@show_about}
        class="dialog-backdrop"
        id="field-guide-dialog"
        phx-hook="Dialog"
        data-close-event="toggle_about"
      >
        <button class="dialog-overlay" phx-click="toggle_about" aria-label="Close field guide"></button><section
          class="guide-dialog"
          role="dialog"
          aria-modal="true"
          aria-labelledby="guide-title"
          tabindex="-1"
        >
          <div class="section-heading">
            <p class="eyebrow">YOUR FIELD GUIDE</p><button
              class="close-button"
              phx-click="toggle_about"
              aria-label="Close field guide"
            >×</button>
          </div><h2 id="guide-title">Welcome to a living world.</h2><p>
            You are watching a <strong>live artificial-life simulation</strong>. Every mind is an autonomous process with inherited aggression and curiosity. This is procedural behavior, not a language model.
          </p><ol class="guide-steps">
            <li>
              <strong>Observe.</strong>
              Open Details to read memories, lineage, and the Active Heuristic. The trait map reveals personality clusters.
            </li><li>
              <strong>Follow.</strong>
              Star up to 12 minds in your browser. Compare three side by side, or pause your view to look more closely.
            </li><li>
              <strong>Understand.</strong>
              Every interaction settles in energy. Robbing a fleeing pacifist pays; wars drain both sides; cooperation can reward both minds.
            </li><li>
              <strong>Watch evolution.</strong>
              Parents are chosen in proportion to energy. Children inherit jittered traits: frequency-dependent selection shapes each generation.
            </li>
          </ol><p>
            Abundance costs 3 energy per action, normal costs 5, famine costs 8. Members of the same tribe initiate greetings. Responses still depend on personality.
          </p><p>
            The world survives restarts. Watchlist data stays in this browser; clearing browser storage removes it. Pausing your view never pauses the shared simulation.
          </p><p :if={@public_controls} class="notice">
            Visitor controls: +20 energy, up to five injections per 10 seconds; two spawns per minute. Limits are shared across tabs. The world holds up to 50 minds.
          </p><button class="button button-primary" phx-click="toggle_about">Start exploring →</button>
        </section>
      </div>
      <div
        :if={@selected_id}
        class="dialog-backdrop dossier-backdrop"
        id="dossier-dialog"
        phx-hook="Dialog"
        data-close-event="close_entity"
      >
        <button class="dialog-overlay" phx-click="close_entity" aria-label="Close mind dossier"></button><aside
          id="entity-detail"
          class="dossier-dialog"
          role="dialog"
          aria-modal="true"
          aria-labelledby="dossier-title"
          tabindex="-1"
        >
          <div class="section-heading">
            <p class="eyebrow">Mind Dossier</p><button
              class="close-button"
              phx-click="close_entity"
              aria-label="Close mind dossier"
            >×</button>
          </div><h2 id="dossier-title">
            {if @selected, do: @selected.name, else: String.slice(@selected_id, 0, 16)}
          </h2><code class="dossier-id">{@selected_id}</code><div class="dossier-actions">
            <button class="button button-quiet" phx-click="toggle_watch" phx-value-id={@selected_id}>{if @selected_id in @watched,
              do: "★ Watching",
              else: "☆ Watch mind"}</button><button
              id="copy-mind-link"
              phx-hook="CopyLink"
              class="button button-quiet"
            >Copy link ↗</button>
          </div>
          <%= if @selected && @selected.alive do %>
            <dl class="dossier-stats">
              <div>
                <dt>Generation</dt><dd>{@selected.generation}</dd>
              </div><div>
                <dt>Age</dt><dd>{format_age(@selected.age)}</dd>
              </div><div>
                <dt>Energy</dt><dd>{@selected.energy}%</dd>
              </div><div>
                <dt>Kills</dt><dd>{@selected.kills}</dd>
              </div>
            </dl><h3>Traits · {Observatory.personality(@selected.traits)}</h3><p class="trait-detail">
              <span>Aggression <strong class="warm">{pct(@selected.traits.aggression)}%</strong></span><span>Curiosity
              <strong class="cool">{pct(@selected.traits.curiosity)}%</strong></span>
            </p><h3>Lineage</h3><p :if={@selected.ancestors == []} class="muted">
              First of its line — primordial spawn
            </p><div class="lineage-list">
              <.link :for={ancestor <- @selected.ancestors} patch={~p"/?#{[mind: ancestor.id]}"}>{ancestor.name ||
                String.slice(ancestor.id, 0, 8)} <span>· Gen {ancestor.generation}</span></.link>
            </div><.link navigate={~p"/tree"} class="text-button">View full genealogy →</.link><details
              class="heuristic"
              open
            >
              <summary>Active Heuristic</summary><pre>{@selected.behavior_source}</pre>
            </details><h3>Memory Stream ({length(@selected.memories)})</h3><div class="memory-list">
              <div :for={{type, sender} <- Enum.take(@selected.memories, 30)}>
                <span>{type}</span><.link patch={~p"/?#{[mind: sender]}"}>← {String.slice(
                  sender,
                  0,
                  8
                )}</.link>
              </div><p :if={@selected.memories == []} class="muted">
                No memories yet. A new story is beginning.
              </p>
            </div>
          <% else %>
            <div class="notice">
              <h3>This mind has died</h3><p>
                Its state and memories have been purged from the world. Its story may still live in the ancestry book.
              </p><p :if={@selected}>
                Generation {@selected.generation} · Lived {format_age(@selected.age)} · {@selected.cause ||
                  "record unavailable"}
              </p>
            </div><.link navigate={~p"/tree"} class="text-button">Explore the ancestry book →</.link>
          <% end %>
        </aside>
      </div>
    </div>
    """
  end
end
