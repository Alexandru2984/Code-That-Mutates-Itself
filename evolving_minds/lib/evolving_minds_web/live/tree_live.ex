defmodule EvolvingMindsWeb.TreeLive do
  @moduledoc """
  The genealogy of the world: every dynasty rendered as a nested tree
  from the Ancestry book. Loaded on mount and on demand — not on every
  world tick, since the whole forest re-renders.
  """

  use EvolvingMindsWeb, :live_view

  alias EvolvingMinds.Ancestry

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Genealogy") |> load(),
     layout: {EvolvingMindsWeb.Layouts, :screen}}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load(socket)}
  end

  defp load(socket) do
    records = Ancestry.all()
    ids = MapSet.new(records, & &1.id)

    children_map =
      records
      |> Enum.filter(& &1.parent_id)
      |> Enum.group_by(& &1.parent_id)

    # Roots: primordial minds, plus orphans whose ancestors were pruned.
    roots =
      records
      |> Enum.filter(fn record ->
        is_nil(record.parent_id) or not MapSet.member?(ids, record.parent_id)
      end)
      |> Enum.sort_by(& &1.born_at)

    socket
    |> assign(:roots, roots)
    |> assign(:children_map, children_map)
    |> assign(:total, length(records))
    |> assign(:alive, Enum.count(records, &is_nil(&1.died_at)))
  end

  defp name_class(%{died_at: died}) when died != nil, do: "text-slate-500"
  defp name_class(%{tribe: :solari}), do: "text-amber-400"
  defp name_class(%{tribe: :umbra}), do: "text-violet-400"
  defp name_class(_record), do: "text-white"

  defp dynasty(assigns) do
    ~H"""
    <div class={if @depth > 0, do: "ml-3 pl-3 border-l border-white/5", else: ""}>
      <div class="flex items-center gap-2 py-1">
        <div class={"w-1.5 h-1.5 rounded-full shrink-0 #{if @record.died_at, do: "bg-slate-700", else: "bg-emerald-500"}"}>
        </div>
        <span class={"text-xs font-bold #{name_class(@record)}"}>
          {@record.name || String.slice(@record.id, 0, 8)}
        </span>
        <span class="text-[8px] font-mono text-purple-400/70 uppercase">
          gen {@record.generation}
        </span>
        <%= if @record.died_at do %>
          <span class="text-[8px] font-mono text-rose-500/70">† {@record.cause}</span>
        <% end %>
      </div>
      <%= for child <- Map.get(@children_map, @record.id, []) |> Enum.sort_by(& &1.born_at) do %>
        <.dynasty record={child} children_map={@children_map} depth={@depth + 1} />
      <% end %>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen w-full bg-[#050608] text-slate-300 font-sans p-6 md:p-10">
      <div class="max-w-3xl mx-auto">
        <header class="mb-8 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-black text-white">
              The
              <span class="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-indigo-500">
                Dynasties
              </span>
            </h1>
            <p class="text-[10px] text-slate-500 font-mono uppercase tracking-[0.3em] mt-1">
              {@total} minds recorded · {@alive} alive
            </p>
          </div>
          <div class="flex gap-3">
            <button
              phx-click="refresh"
              class="px-4 py-2 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 text-[10px] font-black text-slate-400 uppercase tracking-widest"
            >
              Refresh
            </button>
            <a
              href="/"
              class="px-4 py-2 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 text-[10px] font-black text-slate-400 uppercase tracking-widest"
            >
              ← World
            </a>
          </div>
        </header>

        <div class="bg-slate-900/40 border border-white/10 rounded-2xl p-6 space-y-4">
          <%= for root <- @roots do %>
            <.dynasty record={root} children_map={@children_map} depth={0} />
          <% end %>
          <%= if @roots == [] do %>
            <p class="text-[10px] font-bold text-slate-500 uppercase tracking-[0.2em] text-center py-6">
              The book is empty — the world is young.
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
