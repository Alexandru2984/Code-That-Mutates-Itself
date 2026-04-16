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
    <div class="min-h-screen bg-gray-900 text-green-400 p-8 font-mono">
      <h1 class="text-4xl font-bold text-center mb-8 text-green-500">Evolving Minds <span class="text-sm font-normal">Experimental Live System</span></h1>
      
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for entity <- @entities do %>
          <div class="bg-gray-800 border border-green-700 rounded-lg p-6 shadow-lg shadow-green-900/20">
            <div class="flex justify-between items-center border-b border-green-800 pb-2 mb-4">
              <h2 class="text-xl font-bold">ID: <%= entity.id %></h2>
              <span class={"px-3 py-1 rounded-full text-xs font-bold #{if entity.energy > 50, do: "bg-green-900 text-green-300", else: "bg-red-900 text-red-300"}"}>
                Energy: <%= entity.energy %>
              </span>
            </div>
            
            <div class="space-y-4">
              <div>
                <h3 class="text-sm uppercase tracking-wider text-green-600 mb-1">Traits</h3>
                <div class="flex justify-between text-sm">
                  <span>Aggression:</span>
                  <span class="font-bold"><%= Float.round(entity.traits.aggression, 2) %></span>
                </div>
                <div class="w-full bg-gray-700 rounded-full h-1.5 mb-2">
                  <div class="bg-red-500 h-1.5 rounded-full" style={"width: #{entity.traits.aggression * 100}%"}></div>
                </div>
                
                <div class="flex justify-between text-sm">
                  <span>Curiosity:</span>
                  <span class="font-bold"><%= Float.round(entity.traits.curiosity, 2) %></span>
                </div>
                <div class="w-full bg-gray-700 rounded-full h-1.5">
                  <div class="bg-blue-500 h-1.5 rounded-full" style={"width: #{entity.traits.curiosity * 100}%"}></div>
                </div>
              </div>
              
              <div>
                <h3 class="text-sm uppercase tracking-wider text-green-600 mb-1">Behavior (Mutating)</h3>
                <pre class="text-xs bg-black p-3 rounded overflow-x-auto text-gray-300 border border-gray-700"><%= entity.behavior_source %></pre>
              </div>
              
              <div>
                <h3 class="text-sm uppercase tracking-wider text-green-600 mb-1">Recent Memory (Events)</h3>
                <ul class="text-xs space-y-1 h-24 overflow-y-auto bg-black p-2 rounded border border-gray-700">
                  <%= for {type, sender} <- Enum.take(EvolvingMinds.Memory.get_memories(entity.id), 5) do %>
                    <li>
                      <span class="text-yellow-400"><%= type %></span> from <%= sender %>
                    </li>
                  <% end %>
                  <%= if Enum.empty?(EvolvingMinds.Memory.get_memories(entity.id)) do %>
                    <li class="text-gray-500 italic">No interactions yet.</li>
                  <% end %>
                </ul>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end