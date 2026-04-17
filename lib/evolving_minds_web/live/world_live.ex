defmodule EvolvingMindsWeb.WorldLive do
  use EvolvingMindsWeb, :live_view

  alias EvolvingMinds.World
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(500, :tick)

    socket =
      socket
      |> assign(entities: fetch_entities())
      |> assign(global_events: EvolvingMinds.GlobalEvents.get_recent_events())
      |> assign(stats: EvolvingMinds.Stats.get_history())
      |> assign(top_interactions: EvolvingMinds.Memory.get_top_interactions())

    {:ok, socket, layout: {EvolvingMindsWeb.Layouts, :screen}}
  end

@impl true
def handle_info(:tick, socket) do
  {:noreply, 
   socket 
   |> assign(entities: fetch_entities())
   |> assign(global_events: EvolvingMinds.GlobalEvents.get_recent_events())
   |> assign(stats: EvolvingMinds.Stats.get_history())
   |> assign(top_interactions: EvolvingMinds.Memory.get_top_interactions())
  }
end
@impl true
def handle_event("inject_energy", %{"id" => id}, socket) do
  World.inject_energy(id)
  {:noreply, assign(socket, entities: fetch_entities())}
end

defp fetch_entities do
  EvolvingMinds.StateStore.get_all_states()
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
      <main class="flex-1 w-full px-4 py-8 md:px-8 overflow-hidden flex flex-col lg:flex-row gap-8">
        <!-- Main Simulation Grid -->
        <div class="flex-1 overflow-auto custom-scrollbar-none">
          <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-6">
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
                    
                    <button phx-click="inject_energy" phx-value-id={entity.id} class="group/btn relative px-3 py-1.5 rounded-xl border border-cyan-500/30 bg-cyan-500/5 hover:bg-cyan-500/20 transition-all duration-300">
                      <span class="text-[9px] font-black text-cyan-400 uppercase tracking-widest">+ Energy</span>
                    </button>
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

                  <!-- Energy Bar -->
                  <div class="mb-5">
                    <div class="flex justify-between items-center mb-1.5">
                      <span class="text-[8px] uppercase tracking-widest text-slate-500 font-bold">Vitality</span>
                      <span class={"text-[9px] font-mono font-bold #{if entity.energy > 50, do: "text-cyan-400", else: "text-orange-400"}"}><%= entity.energy %>%</span>
                    </div>
                    <div class="h-1.5 w-full bg-black/40 rounded-full overflow-hidden border border-white/5">
                      <div class={"h-full transition-all duration-1000 #{if entity.energy > 50, do: "bg-cyan-500", else: "bg-orange-500"}"} style={"width: #{entity.energy}%"}></div>
                    </div>
                  </div>

                  <!-- Behavior Source (Minimized) -->
                  <div class="mb-5 flex-1 flex flex-col min-h-0">
                    <div class="flex items-center gap-2 mb-2">
                      <div class="w-1 h-1 rounded-full bg-cyan-500/50"></div>
                      <h3 class="text-[9px] uppercase tracking-widest text-cyan-400/80 font-black">Heuristic</h3>
                    </div>
                    <pre class="flex-1 text-[9px] leading-relaxed bg-[#05060a] border border-white/[0.05] p-3 rounded-xl text-cyan-100/40 font-mono overflow-auto max-h-[100px] custom-scrollbar">
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
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Sidebar for Logs and Stats -->
        <aside class="w-full lg:w-[400px] flex flex-col gap-8">
          <!-- Global Logs -->
          <div class="bg-slate-900/40 backdrop-blur-3xl border border-white/10 rounded-[2rem] p-6 flex flex-col h-[400px]">
            <div class="flex items-center justify-between mb-6">
              <h3 class="text-xs font-black text-white uppercase tracking-[0.3em]">Global Events</h3>
              <div class="px-2 py-0.5 rounded-md bg-cyan-500/10 border border-cyan-500/20">
                <span class="text-[8px] font-bold text-cyan-500 uppercase tracking-widest">Real-time</span>
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
                      _ -> "text-slate-400"
                    end}"}>
                      <%= event.type %>
                    </span>
                    <span class="text-[8px] font-mono text-slate-600">
                      <%= Calendar.strftime(event.timestamp, "%H:%M:%S") %>
                    </span>
                  </div>
                  <p class="text-[10px] text-slate-400 font-medium">
                    <%= if Map.has_key?(event, :entity_id), do: "Entity " <> String.slice(event.entity_id, 0, 8), else: event[:detail] || "System action" %>
                    <%= if Map.has_key?(event, :parent_id), do: "from parent " <> String.slice(event.parent_id, 0, 8), else: "" %>
                  </p>
                </div>
              <% end %>
              <%= if Enum.empty?(@global_events) do %>
                <div class="h-full flex items-center justify-center opacity-20">
                  <p class="text-[9px] font-bold text-slate-500 uppercase tracking-[0.2em]">Monitoring Initializing...</p>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Evolution Stats -->
          <div class="bg-slate-900/40 backdrop-blur-3xl border border-white/10 rounded-[2rem] p-6">
            <h3 class="text-xs font-black text-white uppercase tracking-[0.3em] mb-6">Evolution Trends</h3>
            
            <div class="space-y-6">
              <%= if !Enum.empty?(@stats) do %>
                <% current = List.first(@stats) %>
                <div class="grid grid-cols-2 gap-4">
                  <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                    <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">Avg Aggression</span>
                    <span class="text-xl font-black text-orange-500 tabular-nums"><%= Float.round(current.avg_aggression, 2) %></span>
                  </div>
                  <div class="bg-black/40 p-3 rounded-2xl border border-white/5">
                    <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">Avg Curiosity</span>
                    <span class="text-xl font-black text-cyan-500 tabular-nums"><%= Float.round(current.avg_curiosity, 2) %></span>
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
                        @stats 
                        |> Enum.reverse() 
                        |> Enum.with_index() 
                        |> Enum.map_join(" ", fn {s, i} -> "#{i * (100 / (length(@stats) - 1))},#{100 - s.avg_aggression * 100}" end)
                      }
                    />
                    <!-- Curiosity line -->
                    <polyline
                      fill="none"
                      stroke="#06b6d4"
                      stroke-width="2"
                      stroke-linecap="round"
                      points={
                        @stats 
                        |> Enum.reverse() 
                        |> Enum.with_index() 
                        |> Enum.map_join(" ", fn {s, i} -> "#{i * (100 / (length(@stats) - 1))},#{100 - s.avg_curiosity * 100}" end)
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
                  <p class="text-[9px] font-bold text-slate-500 uppercase tracking-[0.2em]">Calculating Traits...</p>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Top Connections -->
          <div class="bg-slate-900/40 backdrop-blur-3xl border border-white/10 rounded-[2rem] p-6">
            <h3 class="text-xs font-black text-white uppercase tracking-[0.3em] mb-6">Social Graph</h3>
            <div class="space-y-4">
              <%= for {pair, count} <- @top_interactions do %>
                <div class="flex items-center justify-between bg-black/40 p-3 rounded-2xl border border-white/5">
                  <div class="flex items-center gap-2">
                    <span class="text-[9px] font-mono font-bold text-cyan-400"><%= String.slice(Enum.at(pair, 0), 0, 4) %></span>
                    <div class="w-3 h-[1px] bg-slate-700"></div>
                    <span class="text-[9px] font-mono font-bold text-cyan-400"><%= String.slice(Enum.at(pair, 1), 0, 4) %></span>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <span class="text-[10px] font-black text-slate-300"><%= count %></span>
                    <span class="text-[7px] font-bold text-slate-500 uppercase">msgr</span>
                  </div>
                </div>
              <% end %>
              <%= if Enum.empty?(@top_interactions) do %>
                <div class="py-4 text-center opacity-20">
                  <p class="text-[9px] font-bold text-slate-500 uppercase tracking-[0.2em]">Silent World</p>
                </div>
              <% end %>
            </div>
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