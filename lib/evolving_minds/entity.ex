defmodule EvolvingMinds.Entity do
  use GenServer, restart: :transient
  require Logger

  alias EvolvingMinds.Memory
  alias EvolvingMinds.MutationEngine
  alias EvolvingMinds.World

  def start_link(args \\ []) do
    id = Keyword.get(args, :id, random_id())
    GenServer.start_link(__MODULE__, [id: id], name: via_tuple(id))
  end

  defp random_id() do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  defp via_tuple(id) do
    {:via, Registry, {EvolvingMinds.EntityRegistry, id}}
  end

  def init(args) do
    id = Keyword.fetch!(args, :id)
    
    traits = %{
      aggression: :rand.uniform(),
      curiosity: :rand.uniform()
    }
    
    source_code = MutationEngine.generate_behavior(traits)
    behavior_fn = MutationEngine.compile_behavior(source_code)

    state = %{
      id: id,
      traits: traits,
      behavior_source: source_code,
      behavior_fn: behavior_fn,
      energy: 100
    }

    EvolvingMinds.StateStore.update_state(id, state)
    # Delay the first action slightly to allow the supervisor to settle
    Process.send_after(self(), :act, 2000 + :rand.uniform(3000))
    {:ok, state}
  end

  def handle_cast({:message, type, sender_id}, state) do
    Memory.remember(state.id, {type, sender_id})
    Logger.info("Entity #{state.id} received #{type} from #{sender_id}")
    
    action = try do
      state.behavior_fn.({type, sender_id})
    rescue
      e -> 
        Logger.error("Entity #{state.id} behavior fn failed: #{inspect(e)}")
        {:ignore, nil}
    end

    case action do
      {response_type, ^sender_id} when response_type != :ignore ->
        World.send_message(sender_id, response_type, state.id)
      _ ->
        :ok
    end

    EvolvingMinds.StateStore.update_state(state.id, state)
    {:noreply, state}
  end

  def handle_cast(:inject_energy, state) do
    new_energy = min(100, state.energy + 20)
    new_state = %{state | energy: new_energy}
    EvolvingMinds.StateStore.update_state(state.id, new_state)
    {:noreply, new_state}
  end

  def handle_info(:act, state) do
    case World.get_random_entity(state.id) do
      nil -> :ok
      target_id ->
        type = if :rand.uniform() > state.traits.aggression, do: :greet, else: :attack
        World.send_message(target_id, type, state.id)
    end
    
    new_state = if :rand.uniform() > 0.8 do
      {new_traits, new_source, new_fn} = MutationEngine.mutate(state.traits, state.behavior_source)
      EvolvingMinds.GlobalEvents.report_event(%{type: :mutation, entity_id: state.id})
      Logger.info("Entity #{state.id} mutated.")
      %{state | traits: new_traits, behavior_source: new_source, behavior_fn: new_fn}
    else
      state
    end
    
    new_state = %{new_state | energy: new_state.energy - 5}
    
    if new_state.energy <= 0 do
      EvolvingMinds.GlobalEvents.report_event(%{type: :death, entity_id: new_state.id})
      EvolvingMinds.StateStore.remove_state(new_state.id)
      Logger.info("Entity #{new_state.id} died of exhaustion.")
      {:stop, :normal, new_state}
    else
      EvolvingMinds.StateStore.update_state(new_state.id, new_state)
      Process.send_after(self(), :act, 2000 + :rand.uniform(3000))
      {:noreply, new_state}
    end
  end
end