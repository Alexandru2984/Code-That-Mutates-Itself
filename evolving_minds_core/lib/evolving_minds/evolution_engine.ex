defmodule EvolvingMinds.EvolutionEngine do
  @moduledoc """
  Keeps the population alive and evolving.

  Reproduction is fitness-weighted: parents are drawn with probability
  proportional to their current energy, and children inherit jittered
  traits, so selection pressure from the interaction economy actually
  shapes the gene pool.
  """

  use GenServer
  require Logger

  alias EvolvingMinds.MutationEngine
  alias EvolvingMinds.StateStore
  alias EvolvingMinds.World

  @max_population 50

  def max_population, do: @max_population

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
    # A restored world keeps its population; only seed when empty.
    if World.get_all_entities() == [] do
      for _ <- 1..5 do
        World.spawn_entity()
      end
    end

    Process.send_after(self(), :evaluate, 10000)
    {:noreply, state}
  end

  def handle_info(:evaluate, state) do
    if World.paused?() do
      Process.send_after(self(), :evaluate, 10000)
      {:noreply, state}
    else
      evaluate(state)
    end
  end

  defp evaluate(state) do
    states = StateStore.get_all_states()
    population_size = length(states)

    Logger.debug("Evaluating world. Population size: #{population_size}")

    if population_size < 3 do
      Logger.debug("Population low. Spawning new entities.")
      World.spawn_entity()
      World.spawn_entity()
      EvolvingMinds.GlobalEvents.report_event(%{type: :birth, detail: "Population low"})
    end

    if population_size > 0 and population_size < @max_population and :rand.uniform() > 0.5 do
      reproduce(states)
    end

    Process.send_after(self(), :evaluate, 10000)
    {:noreply, state}
  end

  @doc """
  Spawns a child of a fitness-weighted parent picked from `states`.
  Children inherit jittered traits and the parent's generation + 1.
  """
  def reproduce([]), do: :noop

  def reproduce(states) do
    parent = weighted_parent(states)
    child_generation = parent.generation + 1

    {:ok, pid} =
      World.spawn_entity(
        traits: MutationEngine.inherit(parent.traits),
        generation: child_generation,
        parent_id: parent.id,
        tribe: Map.get(parent, :tribe)
      )

    child_id = World.id_of(pid)
    child = StateStore.get_state(child_id)

    EvolvingMinds.GlobalEvents.report_event(%{
      type: :reproduction,
      entity_id: child_id,
      name: child && child.name,
      parent_id: parent.id,
      parent_name: parent[:name],
      generation: child_generation
    })

    Logger.debug("Entity #{parent.id} reproduced -> #{child_id} (gen #{child_generation}).")
    {:ok, child_id, parent.id}
  end

  # Draws a parent with probability proportional to its energy.
  defp weighted_parent(states) do
    total = states |> Enum.map(& &1.energy) |> Enum.sum()
    pick = :rand.uniform() * total

    result =
      Enum.reduce_while(states, pick, fn entity_state, remaining ->
        if remaining <= entity_state.energy do
          {:halt, entity_state}
        else
          {:cont, remaining - entity_state.energy}
        end
      end)

    # Float edge: if no bucket halted, fall back to the last candidate.
    if is_map(result), do: result, else: List.last(states)
  end
end
