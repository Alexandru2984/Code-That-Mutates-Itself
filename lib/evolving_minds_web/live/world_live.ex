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
    <div class="min-h-screen bg-[#0a0b10] bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-slate-900 via-[#0a0b10] to-black text-slate-300 p-4 md:p-8 font-sans selection:bg-cyan-500/30">
      <div class="max-w-7xl mx-auto">
        <header class="flex flex-col md:flex-row items-center justify-between mb-12 gap-6 border-b border-white/5 pb-8">
          <div class="relative">
            <div class="absolute -inset-1 bg-gradient-to-r from-cyan-500 to-blue-600 rounded-lg blur opacity-25 group-hover:opacity-100 transition duration-1000 group-hover:duration-200"></div>
            <h1 class="relative text-4xl md:text-5xl font-extrabold tracking-tighter text-white">
              Evolving <span class="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-blue-500">Minds</span>
            </h1>
            <p class="text-slate-500 mt-2 font-mono text-xs uppercase tracking-[0.3em]">Autonomous Heuristic Entity Simulator</p>
          </div>
          
          <div class="flex items-center gap-4 bg-white/5 backdrop-blur-xl border border-white/10 p-4 rounded-2xl shadow-2xl">
            <div class="flex flex-col items-end">
              <span class="text-[10px] uppercase tracking-widest text-slate-500">Population Matrix</span>
              <span class="text-2xl font-black text-white leading-none"><%= length(@entities) %></span>
            </div>
            <div class="h-8 w-px bg-white/10"></div>
            <div class="flex items-center gap-2">
              <div class="w-2 h-2 rounded-full bg-cyan-500 animate-pulse"></div>
              <span class="text-xs font-mono text-cyan-500/80 uppercase">Live Uplink</span>
            </div>
          </div>
        </header>

        <div class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-8">
          <%= for entity <- @entities do %>
            <div class="group relative bg-slate-900/40 backdrop-blur-md border border-white/5 rounded-3xl p-1 transition-all duration-500 hover:border-cyan-500/30 hover:shadow-[0_0_50px_-12px_rgba(6,182,212,0.2)]">
              <div class="bg-[#0f111a] rounded-[1.4rem] p-6 h-full flex flex-col">
                <!-- Entity Header -->
                <div class="flex justify-between items-start mb-8">
                  <div class="flex items-center gap-3">
                    <div class={"w-10 h-10 rounded-xl flex items-center justify-center border transition-colors duration-500 #{if entity.energy > 50, do: "bg-cyan-500/10 border-cyan-500/20 text-cyan-400", else: "bg-orange-500/10 border-orange-500/20 text-orange-400"}"}>
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6">
                        <path d="M11.7 2.805a.75.75 0 0 1 .6 0A60.65 60.65 0 0 1 22.83 8.72a.75.75 0 0 1-.231 1.337 49.948 49.948 0 0 0-9.902 3.912l-.003.002-.34.18a.75.75 0 0 1-.707 0A50.88 50.88 0 0 0 7.5 12.173v-.224c0-.131.067-.248.172-.311a54.615 54.615 0 0 1 4.653-2.52.75.75 0 0 0-.65-1.352 56.123 56.123 0 0 0-4.78 2.589 2.258 2.258 0 0 0-1.095 1.944v.647a.75.75 0 0 1-.12.413l-1.95 3.177a3.75 3.75 0 0 0 3.185 5.706h11.27a3.75 3.75 0 0 0 3.185-5.706l-1.95-3.177a.75.75 0 0 1-.12-.413v-.647c0-1.226-.78-2.316-1.93-2.731a61.763 61.763 0 0 0-14.898-3.924.75.75 0 0 1-.23-1.337A62.152 62.152 0 0 1 11.7 2.805Z" />
                      </svg>
                    </div>
                    <div>
                      <h2 class="text-xs font-mono text-slate-500 uppercase tracking-tighter">Instance ID</h2>
                      <p class="text-white font-bold leading-tight"><%= String.slice(entity.id, 0, 8) %></p>
                    </div>
                  </div>
                  
                  <div class="text-right">
                    <span class="text-[10px] block uppercase tracking-widest text-slate-500 mb-1 font-bold">Vitality</span>
                    <div class="flex items-center gap-2">
                      <span class={"text-lg font-black #{if entity.energy > 50, do: "text-cyan-400", else: "text-orange-400"}"}>
                        <%= entity.energy %>%
                      </span>
                    </div>
                  </div>
                </div>

                <!-- Traits Grid -->
                <div class="grid grid-cols-2 gap-4 mb-8">
                  <div class="bg-white/5 rounded-2xl p-3 border border-white/5 hover:bg-white/[0.07] transition-colors">
                    <span class="text-[9px] uppercase tracking-widest text-slate-500 block mb-2 font-bold">Aggression</span>
                    <div class="flex items-center gap-3">
                      <div class="flex-1 h-1.5 bg-white/10 rounded-full overflow-hidden">
                        <div class="h-full bg-gradient-to-r from-orange-600 to-red-500 rounded-full transition-all duration-1000" style={"width: #{entity.traits.aggression * 100}%"}></div>
                      </div>
                      <span class="text-xs font-mono text-white/80"><%= Float.round(entity.traits.aggression, 2) %></span>
                    </div>
                  </div>
                  <div class="bg-white/5 rounded-2xl p-3 border border-white/5 hover:bg-white/[0.07] transition-colors">
                    <span class="text-[9px] uppercase tracking-widest text-slate-500 block mb-2 font-bold">Curiosity</span>
                    <div class="flex items-center gap-3">
                      <div class="flex-1 h-1.5 bg-white/10 rounded-full overflow-hidden">
                        <div class="h-full bg-gradient-to-r from-blue-600 to-cyan-500 rounded-full transition-all duration-1000" style={"width: #{entity.traits.curiosity * 100}%"}></div>
                      </div>
                      <span class="text-xs font-mono text-white/80"><%= Float.round(entity.traits.curiosity, 2) %></span>
                    </div>
                  </div>
                </div>

                <!-- Mutating Code Section -->
                <div class="mb-8 flex-1 flex flex-col">
                  <div class="flex items-center justify-between mb-3 px-1">
                    <h3 class="text-[10px] uppercase tracking-[0.2em] text-cyan-500/70 font-bold">Cognitive Mutation Shell</h3>
                    <div class="flex gap-1">
                      <div class="w-1.5 h-1.5 rounded-full bg-white/10"></div>
                      <div class="w-1.5 h-1.5 rounded-full bg-white/10"></div>
                    </div>
                  </div>
                  <div class="relative group/code flex-1 min-h-[140px]">
                    <div class="absolute inset-0 bg-cyan-500/5 rounded-2xl blur-xl opacity-0 group-hover/code:opacity-100 transition duration-700"></div>
                    <pre class="relative h-full text-[11px] leading-relaxed bg-black/40 backdrop-blur-sm border border-white/5 p-4 rounded-2xl text-cyan-100/70 font-mono overflow-x-auto selection:bg-cyan-500/30">
