defmodule EvolvingMindsWeb.WorldLive do
  use EvolvingMindsWeb, :live_view

  alias EvolvingMinds.World
  alias EvolvingMindsWeb.WorldPublisher

  # Public controls are rate limited per connected client with sliding
  # windows: @inject_limit injections per @inject_window_ms, and
  # @spawn_limit spawned minds per @spawn_window_ms.
  @inject_limit 5
  @inject_window_ms 10_000
  @spawn_limit 2
  @spawn_window_ms 60_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: WorldPublisher.subscribe()

    socket =
      socket
      |> assign(:query, "")
      |> assign(:sort, "energy_desc")
      |> assign(:prev_visible, [])
      |> assign(:inject_history, [])
      |> assign(:spawn_history, [])
      |> assign(:selected_id, nil)
      |> assign(:selected, nil)
      |> assign(:show_about, false)
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
  def handle_event("spawn_mind", _params, socket) do
    now = System.monotonic_time(:millisecond)
    recent = Enum.filter(socket.assigns.spawn_history, &(now - &1 < @spawn_window_ms))

    cond do
      not socket.assigns.public_controls ->
        {:noreply, socket}

      socket.assigns.total_population >= EvolvingMinds.EvolutionEngine.max_population() ->
        {:noreply, put_flash(socket, :error, "The world is full — wait for natural selection.")}

      length(recent) >= @spawn_limit ->
        {:noreply,
         socket
         |> assign(:spawn_history, recent)
         |> put_flash(:error, "The world needs a moment between new minds.")}

      true ->
        {:ok, pid} = World.spawn_entity()
        id = World.id_of(pid)
        name = mind_name(id)

        EvolvingMinds.GlobalEvents.report_event(%{
          type: :birth,
          entity_id: id,
          name: name,
          cause: :visitor
        })

        socket =
          socket
          |> assign(:spawn_history, [now | recent])
          |> put_flash(:info, "A new mind awakens: #{name}")
          |> apply_snapshot(WorldPublisher.snapshot())

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_entity", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:selected_id, id) |> assign(:selected, build_selected(id))}
  end

  @impl true
  def handle_event("close_entity", _params, socket) do
    {:noreply, socket |> assign(:selected_id, nil) |> assign(:selected, nil)}
  end

  @impl true
  def handle_event("toggle_about", _params, socket) do
    {:noreply, assign(socket, :show_about, not socket.assigns.show_about)}
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
    |> assign(:selected, build_selected(socket.assigns.selected_id))
    |> refresh_stream(entities, opts)
  end

  defp mind_name(id) do
    case EvolvingMinds.StateStore.get_state(id) do
      %{name: name} -> name
      _ -> String.slice(id, 0, 8)
    end
  end

  # The detail panel reads fresh state directly; a nil result for a
  # still-selected id means the mind died while being watched.
  defp build_selected(nil), do: nil

  defp build_selected(id) do
    case EvolvingMinds.StateStore.get_state(id) do
      nil ->
        nil

      state ->
        state
        |> Map.delete(:behavior_fn)
        |> Map.put(:memories, EvolvingMinds.Memory.get_memories(id))
        |> Map.put(:age, System.system_time(:second) - state.born_at)
        |> Map.put(:ancestors, id |> EvolvingMinds.Ancestry.lineage() |> Enum.drop(1))
    end
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

  defp epoch_class(:abundance), do: "text-emerald-400"
  defp epoch_class(:famine), do: "text-rose-400"
  defp epoch_class(_), do: "text-slate-500"

  defp tribe_class(:solari), do: "text-amber-400"
  defp tribe_class(:umbra), do: "text-violet-400"
  defp tribe_class(_), do: "text-slate-500"

  defp tribe_counts(entities) do
    solari = Enum.count(entities, &(Map.get(&1, :tribe) == :solari))
    umbra = Enum.count(entities, &(Map.get(&1, :tribe) == :umbra))
    {solari, umbra}
  end

  defp tribe_share(part, total) when total > 0, do: round(part / total * 100)
  defp tribe_share(_part, _total), do: 50

  defp epoch_label(:abundance), do: "Epoch: Abundance"
  defp epoch_label(:famine), do: "Epoch: Famine"
  defp epoch_label(_), do: "Epoch: Normal"

  defp format_age(seconds) when seconds >= 3600,
    do: "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"

  defp format_age(seconds) when seconds >= 60, do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  defp format_age(seconds), do: "#{seconds}s"

  defp population_points(stats) when length(stats) > 1 do
    max_pop = stats |> Enum.map(& &1.population) |> Enum.max() |> max(1)
    n = length(stats)

    stats
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {s, i} ->
      "#{i * (100 / (n - 1))},#{100 - s.population / max_pop * 90}"
    end)
  end

  defp population_points(_), do: nil

  # Distribution of living minds across the 12 most recent generations,
  # as {generation, count, percent-of-max} for bar heights.
  defp generation_histogram(entities) do
    counts = Enum.frequencies_by(entities, &Map.get(&1, :generation, 1))
    shown = counts |> Map.keys() |> Enum.sort() |> Enum.take(-12)
    max_count = shown |> Enum.map(&counts[&1]) |> Enum.max(fn -> 1 end)

    Enum.map(shown, fn gen -> {gen, counts[gen], round(counts[gen] / max_count * 100)} end)
  end

  # 10-bucket distribution of a trait across the living population,
  # as {count, percent-of-max} pairs for bar heights.
  defp histogram(entities, trait) do
    counts =
      Enum.reduce(entities, List.duplicate(0, 10), fn entity, acc ->
        bucket = min(9, trunc(Map.fetch!(entity.traits, trait) * 10))
        List.update_at(acc, bucket, &(&1 + 1))
      end)

    max_count = max(Enum.max(counts), 1)
    Enum.map(counts, &{&1, round(&1 / max_count * 100)})
  end

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
            <div class="flex flex-col gap-1 border-l border-white/10 pl-4 min-w-[110px]">
              <% {solari, umbra} = tribe_counts(@entities) %>
              <div class="flex justify-between text-[8px] font-black uppercase tracking-widest">
                <span class="text-amber-400">Solari {solari}</span>
                <span class="text-violet-400">{umbra} Umbra</span>
              </div>
              <div class="h-1.5 w-full rounded-full overflow-hidden bg-black/40 flex">
                <div
                  class="h-full bg-amber-500 transition-all duration-1000"
                  style={"width: #{tribe_share(solari, solari + umbra)}%"}
                >
                </div>
                <div class="h-full bg-violet-500 flex-1 transition-all duration-1000"></div>
              </div>
            </div>
            <%= if @public_controls do %>
              <button
                phx-click="spawn_mind"
                class="ml-2 px-3 py-2 rounded-xl border border-emerald-500/30 bg-emerald-500/5 hover:bg-emerald-500/20 transition-all duration-300"
              >
                <span class="text-[9px] font-black text-emerald-400 uppercase tracking-widest">
                  Spawn a Mind
                </span>
              </button>
            <% end %>
            <.link
              navigate={~p"/tree"}
              class="ml-2 px-3 py-2 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 transition-all duration-300"
            >
              <span class="text-[9px] font-black text-slate-400 uppercase tracking-widest">
                Dynasties
              </span>
            </.link>
            <button
              phx-click="toggle_about"
              class="ml-2 px-3 py-2 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 transition-all duration-300"
            >
              <span class="text-[9px] font-black text-slate-400 uppercase tracking-widest">
                What is this?
              </span>
            </button>
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
                        <p class="text-white font-black text-base tracking-tight">
                          {Map.get(entity, :name, "Unnamed")}
                        </p>
                        <span class="text-[8px] font-mono text-slate-600">
                          {String.slice(entity.id, 0, 8)}
                        </span>
                        <span class="text-[8px] font-mono font-bold uppercase tracking-widest block">
                          <span class="text-purple-400/80">Gen {Map.get(entity, :generation, 1)}</span>
                          <span class={tribe_class(Map.get(entity, :tribe))}>
                            · {Map.get(entity, :tribe, :unaligned)}
                          </span>
                        </span>
                      </div>
                    </div>

                    <div class="flex flex-col items-end gap-1.5">
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
                      <button
                        phx-click="select_entity"
                        phx-value-id={entity.id}
                        class="px-3 py-1.5 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 transition-all duration-300"
                      >
                        <span class="text-[9px] font-black text-slate-400 uppercase tracking-widest">
                          Details
                        </span>
                      </button>
                    </div>
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
                    {event_sentence(event)}
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
              <!-- Population over time -->
              <div>
                <div class="flex justify-between items-center mb-1.5">
                  <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold">
                    Population
                  </span>
                  <span class="text-[9px] font-mono font-bold text-emerald-400">
                    {@total_population}
                  </span>
                </div>
                <div class="h-16 w-full bg-black/40 rounded-2xl border border-white/5 p-3">
                  <%= if points = population_points(@stats) do %>
                    <svg class="w-full h-full" viewBox="0 0 100 100" preserveAspectRatio="none">
                      <polyline
                        fill="none"
                        stroke="#34d399"
                        stroke-width="3"
                        stroke-linecap="round"
                        points={points}
                      />
                    </svg>
                  <% else %>
                    <div class="h-full flex items-center justify-center opacity-20">
                      <span class="text-[8px] font-bold text-slate-500 uppercase tracking-widest">
                        Collecting...
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
              <!-- Trait distribution histograms -->
              <div>
                <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold block mb-1.5">
                  Trait Distribution
                </span>
                <div class="grid grid-cols-2 gap-3">
                  <div class="bg-black/40 rounded-2xl border border-white/5 p-3">
                    <div class="flex items-end gap-0.5 h-12">
                      <%= for {count, pct} <- histogram(@entities, :aggression) do %>
                        <div
                          class="flex-1 bg-orange-500/70 rounded-t-sm"
                          style={"height: #{max(pct, 4)}%"}
                          title={"#{count}"}
                        >
                        </div>
                      <% end %>
                    </div>
                    <span class="text-[7px] font-bold text-orange-400/80 uppercase block mt-1.5">
                      Aggression 0 → 1
                    </span>
                  </div>
                  <div class="bg-black/40 rounded-2xl border border-white/5 p-3">
                    <div class="flex items-end gap-0.5 h-12">
                      <%= for {count, pct} <- histogram(@entities, :curiosity) do %>
                        <div
                          class="flex-1 bg-cyan-500/70 rounded-t-sm"
                          style={"height: #{max(pct, 4)}%"}
                          title={"#{count}"}
                        >
                        </div>
                      <% end %>
                    </div>
                    <span class="text-[7px] font-bold text-cyan-400/80 uppercase block mt-1.5">
                      Curiosity 0 → 1
                    </span>
                  </div>
                </div>
              </div>
              <!-- Generation distribution -->
              <div>
                <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold block mb-1.5">
                  Generations Alive
                </span>
                <div class="bg-black/40 rounded-2xl border border-white/5 p-3">
                  <div class="flex items-end gap-1 h-12">
                    <%= for {gen, count, pct} <- generation_histogram(@entities) do %>
                      <div class="flex-1 flex flex-col items-center gap-0.5" title={"#{count} minds"}>
                        <div class="w-full flex items-end h-9">
                          <div
                            class="w-full bg-purple-500/70 rounded-t-sm"
                            style={"height: #{max(pct, 6)}%"}
                          >
                          </div>
                        </div>
                        <span class="text-[7px] font-mono text-purple-400/70">{gen}</span>
                      </div>
                    <% end %>
                    <%= if @entities == [] do %>
                      <span class="text-[8px] font-bold text-slate-600 uppercase tracking-widest mx-auto self-center">
                        Empty world
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>
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
            <div class="space-y-2">
              <%= if @all_time.oldest do %>
                <div class="bg-black/40 p-3 rounded-2xl border border-white/5 flex items-center justify-between">
                  <div>
                    <span class="text-[8px] text-slate-500 uppercase font-black block mb-0.5">
                      Oldest Mind Ever
                    </span>
                    <span class="text-[10px] font-bold text-amber-400">
                      {@all_time.oldest[:name] || String.slice(@all_time.oldest.id || "?", 0, 8)}
                    </span>
                  </div>
                  <span class="text-sm font-black text-amber-400 tabular-nums">
                    {format_age(@all_time.oldest.age)}
                  </span>
                </div>
              <% end %>
              <%= if @all_time[:most_feared] do %>
                <div class="bg-black/40 p-3 rounded-2xl border border-white/5 flex items-center justify-between">
                  <div>
                    <span class="text-[8px] text-slate-500 uppercase font-black block mb-0.5">
                      Most Feared
                    </span>
                    <span class="text-[10px] font-bold text-rose-400">
                      {@all_time.most_feared[:name] ||
                        String.slice(@all_time.most_feared.id || "?", 0, 8)}
                    </span>
                  </div>
                  <span class="text-sm font-black text-rose-400 tabular-nums">
                    {@all_time.most_feared.kills} kills
                  </span>
                </div>
              <% end %>
              <%= if @all_time[:most_prolific] do %>
                <div class="bg-black/40 p-3 rounded-2xl border border-white/5 flex items-center justify-between">
                  <div>
                    <span class="text-[8px] text-slate-500 uppercase font-black block mb-0.5">
                      Most Prolific
                    </span>
                    <span class="text-[10px] font-bold text-emerald-400">
                      {@all_time.most_prolific[:name] ||
                        String.slice(@all_time.most_prolific.id || "?", 0, 8)}
                    </span>
                  </div>
                  <span class="text-sm font-black text-emerald-400 tabular-nums">
                    {@all_time.most_prolific.children} heirs
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </aside>
      </main>

      <%= if @show_about do %>
        <div class="fixed inset-0 z-[70] flex items-center justify-center p-4">
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" phx-click="toggle_about"></div>
          <div class="relative w-full max-w-2xl max-h-[85vh] overflow-y-auto custom-scrollbar bg-[#0b0d15] border border-white/10 rounded-[2rem] p-8">
            <div class="flex items-start justify-between mb-6">
              <h2 class="text-xl font-black text-white">
                What is
                <span class="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-indigo-500">
                  Evolving Minds
                </span>
                ?
              </h2>
              <button
                phx-click="toggle_about"
                class="px-3 py-1.5 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 text-slate-400 text-xs font-black"
                aria-label="close"
              >
                ✕
              </button>
            </div>

            <div class="space-y-4 text-sm text-slate-400 leading-relaxed">
              <p>
                You are watching a
                <strong class="text-slate-200">live artificial-life simulation</strong>
                running on the Erlang virtual machine. Every card is an autonomous process — a
                digital mind with two inherited traits,
                <span class="text-orange-400">aggression</span>
                and <span class="text-cyan-400">curiosity</span>, that decide how it treats others.
              </p>
              <p>
                Minds act on their own timers: they greet or attack whoever they meet, and every
                interaction settles in <strong class="text-slate-200">energy</strong>. Robbing a
                fleeing pacifist pays; picking a fight with another warrior bleeds both sides;
                sharing knowledge between curious minds compounds for everyone. Run out of energy
                and you die — of exhaustion, or by someone's hand.
              </p>
              <p>
                The fittest minds reproduce: parents are drawn proportionally to their energy, and
                children inherit slightly mutated traits. Add shifting epochs of
                <span class="text-emerald-400">abundance</span>
                and <span class="text-rose-400">famine</span>, and what you get is real,
                frequency-dependent natural selection — watch the trait averages drift in the
                sidebar as strategies win and lose.
              </p>
              <p>
                The world is <strong class="text-slate-200">persistent</strong>: it survives
                restarts and deploys, and the Hall of Fame remembers every generation. Click
                <em>Details</em>
                on any card to read a mind's memories and the heuristic it is
                currently running.
              </p>
              <p class="text-[11px] text-slate-600 pt-2 border-t border-white/5">
                Built with Elixir, Phoenix LiveView, and the BEAM — every mind is a supervised
                GenServer process. No JavaScript frameworks, no runtime code evaluation.
              </p>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @selected_id do %>
        <div class="fixed inset-0 z-[60] flex justify-end">
          <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_entity"></div>
          <aside
            id="entity-detail"
            class="relative w-full max-w-md h-full bg-[#0b0d15] border-l border-white/10 p-6 overflow-y-auto custom-scrollbar"
          >
            <div class="flex items-start justify-between mb-6">
              <div>
                <h2 class="text-[9px] font-bold text-slate-500 uppercase tracking-[0.3em] mb-1">
                  Mind Dossier
                </h2>
                <p class="text-white font-black text-xl tracking-tight">
                  {(@selected && Map.get(@selected, :name)) || String.slice(@selected_id, 0, 16)}
                </p>
                <p class="text-[9px] font-mono text-slate-600">
                  {@selected_id}
                  <%= if @selected && Map.get(@selected, :tribe) do %>
                    <span class={"font-black uppercase #{tribe_class(@selected.tribe)}"}>
                      · {@selected.tribe}
                    </span>
                  <% end %>
                </p>
              </div>
              <button
                phx-click="close_entity"
                class="px-3 py-1.5 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 text-slate-400 text-xs font-black"
                aria-label="close"
              >
                ✕
              </button>
            </div>

            <%= if @selected do %>
              <div class="grid grid-cols-2 gap-3 mb-6">
                <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                  <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">Gen</span>
                  <span class="text-lg font-black text-purple-400 tabular-nums">
                    {@selected.generation}
                  </span>
                </div>
                <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                  <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">Age</span>
                  <span class="text-lg font-black text-amber-400 tabular-nums">
                    {format_age(@selected.age)}
                  </span>
                </div>
                <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                  <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                    Energy
                  </span>
                  <span class="text-lg font-black text-cyan-400 tabular-nums">
                    {@selected.energy}%
                  </span>
                </div>
                <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                  <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                    Kills
                  </span>
                  <span class="text-lg font-black text-rose-400 tabular-nums">
                    {Map.get(@selected, :kills, 0)}
                  </span>
                </div>
              </div>

              <div class="bg-black/40 p-3 rounded-2xl border border-white/5 mb-6">
                <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
                  Lineage
                </span>
                <%= if @selected.ancestors == [] do %>
                  <span class="text-[11px] font-mono text-slate-300">
                    First of its line — primordial spawn
                  </span>
                <% else %>
                  <div class="flex flex-wrap items-center gap-1.5 text-[11px] font-mono">
                    <span class="text-slate-200 font-bold">{Map.get(@selected, :name, "?")}</span>
                    <%= for ancestor <- @selected.ancestors do %>
                      <span class="text-slate-600">←</span>
                      <span class={
                        if ancestor.died_at, do: "text-slate-500", else: "text-emerald-400"
                      }>
                        {ancestor.name || String.slice(ancestor.id, 0, 8)}
                      </span>
                    <% end %>
                  </div>
                <% end %>
                <.link
                  navigate={~p"/tree"}
                  class="text-[9px] font-black text-cyan-500/70 uppercase tracking-widest hover:text-cyan-400 inline-block mt-2"
                >
                  View full genealogy →
                </.link>
              </div>

              <div class="mb-6">
                <h3 class="text-[9px] uppercase tracking-widest text-cyan-400/80 font-black mb-2">
                  Traits
                </h3>
                <div class="space-y-2">
                  <div class="flex items-center gap-3">
                    <span class="text-[9px] font-bold text-slate-500 uppercase w-20">Aggression</span>
                    <div class="flex-1 h-1.5 bg-black/40 rounded-full overflow-hidden">
                      <div
                        class="h-full bg-orange-500"
                        style={"width: #{@selected.traits.aggression * 100}%"}
                      >
                      </div>
                    </div>
                    <span class="text-[10px] font-mono font-bold text-orange-400">
                      {Float.round(@selected.traits.aggression, 2)}
                    </span>
                  </div>
                  <div class="flex items-center gap-3">
                    <span class="text-[9px] font-bold text-slate-500 uppercase w-20">Curiosity</span>
                    <div class="flex-1 h-1.5 bg-black/40 rounded-full overflow-hidden">
                      <div
                        class="h-full bg-cyan-500"
                        style={"width: #{@selected.traits.curiosity * 100}%"}
                      >
                      </div>
                    </div>
                    <span class="text-[10px] font-mono font-bold text-cyan-400">
                      {Float.round(@selected.traits.curiosity, 2)}
                    </span>
                  </div>
                </div>
              </div>

              <div class="mb-6">
                <h3 class="text-[9px] uppercase tracking-widest text-cyan-400/80 font-black mb-2">
                  Active Heuristic
                </h3>
                <pre class="text-[10px] leading-relaxed bg-[#05060a] border border-white/[0.05] p-3 rounded-xl text-cyan-100/50 font-mono overflow-x-auto custom-scrollbar">{@selected.behavior_source}</pre>
              </div>

              <div>
                <h3 class="text-[9px] uppercase tracking-widest text-cyan-400/80 font-black mb-2">
                  Memory Stream ({length(@selected.memories)})
                </h3>
                <div class="space-y-1.5">
                  <%= for {type, sender} <- Enum.take(@selected.memories, 30) do %>
                    <div class="flex items-center justify-between bg-white/[0.02] p-2 rounded-lg border border-white/5">
                      <span class="text-[9px] font-bold text-slate-400 uppercase">{type}</span>
                      <span class="text-[8px] font-mono text-slate-600">
                        ← {String.slice(sender, 0, 8)}
                      </span>
                    </div>
                  <% end %>
                  <%= if Enum.empty?(@selected.memories) do %>
                    <p class="text-[9px] text-slate-600 uppercase tracking-widest py-2">
                      No memories yet
                    </p>
                  <% end %>
                </div>
              </div>
            <% else %>
              <div class="bg-rose-500/10 border border-rose-500/30 rounded-2xl p-6 text-center">
                <p class="text-xs font-black uppercase tracking-[0.3em] text-rose-400 mb-2">
                  This mind has died
                </p>
                <p class="text-[11px] text-slate-500">
                  Its state and memories have been purged from the world.
                </p>
              </div>
            <% end %>
          </aside>
        </div>
      <% end %>

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
