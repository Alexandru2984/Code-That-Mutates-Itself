defmodule EvolvingMindsWeb.WorldLive do
  use EvolvingMindsWeb, :live_view

  alias EvolvingMinds.World

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(500, :tick)
    {:ok, assign(socket, entities: fetch_entities()), layout: {EvolvingMindsWeb.Layouts, :screen}}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, entities: fetch_entities())}
  end

  defp fetch_entities do
    World.get_all_entities()
    |> Enum.map(fn id ->
      case Registry.lookup(EvolvingMinds.EntityRegistry, id) do
        [{pid, _}] ->
          try do
            # Using sys.get_state for experimental debugging purposes
            :sys.get_state(pid, 100)
          rescue
            _ -> nil
          end
        [] -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen w-full bg-[#050608] text-slate-300 font-sans selection:bg-cyan-500/30 flex flex-col">
      <!-- Fixed Header for better UX on long lists -->
      <header class="sticky top-0 z-50 w-full bg-[#050608]/80 backdrop-blur-xl border-b border-white/5 px-4 py-4 md:px-8">
        <div class="max-w-[2400px] mx-auto flex flex-col md:flex-row items-center justify-between gap-6">
          <div class="relative group">
            <div class="absolute -inset-2 bg-gradient-to-r from-cyan-600 to-blue-700 rounded-xl blur-lg opacity-20 group-hover:opacity-40 transition duration-1000"></div>
            <h1 class="relative text-3xl md:text-4xl font-black tracking-tighter text-white">
              Evolving <span class="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 via-blue-500 to-indigo-600">Minds</span>
            </h1>
            <div class="flex items-center gap-3 mt-1">
              <p class="text-slate-500 font-mono text-[9px] uppercase tracking-[0.4em]">Autonomous Heuristic Simulator</p>
              <span class="text-[9px] text-cyan-500/50 font-bold uppercase tracking-widest animate-pulse">Live</span>
            </div>
          </div>
          
          <div class="flex items-center gap-4 bg-slate-900/40 backdrop-blur-3xl border border-white/10 px-6 py-3 rounded-2xl shadow-2xl">
            <div class="flex flex-col items-center border-r border-white/10 pr-6">
              <span class="text-[8px] uppercase tracking-[0.2em] text-slate-500 font-bold mb-0.5">Population</span>
              <span class="text-2xl font-black text-white leading-none tabular-nums"><%= length(@entities) %></span>
            </div>
            <div class="flex flex-col items-start gap-0.5 pl-2">
              <div class="flex items-center gap-2">
                <div class="w-1.5 h-1.5 rounded-full bg-cyan-500 animate-ping"></div>
                <span class="text-[9px] font-mono text-cyan-500 font-bold uppercase tracking-widest">Uplink Active</span>
              </div>
              <span class="text-[8px] text-slate-500 font-medium tracking-tight">BEAM Cluster Online</span>
            </div>
          </div>
        </div>
      </header>

      <!-- Full-Width Main Content -->
      <main class="flex-1 w-full px-4 py-8 md:px-8">
        <div class="max-w-[2400px] mx-auto">
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 3xl:grid-cols-6 4xl:grid-cols-8 gap-6">
            <%= for entity <- @entities do %>
              <div class="group relative bg-slate-900/20 backdrop-blur-xl border border-white/5 rounded-[2rem] p-1 transition-all duration-500 hover:scale-[1.01] hover:border-cyan-500/30">
                <div class="bg-[#0b0d15]/95 rounded-[1.8rem] p-5 h-full flex flex-col border border-white/[0.02]">
                  <!-- Entity Header -->
                  <div class="flex justify-between items-start mb-5">
                    <div class="flex items-center gap-3">
                      <div class={"w-10 h-10 rounded-xl flex items-center justify-center border transition-all duration-500 shadow-inner #{if entity.energy > 50, do: "bg-cyan-500/10 border-cyan-500/20 text-cyan-400", else: "bg-orange-500/10 border-orange-500/20 text-orange-400"}"}>
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6">
                          <path d="M11.7 2.805a.75.75 0 0 1 .6 0A60.65 60.65 0 0 1 22.83 8.72a.75.75 0 0 1-.231 1.337 49.948 49.948 0 0 0-9.902 3.912l-.003.002-.34.18a.75.75 0 0 1-.707 0A50.88 50.88 0 0 0 7.5 12.173v-.224c0-.131.067-.248.172-.311a54.615 54.615 0 0 1 4.653-2.52.75.75 0 0 0-.65-1.352 56.123 56.123 0 0 0-4.78 2.589 2.258 2.258 0 0 0-1.095 1.944v.647a.75.75 0 0 1-.12.413l-1.95 3.177a3.75 3.75 0 0 0 3.185 5.706h11.27a3.75 3.75 0 0 0 3.185-5.706l-1.95-3.177a.75.75 0 0 1-.12-.413v-.647c0-1.226-.78-2.316-1.93-2.731a61.763 61.763 0 0 0-14.898-3.924.75.75 0 0 1-.23-1.337A62.152 62.152 0 0 1 11.7 2.805Z" />
                        </svg>
                      </div>
                      <div>
                        <h2 class="text-[8px] font-bold text-slate-500 uppercase tracking-widest mb-0.5">ID</h2>
                        <p class="text-white font-black text-base tracking-tight"><%= String.slice(entity.id, 0, 8) %></p>
                      </div>
                    </div>
                    
                    <div class="bg-black/40 rounded-xl px-2.5 py-1.5 border border-white/5 backdrop-blur-md min-w-[50px]">
                      <span class={"text-xs font-mono font-black block text-center #{if entity.energy > 50, do: "text-cyan-400", else: "text-orange-400"}"}>
                        <%= entity.energy %>%
                      </span>
                    </div>
                  </div>

                  <!-- Traits Section -->
                  <div class="grid grid-cols-2 gap-3 mb-6">
                    <div class="bg-white/[0.02] rounded-xl p-3 border border-white/[0.03]">
                      <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold block mb-1">AGGR</span>
                      <div class="flex items-center gap-2">
                        <div class="flex-1 h-1 bg-black/40 rounded-full overflow-hidden">
                          <div class="h-full bg-orange-500 transition-all duration-1000" style={"width: #{entity.traits.aggression * 100}%"}></div>
                        </div>
                        <span class="text-[9px] font-mono font-bold text-orange-400"><%= Float.round(entity.traits.aggression, 1) %></span>
                      </div>
                    </div>
                    
                    <div class="bg-white/[0.02] rounded-xl p-3 border border-white/[0.03]">
                      <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold block mb-1">CURI</span>
                      <div class="flex items-center gap-2">
                        <div class="flex-1 h-1 bg-black/40 rounded-full overflow-hidden">
                          <div class="h-full bg-cyan-500 transition-all duration-1000" style={"width: #{entity.traits.curiosity * 100}%"}></div>
                        </div>
                        <span class="text-[9px] font-mono font-bold text-cyan-400"><%= Float.round(entity.traits.curiosity, 1) %></span>
                      </div>
                    </div>
                  </div>

                  <!-- Behavior Source (Minimized but interactive) -->
                  <div class="mb-5 flex-1 flex flex-col min-h-0">
                    <div class="flex items-center gap-2 mb-2">
                      <div class="w-1 h-1 rounded-full bg-cyan-500/50"></div>
                      <h3 class="text-[9px] uppercase tracking-widest text-cyan-400/80 font-black">Heuristic</h3>
                    </div>
                    <pre class="flex-1 text-[9px] leading-relaxed bg-[#05060a] border border-white/[0.05] p-3 rounded-xl text-cyan-100/40 font-mono overflow-auto max-h-[120px] custom-scrollbar">
<%= entity.behavior_source %>
                    </pre>
                  </div>

                  <!-- Memory Stream -->
                  <div class="mt-auto">
                    <div class="space-y-1.5">
                      <%= for {type, sender} <- Enum.take(EvolvingMinds.Memory.get_memories(entity.id), 2) do %>
                        <div class="flex items-center justify-between bg-white/[0.02] p-2 rounded-lg border border-white/5 transition-colors">
                          <div class="flex items-center gap-2">
                            <div class={"w-1.5 h-1.5 rounded-full #{case type do
                              :attack -> "bg-rose-500"
                              :greet -> "bg-emerald-500"
                              _ -> "bg-amber-400"
                            end}"}></div>
                            <span class="text-[9px] font-bold text-slate-400 uppercase"><%= type %></span>
                          </div>
                          <span class="text-[8px] font-mono text-slate-600">→ <%= String.slice(sender, 0, 4) %></span>
                        </div>
                      <% end %>
                      <%= if Enum.empty?(EvolvingMinds.Memory.get_memories(entity.id)) do %>
                        <div class="text-center py-2 opacity-20">
                          <p class="text-[8px] text-slate-500 font-mono uppercase tracking-widest">Idle</p>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
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