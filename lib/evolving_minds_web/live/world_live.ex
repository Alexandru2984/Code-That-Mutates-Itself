defmodule EvolvingMindsWeb.WorldLive do
  use EvolvingMindsWeb, :live_view

  alias EvolvingMinds.World

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(500, :tick)
    {:ok, assign(socket, entities: fetch_entities())}
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
    <div class="min-h-screen bg-[#050608] bg-[radial-gradient(circle_at_50%_0%,_var(--tw-gradient-stops))] from-slate-900/40 via-[#050608] to-black text-slate-300 p-4 md:p-6 font-sans selection:bg-cyan-500/30">
      <div class="w-full">
        <header class="flex flex-col lg:flex-row items-center justify-between mb-10 gap-6 border-b border-white/5 pb-8 px-2">
          <div class="relative group">
            <div class="absolute -inset-2 bg-gradient-to-r from-cyan-600 to-blue-700 rounded-xl blur-lg opacity-20 group-hover:opacity-40 transition duration-1000"></div>
            <h1 class="relative text-5xl md:text-6xl font-black tracking-tighter text-white">
              Evolving <span class="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 via-blue-500 to-indigo-600">Minds</span>
            </h1>
            <div class="flex items-center gap-3 mt-3">
              <p class="text-slate-500 font-mono text-[10px] uppercase tracking-[0.4em]">Autonomous Heuristic Entity Simulator</p>
              <div class="h-px w-12 bg-white/10"></div>
              <span class="text-[9px] text-cyan-500/50 font-bold uppercase tracking-widest animate-pulse">v2.0 Wide-Spectrum</span>
            </div>
          </div>
          
          <div class="flex items-center gap-6 bg-slate-900/40 backdrop-blur-3xl border border-white/10 p-5 rounded-3xl shadow-2xl">
            <div class="flex flex-col items-center px-4">
              <span class="text-[9px] uppercase tracking-[0.2em] text-slate-500 font-bold mb-1">Global Population</span>
              <span class="text-3xl font-black text-white leading-none tabular-nums"><%= length(@entities) %></span>
            </div>
            <div class="h-10 w-px bg-white/10"></div>
            <div class="flex flex-col items-start gap-1">
              <div class="flex items-center gap-2">
                <div class="w-2 h-2 rounded-full bg-cyan-500 animate-ping"></div>
                <span class="text-[10px] font-mono text-cyan-500 font-bold uppercase tracking-widest">Live Uplink</span>
              </div>
              <span class="text-[9px] text-slate-500 font-medium tracking-tight">Syncing BEAM Processes...</span>
            </div>
          </div>
        </header>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 3xl:grid-cols-6 gap-5 px-2">
          <%= for entity <- @entities do %>
            <div class="group relative bg-slate-900/20 backdrop-blur-xl border border-white/5 rounded-[2.5rem] p-1.5 transition-all duration-700 hover:scale-[1.02] hover:border-cyan-500/40 hover:shadow-[0_0_60px_-15px_rgba(6,182,212,0.3)]">
              <div class="bg-[#0b0d15]/90 rounded-[2.2rem] p-6 h-full flex flex-col border border-white/[0.03]">
                <!-- Entity Header -->
                <div class="flex justify-between items-start mb-6">
                  <div class="flex items-center gap-4">
                    <div class={"w-12 h-12 rounded-2xl flex items-center justify-center border-2 transition-all duration-700 shadow-inner #{if entity.energy > 50, do: "bg-cyan-500/10 border-cyan-500/20 text-cyan-400 shadow-cyan-500/10", else: "bg-orange-500/10 border-orange-500/20 text-orange-400 shadow-orange-500/10"}"}>
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-7 h-7">
                        <path d="M11.7 2.805a.75.75 0 0 1 .6 0A60.65 60.65 0 0 1 22.83 8.72a.75.75 0 0 1-.231 1.337 49.948 49.948 0 0 0-9.902 3.912l-.003.002-.34.18a.75.75 0 0 1-.707 0A50.88 50.88 0 0 0 7.5 12.173v-.224c0-.131.067-.248.172-.311a54.615 54.615 0 0 1 4.653-2.52.75.75 0 0 0-.65-1.352 56.123 56.123 0 0 0-4.78 2.589 2.258 2.258 0 0 0-1.095 1.944v.647a.75.75 0 0 1-.12.413l-1.95 3.177a3.75 3.75 0 0 0 3.185 5.706h11.27a3.75 3.75 0 0 0 3.185-5.706l-1.95-3.177a.75.75 0 0 1-.12-.413v-.647c0-1.226-.78-2.316-1.93-2.731a61.763 61.763 0 0 0-14.898-3.924.75.75 0 0 1-.23-1.337A62.152 62.152 0 0 1 11.7 2.805Z" />
                      </svg>
                    </div>
                    <div>
                      <h2 class="text-[9px] font-bold text-slate-500 uppercase tracking-[0.2em] mb-0.5">Matrix ID</h2>
                      <p class="text-white font-black text-lg leading-tight tracking-tight"><%= String.slice(entity.id, 0, 8) %></p>
                    </div>
                  </div>
                  
                  <div class="bg-black/40 rounded-2xl px-3 py-2 border border-white/5 backdrop-blur-md">
                    <span class="text-[8px] block uppercase tracking-widest text-slate-500 mb-0.5 font-black text-center">Vitality</span>
                    <span class={"text-sm font-mono font-black block text-center #{if entity.energy > 50, do: "text-cyan-400", else: "text-orange-400"}"}>
                      <%= entity.energy %>%
                    </span>
                  </div>
                </div>

                <!-- Traits Section -->
                <div class="space-y-4 mb-8">
                  <div class="group/trait bg-white/[0.02] hover:bg-white/[0.05] rounded-2xl p-4 border border-white/[0.03] transition-all duration-500">
                    <div class="flex justify-between items-center mb-2.5">
                      <span class="text-[10px] uppercase tracking-widest text-slate-400 font-bold">Aggression</span>
                      <span class="text-xs font-mono font-bold text-orange-400"><%= Float.round(entity.traits.aggression, 2) %></span>
                    </div>
                    <div class="w-full h-1.5 bg-black/40 rounded-full overflow-hidden p-[1px]">
                      <div class="h-full bg-gradient-to-r from-orange-600 via-red-500 to-rose-600 rounded-full transition-all duration-1000 shadow-[0_0_10px_rgba(244,63,94,0.3)]" style={"width: #{entity.traits.aggression * 100}%"}></div>
                    </div>
                  </div>
                  
                  <div class="group/trait bg-white/[0.02] hover:bg-white/[0.05] rounded-2xl p-4 border border-white/[0.03] transition-all duration-500">
                    <div class="flex justify-between items-center mb-2.5">
                      <span class="text-[10px] uppercase tracking-widest text-slate-400 font-bold">Curiosity</span>
                      <span class="text-xs font-mono font-bold text-cyan-400"><%= Float.round(entity.traits.curiosity, 2) %></span>
                    </div>
                    <div class="w-full h-1.5 bg-black/40 rounded-full overflow-hidden p-[1px]">
                      <div class="h-full bg-gradient-to-r from-blue-600 via-cyan-500 to-emerald-500 rounded-full transition-all duration-1000 shadow-[0_0_10px_rgba(6,182,212,0.3)]" style={"width: #{entity.traits.curiosity * 100}%"}></div>
                    </div>
                  </div>
                </div>

                <!-- Behavior Section -->
                <div class="flex-1 flex flex-col min-h-0 mb-6">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <div class="w-1.5 h-1.5 rounded-full bg-cyan-500/50 shadow-[0_0_8px_rgba(6,182,212,0.5)] animate-pulse"></div>
                      <h3 class="text-[10px] uppercase tracking-[0.3em] text-cyan-400/80 font-black">Heuristic Root</h3>
                    </div>
                    <span class="text-[8px] font-mono text-slate-600">Runtime: BEAM-OPT</span>
                  </div>
                  <div class="relative flex-1 group/code min-h-[160px]">
                    <div class="absolute inset-0 bg-cyan-500/5 rounded-2xl blur-2xl opacity-0 group-hover/code:opacity-100 transition duration-1000"></div>
                    <pre class="relative h-full text-[10px] leading-relaxed bg-[#05060a] border border-white/[0.05] p-5 rounded-3xl text-cyan-100/60 font-mono overflow-auto custom-scrollbar shadow-2xl">
