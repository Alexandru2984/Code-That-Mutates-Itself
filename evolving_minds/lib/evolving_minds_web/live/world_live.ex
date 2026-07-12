defmodule EvolvingMindsWeb.WorldLive do
  use EvolvingMindsWeb, :live_view

  alias EvolvingMinds.World
  alias EvolvingMindsWeb.WorldPublisher

  # Public energy injections are rate limited per connected client:
  # at most @inject_limit within a sliding @inject_window_ms window.
  @inject_limit 5
  @inject_window_ms 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: WorldPublisher.subscribe()

    socket =
      socket
      |> assign(:query, "")
      |> assign(:sort, "energy_desc")
      |> assign(:prev_visible, [])
      |> assign(:inject_history, [])
      |> assign(public_controls: Application.get_env(:evolving_minds, :public_controls, false))
      |> stream_configure(:entities, dom_id: &"entity-#{&1.id}")
      |> apply_snapshot(WorldPublisher.snapshot(), reset: true)

    {:ok, socket, layout: {EvolvingMindsWeb.Layouts, :screen}}
  end

  @impl true
  def handle_info({:world_update, snapshot}, socket) do
    {:noreply, apply_snapshot(socket, snapshot)}
  end

  @impl true
  def handle_event("inject_energy", %{"id" => id}, socket) do
    cond do
      not socket.assigns.public_controls ->
        {:noreply, socket}

      true ->
        now = System.monotonic_time(:millisecond)

        recent =
          Enum.filter(socket.assigns.inject_history, &(now - &1 < @inject_window_ms))

        if length(recent) < @inject_limit do
          World.inject_energy(id)

          socket =
            socket
            |> assign(:inject_history, [now | recent])
            |> apply_snapshot(WorldPublisher.snapshot())

          {:noreply, socket}
        else
          {:noreply,
           socket
           |> assign(:inject_history, recent)
           |> put_flash(:error, "Rate limit reached — let the minds breathe for a few seconds.")}
        end
    end
  end

  @impl true
  def handle_event("filter_entities", %{"filters" => filters}, socket) do
    query = Map.get(filters, "query", "") |> String.trim()
    sort = Map.get(filters, "sort", "energy_desc")

    socket =
      socket
      |> assign(:query, query)
      |> assign(:sort, sort)
      |> refresh_stream(socket.assigns.entities, reset: true)

    {:noreply, socket}
  end

  defp apply_snapshot(socket, snapshot, opts \\ []) do
    entities = merge_memories(snapshot.entities, snapshot.memories)

    socket
    |> assign(:global_events, snapshot.global_events)
    |> assign(:stats, snapshot.stats)
    |> assign(:top_interactions, snapshot.top_interactions)
    |> assign(:epoch, snapshot.epoch)
    |> assign(:all_time, snapshot.all_time)
    |> assign(:entities, entities)
    |> refresh_stream(entities, opts)
  end

  # Memories ride inside each stream item: a stream card only re-renders
  # when re-inserted, so everything it displays must be part of the item.
  defp merge_memories(entities, memories) do
    Enum.map(entities, &Map.put(&1, :memories, Map.get(memories, &1.id, [])))
  end

  defp refresh_stream(socket, entities, opts) do
    visible =
      entities |> filter_entities(socket.assigns.query) |> sort_entities(socket.assigns.sort)

    prev_visible = socket.assigns.prev_visible

    socket =
      socket
      |> assign(:prev_visible, visible)
      |> assign(:visible_count, length(visible))
      |> assign(:total_population, length(entities))

    if Keyword.get(opts, :reset, false) do
      stream(socket, :entities, visible, reset: true)
    else
      diff_stream(socket, prev_visible, visible)
    end
  end

  # Sends only what changed: deletes for entities that left the visible
  # set, and positional re-inserts for entities whose data or sort index
  # changed. Untouched cards produce no payload at all.
  defp diff_stream(socket, prev_visible, visible) do
    prev_by_id = Map.new(prev_visible, &{&1.id, &1})

    prev_index =
      prev_visible |> Enum.with_index() |> Map.new(fn {entity, i} -> {entity.id, i} end)

    visible_ids = MapSet.new(visible, & &1.id)

    socket =
      Enum.reduce(prev_visible, socket, fn entity, acc ->
        if MapSet.member?(visible_ids, entity.id) do
          acc
        else
          stream_delete(acc, :entities, entity)
        end
      end)

    visible
    |> Enum.with_index()
    |> Enum.reduce(socket, fn {entity, index}, acc ->
      if Map.get(prev_by_id, entity.id) == entity and Map.get(prev_index, entity.id) == index do
        acc
      else
        stream_insert(acc, :entities, entity, at: index)
      end
    end)
  end

  defp filter_entities(entities, ""), do: entities

  defp filter_entities(entities, query) do
    normalized_query = String.downcase(query)

    Enum.filter(entities, fn entity ->
      entity.id |> String.downcase() |> String.contains?(normalized_query)
    end)
  end

  defp sort_entities(entities, "energy_asc"), do: Enum.sort_by(entities, & &1.energy)

  defp sort_entities(entities, "aggression_desc"),
    do: Enum.sort_by(entities, & &1.traits.aggression, :desc)

  defp sort_entities(entities, "curiosity_desc"),
    do: Enum.sort_by(entities, & &1.traits.curiosity, :desc)

  defp sort_entities(entities, _), do: Enum.sort_by(entities, & &1.energy, :desc)

  defp epoch_class(:abundance), do: "text-emerald-400"
  defp epoch_class(:famine), do: "text-rose-400"
  defp epoch_class(_), do: "text-slate-500"

  defp epoch_label(:abundance), do: "Epoch: Abundance"
  defp epoch_label(:famine), do: "Epoch: Famine"
  defp epoch_label(_), do: "Epoch: Normal"

  defp format_age(seconds) when seconds >= 3600,
    do: "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"

  defp format_age(seconds) when seconds >= 60, do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  defp format_age(seconds), do: "#{seconds}s"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen w-full bg-[#050608] text-slate-300 font-sans selection:bg-cyan-500/30 flex flex-col">
      <!-- Fixed Header for better UX on long lists -->
      <header class="sticky top-0 z-50 w-full bg-[#050608]/80 backdrop-blur-xl border-b border-white/5 px-4 py-4 md:px-8">
        <div class="max-w-[2400px] mx-auto flex flex-col xl:flex-row items-stretch xl:items-center justify-between gap-4">
          <div class="relative group text-center sm:text-left">
            <div class="absolute -inset-2 bg-gradient-to-r from-cyan-600 to-blue-700 rounded-xl blur-lg opacity-20 group-hover:opacity-40 transition duration-1000">
            </div>
            <h1 class="relative text-3xl md:text-4xl font-black tracking-normal text-white">
              Evolving
              <span class="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 via-blue-500 to-indigo-600">
                Minds
              </span>
            </h1>
            <div class="flex flex-wrap items-center justify-center sm:justify-start gap-3 mt-1">
              <p class="text-slate-500 font-mono text-[9px] uppercase tracking-[0.2em] sm:tracking-[0.4em]">
                Autonomous Heuristic Simulator
              </p>
              <span class="text-[9px] text-cyan-500/50 font-bold uppercase tracking-widest animate-pulse">
                Live
              </span>
            </div>
          </div>

          <form
            id="filter-form"
            phx-change="filter_entities"
            class="grid grid-cols-1 sm:grid-cols-[minmax(180px,1fr)_180px] gap-3 w-full xl:max-w-xl"
          >
            <div class="relative">
              <input
                type="search"
                name="filters[query]"
                value={@query}
                placeholder="Filter entity ID"
                class="w-full h-11 rounded-xl border border-white/10 bg-black/30 px-4 text-sm text-slate-200 placeholder:text-slate-600 focus:border-cyan-500/60 focus:ring-cyan-500/20"
              />
            </div>
            <select
              name="filters[sort]"
              value={@sort}
              class="h-11 rounded-xl border border-white/10 bg-black/30 px-4 text-sm text-slate-200 focus:border-cyan-500/60 focus:ring-cyan-500/20"
            >
              <option value="energy_desc">Energy high</option>
              <option value="energy_asc">Energy low</option>
              <option value="aggression_desc">Aggression</option>
              <option value="curiosity_desc">Curiosity</option>
            </select>
          </form>

          <div class="flex items-center justify-center xl:justify-start gap-4 bg-slate-900/40 backdrop-blur-3xl border border-white/10 px-4 sm:px-6 py-3 rounded-2xl shadow-2xl">
            <div class="flex flex-col items-center border-r border-white/10 pr-6">
              <span class="text-[8px] uppercase tracking-[0.2em] text-slate-500 font-bold mb-0.5">
                Population
              </span>
              <span class="text-2xl font-black text-white leading-none tabular-nums">
                {@total_population}
              </span>
            </div>
            <div class="flex flex-col items-center border-r border-white/10 pr-6">
              <span class="text-[8px] uppercase tracking-[0.2em] text-slate-500 font-bold mb-0.5">
                Visible
              </span>
              <span class="text-2xl font-black text-white leading-none tabular-nums">
                {@visible_count}
              </span>
            </div>
            <div class="flex flex-col items-start gap-0.5 pl-2">
              <div class="flex items-center gap-2">
                <div class="w-1.5 h-1.5 rounded-full bg-cyan-500 animate-ping"></div>
                <span class="text-[9px] font-mono text-cyan-500 font-bold uppercase tracking-widest">
                  Uplink Active
                </span>
              </div>
              <span class={"text-[9px] font-mono font-bold uppercase tracking-widest #{epoch_class(@epoch)}"}>
                {epoch_label(@epoch)}
              </span>
            </div>
          </div>
        </div>
      </header>
      <!-- Full-Width Main Content -->
      <main class="flex-1 w-full px-4 py-6 md:px-8 md:py-8 overflow-visible lg:overflow-hidden flex flex-col lg:flex-row gap-6 lg:gap-8">
        <!-- Main Simulation Grid -->
        <div class="flex-1 overflow-auto custom-scrollbar-none">
          <div
            id="entities-grid"
            phx-update="stream"
            class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-4 md:gap-6"
          >
            <%= for {dom_id, entity} <- @streams.entities do %>
              <div
                id={dom_id}
                class="group relative bg-slate-900/20 backdrop-blur-xl border border-white/5 rounded-[2rem] p-1 transition-all duration-500 hover:scale-[1.01] hover:border-cyan-500/30"
              >
                <div class="bg-[#0b0d15]/95 rounded-[1.8rem] p-5 h-full flex flex-col border border-white/[0.02]">
                  <!-- Entity Header -->
                  <div class="flex justify-between items-start mb-5">
                    <div class="flex items-center gap-3">
                      <div class={"w-10 h-10 rounded-xl flex items-center justify-center border transition-all duration-500 shadow-inner #{if entity.energy > 50, do: "bg-cyan-500/10 border-cyan-500/20 text-cyan-400", else: "bg-orange-500/10 border-orange-500/20 text-orange-400"}"}>
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          viewBox="0 0 24 24"
                          fill="currentColor"
                          class="w-6 h-6"
                        >
                          <path d="M11.7 2.805a.75.75 0 0 1 .6 0A60.65 60.65 0 0 1 22.83 8.72a.75.75 0 0 1-.231 1.337 49.948 49.948 0 0 0-9.902 3.912l-.003.002-.34.18a.75.75 0 0 1-.707 0A50.88 50.88 0 0 0 7.5 12.173v-.224c0-.131.067-.248.172-.311a54.615 54.615 0 0 1 4.653-2.52.75.75 0 0 0-.65-1.352 56.123 56.123 0 0 0-4.78 2.589 2.258 2.258 0 0 0-1.095 1.944v.647a.75.75 0 0 1-.12.413l-1.95 3.177a3.75 3.75 0 0 0 3.185 5.706h11.27a3.75 3.75 0 0 0 3.185-5.706l-1.95-3.177a.75.75 0 0 1-.12-.413v-.647c0-1.226-.78-2.316-1.93-2.731a61.763 61.763 0 0 0-14.898-3.924.75.75 0 0 1-.23-1.337A62.152 62.152 0 0 1 11.7 2.805Z" />
                        </svg>
                      </div>
                      <div>
                        <h2 class="text-[8px] font-bold text-slate-500 uppercase tracking-widest mb-0.5">
                          ID
                        </h2>
                        <p class="text-white font-black text-base tracking-tight">
                          {String.slice(entity.id, 0, 8)}
                        </p>
                        <span class="text-[8px] font-mono font-bold text-purple-400/80 uppercase tracking-widest">
                          Gen {Map.get(entity, :generation, 1)}
                        </span>
                      </div>
                    </div>

                    <%= if @public_controls do %>
                      <button
                        phx-click="inject_energy"
                        phx-value-id={entity.id}
                        class="group/btn relative px-3 py-1.5 rounded-xl border border-cyan-500/30 bg-cyan-500/5 hover:bg-cyan-500/20 transition-all duration-300"
                      >
                        <span class="text-[9px] font-black text-cyan-400 uppercase tracking-widest">
                          + Energy
                        </span>
                      </button>
                    <% end %>
                  </div>
                  <!-- Traits Section -->
                  <div class="grid grid-cols-2 gap-3 mb-6">
                    <div class="bg-white/[0.02] rounded-xl p-3 border border-white/[0.03]">
                      <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold block mb-1">
                        AGGR
                      </span>
                      <div class="flex items-center gap-2">
                        <div class="flex-1 h-1 bg-black/40 rounded-full overflow-hidden">
                          <div
                            class="h-full bg-orange-500 transition-all duration-1000"
                            style={"width: #{entity.traits.aggression * 100}%"}
                          >
                          </div>
                        </div>
                        <span class="text-[9px] font-mono font-bold text-orange-400">
                          {Float.round(entity.traits.aggression, 1)}
                        </span>
                      </div>
                    </div>

                    <div class="bg-white/[0.02] rounded-xl p-3 border border-white/[0.03]">
                      <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold block mb-1">
                        CURI
                      </span>
                      <div class="flex items-center gap-2">
                        <div class="flex-1 h-1 bg-black/40 rounded-full overflow-hidden">
                          <div
                            class="h-full bg-cyan-500 transition-all duration-1000"
                            style={"width: #{entity.traits.curiosity * 100}%"}
                          >
                          </div>
                        </div>
                        <span class="text-[9px] font-mono font-bold text-cyan-400">
                          {Float.round(entity.traits.curiosity, 1)}
                        </span>
                      </div>
                    </div>
                  </div>
                  <!-- Energy Bar -->
                  <div class="mb-5">
                    <div class="flex justify-between items-center mb-1.5">
                      <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold">
                        Vitality
                      </span>
                      <span class={"text-[9px] font-mono font-bold #{if entity.energy > 50, do: "text-cyan-400", else: "text-orange-400"}"}>
                        {entity.energy}%
                      </span>
                    </div>
                    <div class="h-1.5 w-full bg-black/40 rounded-full overflow-hidden border border-white/5">
                      <div
                        class={"h-full transition-all duration-1000 #{if entity.energy > 50, do: "bg-cyan-500", else: "bg-orange-500"}"}
                        style={"width: #{entity.energy}%"}
                      >
                      </div>
                    </div>
                  </div>
                  <!-- Behavior Source (Minimized) -->
                  <div class="mb-5 flex-1 flex flex-col min-h-0">
                    <div class="flex items-center gap-2 mb-2">
                      <div class="w-1 h-1 rounded-full bg-cyan-500/50"></div>
                      <h3 class="text-[9px] uppercase tracking-widest text-cyan-400/80 font-black">
                        Heuristic
                      </h3>
                    </div>
                    <pre class="flex-1 text-[9px] leading-relaxed bg-[#05060a] border border-white/[0.05] p-3 rounded-xl text-cyan-100/40 font-mono overflow-auto max-h-[100px] custom-scrollbar">
    <%= entity.behavior_source %>
                    </pre>
                  </div>
                  <!-- Memory Stream -->
                  <div class="mt-auto">
                    <div class="space-y-1.5">
                      <%= for {type, sender} <- entity.memories do %>
                        <div class="flex items-center justify-between bg-white/[0.02] p-2 rounded-lg border border-white/5 transition-colors">
                          <div class="flex items-center gap-2">
                            <div class={"w-1.5 h-1.5 rounded-full #{case type do
                              :attack -> "bg-rose-500"
                              :greet -> "bg-emerald-500"
                              _ -> "bg-amber-400"
                            end}"}>
                            </div>
                            <span class="text-[9px] font-bold text-slate-400 uppercase">
                              {type}
                            </span>
                          </div>
                          <span class="text-[8px] font-mono text-slate-600">
                            → {String.slice(sender, 0, 4)}
                          </span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%= if @visible_count == 0 do %>
            <div class="min-h-56 flex items-center justify-center rounded-2xl border border-white/10 bg-slate-900/20 p-8 text-center">
              <div>
                <p class="text-xs font-black uppercase tracking-[0.3em] text-slate-500">
                  No entities match
                </p>
                <p class="mt-2 text-sm text-slate-600">
                  Clear the filter or wait for the next generation.
                </p>
              </div>
            </div>
          <% end %>
        </div>
        <!-- Sidebar for Logs and Stats -->
        <aside class="w-full lg:w-[400px] flex flex-col gap-8">
          <!-- Global Logs -->
          <div class="bg-slate-900/40 backdrop-blur-3xl border border-white/10 rounded-[2rem] p-6 flex flex-col h-[400px]">
            <div class="flex items-center justify-between mb-6">
              <h3 class="text-xs font-black text-white uppercase tracking-[0.3em]">Global Events</h3>
              <div class="px-2 py-0.5 rounded-md bg-cyan-500/10 border border-cyan-500/20">
                <span class="text-[8px] font-bold text-cyan-500 uppercase tracking-widest">
                  Real-time
                </span>
              </div>
            </div>

            <div class="flex-1 overflow-auto custom-scrollbar space-y-3 pr-2">
              <%= for event <- @global_events do %>
                <div class="bg-black/40 border border-white/5 p-3 rounded-xl flex flex-col gap-1">
                  <div class="flex items-center justify-between">
                    <span class={"text-[9px] font-black uppercase tracking-widest #{case event.type do
                      :death -> "text-rose-500"
                      :mutation -> "text-purple-400"
                      :birth -> "text-emerald-400"
                      :reproduction -> "text-cyan-400"
                      :epoch_change -> "text-amber-400"
                      _ -> "text-slate-400"
                    end}"}>
                      {event.type}
                    </span>
                    <span class="text-[8px] font-mono text-slate-600">
                      {Calendar.strftime(event.timestamp, "%H:%M:%S")}
                    </span>
                  </div>
                  <p class="text-[10px] text-slate-400 font-medium">
                    {if Map.has_key?(event, :entity_id),
                      do: "Entity " <> String.slice(event.entity_id, 0, 8),
                      else: event[:detail] || "System action"}
                    {if Map.has_key?(event, :parent_id),
                      do: "from parent " <> String.slice(event.parent_id, 0, 8),
                      else: ""}
                    {if event[:cause], do: "· #{event.cause}", else: ""}
                  </p>
                </div>
              <% end %>
              <%= if Enum.empty?(@global_events) do %>
                <div class="h-full flex items-center justify-center opacity-20">
                  <p class="text-[9px] font-bold text-slate-500 uppercase tracking-[0.2em]">
                    Monitoring Initializing...
                  </p>
                </div>
              <% end %>
            </div>
          </div>
          <!-- Evolution Stats -->
          <div class="bg-slate-900/40 backdrop-blur-3xl border border-white/10 rounded-[2rem] p-6">
            <h3 class="text-xs font-black text-white uppercase tracking-[0.3em] mb-6">
              Evolution Trends
            </h3>

            <div class="space-y-6">
              <%= if !Enum.empty?(@stats) do %>
                <% current = List.first(@stats) %>
                <div class="grid grid-cols-2 gap-4">
                  <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                    <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                      Avg Aggression
                    </span>
                    <span class="text-xl font-black text-orange-500 tabular-nums">
                      {Float.round(current.avg_aggression, 2)}
                    </span>
                  </div>
                  <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                    <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                      Avg Curiosity
                    </span>
                    <span class="text-xl font-black text-cyan-500 tabular-nums">
                      {Float.round(current.avg_curiosity, 2)}
                    </span>
                  </div>
                </div>
                <!-- Simple SVG Sparkline visualization -->
                <div class="h-32 w-full bg-black/40 rounded-2xl border border-white/5 p-4 relative overflow-hidden">
                  <svg class="w-full h-full" viewBox="0 0 100 100" preserveAspectRatio="none">
                    <!-- Aggression line -->
                    <polyline
                      fill="none"
                      stroke="#f97316"
                      stroke-width="2"
                      stroke-linecap="round"
                      points={
                        if length(@stats) > 1 do
                          @stats
                          |> Enum.reverse()
                          |> Enum.with_index()
                          |> Enum.map_join(" ", fn {s, i} ->
                            "#{i * (100 / (length(@stats) - 1))},#{100 - s.avg_aggression * 100}"
                          end)
                        else
                          "0,#{100 - (List.first(@stats) || %{avg_aggression: 0}).avg_aggression * 100} 100,#{100 - (List.first(@stats) || %{avg_aggression: 0}).avg_aggression * 100}"
                        end
                      }
                    />
                    <!-- Curiosity line -->
                    <polyline
                      fill="none"
                      stroke="#06b6d4"
                      stroke-width="2"
                      stroke-linecap="round"
                      points={
                        if length(@stats) > 1 do
                          @stats
                          |> Enum.reverse()
                          |> Enum.with_index()
                          |> Enum.map_join(" ", fn {s, i} ->
                            "#{i * (100 / (length(@stats) - 1))},#{100 - s.avg_curiosity * 100}"
                          end)
                        else
                          "0,#{100 - (List.first(@stats) || %{avg_curiosity: 0}).avg_curiosity * 100} 100,#{100 - (List.first(@stats) || %{avg_curiosity: 0}).avg_curiosity * 100}"
                        end
                      }
                    />
                  </svg>
                  <div class="absolute bottom-2 left-4 flex gap-4">
                    <div class="flex items-center gap-1.5">
                      <div class="w-2 h-2 rounded-full bg-orange-500"></div>
                      <span class="text-[7px] font-bold text-slate-500 uppercase">Aggr</span>
                    </div>
                    <div class="flex items-center gap-1.5">
                      <div class="w-2 h-2 rounded-full bg-cyan-500"></div>
                      <span class="text-[7px] font-bold text-slate-500 uppercase">Curi</span>
                    </div>
                  </div>
                </div>
              <% else %>
                <div class="h-32 flex items-center justify-center opacity-20">
                  <p class="text-[9px] font-bold text-slate-500 uppercase tracking-[0.2em]">
                    Calculating Traits...
                  </p>
                </div>
              <% end %>
            </div>
          </div>
          <!-- Top Connections -->
          <div class="bg-slate-900/40 backdrop-blur-3xl border border-white/10 rounded-[2rem] p-6">
            <h3 class="text-xs font-black text-white uppercase tracking-[0.3em] mb-6">
              Social Graph
            </h3>
            <div class="space-y-4">
              <%= for {pair, count} <- @top_interactions do %>
                <div class="flex items-center justify-between bg-black/40 p-3 rounded-2xl border border-white/5">
                  <div class="flex items-center gap-2">
                    <span class="text-[9px] font-mono font-bold text-cyan-400">
                      {String.slice(Enum.at(pair, 0), 0, 4)}
                    </span>
                    <div class="w-3 h-[1px] bg-slate-700"></div>
                    <span class="text-[9px] font-mono font-bold text-cyan-400">
                      {String.slice(Enum.at(pair, 1), 0, 4)}
                    </span>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <span class="text-[10px] font-black text-slate-300">{count}</span>
                    <span class="text-[7px] font-bold text-slate-500 uppercase">msgr</span>
                  </div>
                </div>
              <% end %>
              <%= if Enum.empty?(@top_interactions) do %>
                <div class="py-4 text-center opacity-20">
                  <p class="text-[9px] font-bold text-slate-500 uppercase tracking-[0.2em]">
                    Silent World
                  </p>
                </div>
              <% end %>
            </div>
          </div>
          <!-- Hall of Fame -->
          <div class="bg-slate-900/40 backdrop-blur-3xl border border-white/10 rounded-[2rem] p-6">
            <h3 class="text-xs font-black text-white uppercase tracking-[0.3em] mb-6">
              Hall of Fame
            </h3>
            <div class="grid grid-cols-2 gap-3 mb-4">
              <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                  Births
                </span>
                <span class="text-lg font-black text-emerald-400 tabular-nums">
                  {@all_time.births}
                </span>
              </div>
              <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                  Deaths
                </span>
                <span class="text-lg font-black text-rose-400 tabular-nums">
                  {@all_time.deaths}
                </span>
                <span class="text-[8px] font-mono text-slate-600 block">
                  {Map.get(@all_time.deaths_by_cause, :killed, 0)} killed
                </span>
              </div>
              <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                  Mutations
                </span>
                <span class="text-lg font-black text-purple-400 tabular-nums">
                  {@all_time.mutations}
                </span>
              </div>
              <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                  Max Gen
                </span>
                <span class="text-lg font-black text-cyan-400 tabular-nums">
                  {@all_time.max_generation}
                </span>
              </div>
            </div>
            <%= if @all_time.oldest do %>
              <div class="bg-black/40 p-3 rounded-2xl border border-white/5 flex items-center justify-between">
                <div>
                  <span class="text-[8px] text-slate-500 uppercase font-black block mb-0.5">
                    Oldest Mind Ever
                  </span>
                  <span class="text-[10px] font-mono font-bold text-amber-400">
                    {String.slice(@all_time.oldest.id || "?", 0, 8)}
                  </span>
                </div>
                <span class="text-sm font-black text-amber-400 tabular-nums">
                  {format_age(@all_time.oldest.age)}
                </span>
              </div>
            <% end %>
          </div>
        </aside>
      </main>

      <style>
        .custom-scrollbar::-webkit-scrollbar {
          width: 2px;
        }
        .custom-scrollbar::-webkit-scrollbar-track {
          background: transparent;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb {
          background: rgba(255, 255, 255, 0.05);
          border-radius: 10px;
        }
        .custom-scrollbar-none::-webkit-scrollbar {
          display: none;
        }
      </style>
    </div>
    """
  end
end
