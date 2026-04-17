defmodule EvolvingMinds.EvolutionEngine do
  use GenServer
  require Logger

  alias EvolvingMinds.World

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Evolution Engine starting. Creating initial population.")
    
    # Needs to run async so application supervisor doesn't block waiting for init
    send(self(), :seed)
    {:ok, state}
  end
  
  def handle_info(:seed, state) do
    for _ <- 1..5 do
      World.spawn_entity()
    end
    Process.send_after(self(), :evaluate, 10000)
    {:noreply, state}
  end

  def handle_info(:evaluate, state) do
    entities = World.get_all_entities()
    population_size = length(entities)
    
    Logger.info("Evaluating world. Population size: #{population_size}")
    
    if population_size < 3 do
      Logger.info("Population low. Spawning new entities.")
      World.spawn_entity()
      World.spawn_entity()
      EvolvingMinds.GlobalEvents.report_event(%{type: :birth, detail: "Population low"})
    end

    if population_size > 0 and :rand.uniform() > 0.5 do
      parent = Enum.random(entities)
      Logger.info("Entity #{parent} reproduced.")
      World.spawn_entity()
      EvolvingMinds.GlobalEvents.report_event(%{type: :reproduction, parent_id: parent})
    end

    Process.send_after(self(), :evaluate, 10000)
    {:noreply, state}
  end
end