<%= entity.behavior_source %>
                    </pre>
                  </div>
                </div>

                <!-- Footer / Logs -->
                <div>
                  <div class="flex items-center justify-between mb-3 px-1">
                    <h3 class="text-[9px] uppercase tracking-widest text-slate-500 font-black">Memory Stream</h3>
                    <div class="h-px flex-1 mx-4 bg-white/5"></div>
                  </div>
                  <div class="space-y-2 max-h-36 overflow-y-auto pr-1 custom-scrollbar">
                    <%= for {type, sender} <- Enum.take(EvolvingMinds.Memory.get_memories(entity.id), 3) do %>
                      <div class="flex items-center justify-between bg-white/[0.02] p-3 rounded-2xl border border-white/5 transition-colors hover:bg-white/[0.04] animate-in fade-in zoom-in-95 duration-500">
                        <div class="flex items-center gap-3">
                          <div class={"w-2 h-2 rounded-full shadow-[0_0_12px] #{case type do
                            :attack -> "bg-rose-500 shadow-rose-500/60"
                            :greet -> "bg-emerald-500 shadow-emerald-500/60"
                            _ -> "bg-amber-400 shadow-amber-400/60"
                          end}"}></div>
                          <span class="text-[10px] font-black text-slate-400 uppercase tracking-tighter"><%= type %></span>
                        </div>
                        <span class="text-[9px] font-mono text-slate-600 font-bold">src: <%= String.slice(sender, 0, 4) %></span>
                      </div>
                    <% end %>
                    <%= if Enum.empty?(EvolvingMinds.Memory.get_memories(entity.id)) do %>
                      <div class="text-center py-6 border-2 border-dashed border-white/5 rounded-3xl opacity-40">
                        <p class="text-[9px] text-slate-500 font-mono uppercase tracking-[0.2em]">Matrix Idle</p>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <style>
        .custom-scrollbar::-webkit-scrollbar {
          width: 4px;
        }
        .custom-scrollbar::-webkit-scrollbar-track {
          background: rgba(255, 255, 255, 0.02);
          border-radius: 10px;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb {
          background: rgba(255, 255, 255, 0.1);
          border-radius: 10px;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb:hover {
          background: rgba(6, 182, 212, 0.3);
        }
      </style>
    </div>
    """
  end
end