<%= entity.behavior_source %>
                    </pre>
                  </div>
                </div>

                <!-- Interaction Logs -->
                <div>
                  <h3 class="text-[10px] uppercase tracking-[0.2em] text-slate-500 mb-3 font-bold px-1 text-right italic">Interaction Stream</h3>
                  <div class="space-y-2 max-h-32 overflow-y-auto pr-2 custom-scrollbar">
                    <%= for {type, sender} <- Enum.take(EvolvingMinds.Memory.get_memories(entity.id), 4) do %>
                      <div class="flex items-center justify-between bg-white/[0.03] p-2.5 rounded-xl border border-white/5 animate-in slide-in-from-right-2 duration-300">
                        <div class="flex items-center gap-3">
                          <span class={"w-1.5 h-1.5 rounded-full shadow-[0_0_8px] #{case type do
                            :attack -> "bg-red-500 shadow-red-500/50"
                            :greet -> "bg-green-500 shadow-green-500/50"
                            _ -> "bg-cyan-500 shadow-cyan-500/50"
                          end}"}></span>
                          <span class="text-[11px] font-bold text-slate-300 capitalize tracking-tight"><%= type %></span>
                        </div>
                        <span class="text-[10px] font-mono text-slate-500">source: <%= String.slice(sender, 0, 4) %></span>
                      </div>
                    <% end %>
                    <%= if Enum.empty?(EvolvingMinds.Memory.get_memories(entity.id)) do %>
                      <div class="text-center py-4 border-2 border-dashed border-white/5 rounded-2xl">
                        <span class="text-[10px] text-slate-600 italic">Waiting for stimulus...</span>
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