defmodule EvolvingMinds.Entity do
  @moduledoc """
  A single mind: acts on a timer, exchanges messages, and lives or dies
  by the interaction economy below.

  ## Economy

  Incoming interactions are resolved against the receiver's behavior
  response — energy flows, but no reply messages are sent, so there are
  no cascades:

  | incoming          | response          | receiver | sender |
  |-------------------|-------------------|----------|--------|
  | attack            | flee              | -6       | +8     |
  | attack            | attack (fight)    | -10      | -10    |
  | greet             | greet             | +2       | +2     |
  | greet             | share_knowledge   | +2       | +6     |
  | greet             | attack (betrayal) | +5       | -8     |
  | share_knowledge   | share_knowledge   | +6       | +6     |
  | share_knowledge   | greet             | +6       | +2     |
  | share_knowledge   | attack (betrayal) | +5       | -8     |

  Robbing loners pays, wars bleed both sides, and cooperation compounds:
  selection pressure is frequency-dependent.
  """

  use GenServer, restart: :transient
  require Logger

  alias EvolvingMinds.Memory
  alias EvolvingMinds.MutationEngine
  alias EvolvingMinds.World

  @flee_damage 6
  @attack_gain 8
  @war_damage 10
  @caught_damage 12
  @greet_bonus 2
  @share_bonus 6
  @betrayal_gain 5
  @betrayal_damage 8
  @act_cost 5
  @max_energy 100

  def start_link(args \\ []) do
    args = Keyword.put_new(args, :id, random_id())
    GenServer.start_link(__MODULE__, args, name: via_tuple(args[:id]))
  end

  defp random_id() do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  defp via_tuple(id) do
    {:via, Registry, {EvolvingMinds.EntityRegistry, id}}
  end

  def init(args) do
    id = Keyword.fetch!(args, :id)

    traits =
      Keyword.get(args, :traits) ||
        %{
          aggression: :rand.uniform(),
          curiosity: :rand.uniform()
        }

    generation = Keyword.get(args, :generation, 1)

    source_code = MutationEngine.generate_behavior(traits)
    behavior_fn = MutationEngine.compile_behavior(traits)

    state = %{
      id: id,
      traits: traits,
      behavior_source: source_code,
      behavior_fn: behavior_fn,
      # energy/born_at options exist for world restores after restarts
      energy: Keyword.get(args, :energy, 100),
      generation: generation,
      parent_id: Keyword.get(args, :parent_id),
      born_at: Keyword.get(args, :born_at, System.system_time(:second))
    }

    EvolvingMinds.StateStore.update_state(id, state)

    :telemetry.execute([:evolving_minds, :entity, :spawn], %{count: 1}, %{
      id: id,
      traits: traits,
      generation: generation
    })

    # Delay the first action slightly to allow the supervisor to settle
    Process.send_after(self(), :act, 2000 + :rand.uniform(3000))
    {:ok, state}
  end

  def handle_cast({:message, type, sender_id}, state) do
    Memory.remember(state.id, {type, sender_id})
    Logger.debug("Entity #{state.id} received #{type} from #{sender_id}")

    # The behavior decides the response; its effects are applied as pure
    # energy transfers (no reply messages, so no ping-pong cascades).
    response =
      try do
        state.behavior_fn.({type, sender_id})
      rescue
        e ->
          Logger.error("Entity #{state.id} behavior fn failed: #{inspect(e)}")
          {:ignore, nil}
      end

    {self_delta, sender_delta} = resolve_interaction(type, response)

    :telemetry.execute([:evolving_minds, :entity, :interaction], %{count: 1}, %{
      id: state.id,
      sender_id: sender_id,
      type: type,
      response: response_type(response)
    })

    if sender_delta != 0, do: World.adjust_energy(sender_id, sender_delta)

    apply_energy(state, self_delta, :killed)
  end

  def handle_cast({:adjust_energy, delta}, state) do
    apply_energy(state, delta, :killed)
  end

  def handle_cast(:inject_energy, state) do
    apply_energy(state, 20, :killed)
  end

  def handle_info(:act, state) do
    case World.get_random_entity(state.id) do
      nil ->
        :ok

      target_id ->
        type = if :rand.uniform() > state.traits.aggression, do: :greet, else: :attack
        World.send_message(target_id, type, state.id)
    end

    new_state =
      if :rand.uniform() > 0.8 do
        {new_traits, new_source, new_fn} =
          MutationEngine.mutate(state.traits, state.behavior_source, state.behavior_fn)

        EvolvingMinds.GlobalEvents.report_event(%{type: :mutation, entity_id: state.id})

        :telemetry.execute([:evolving_minds, :entity, :mutation], %{count: 1}, %{
          id: state.id,
          traits: new_traits
        })

        Logger.info("Entity #{state.id} mutated.")
        %{state | traits: new_traits, behavior_source: new_source, behavior_fn: new_fn}
      else
        state
      end

    case apply_energy(new_state, -@act_cost, :exhaustion) do
      {:noreply, live_state} ->
        Process.send_after(self(), :act, 2000 + :rand.uniform(3000))
        {:noreply, live_state}

      stop ->
        stop
    end
  end

  # Returns {receiver delta, original sender delta}.
  defp resolve_interaction(:attack, {:flee, _}), do: {-@flee_damage, @attack_gain}
  defp resolve_interaction(:attack, {:attack, _}), do: {-@war_damage, -@war_damage}
  defp resolve_interaction(:attack, _), do: {-@caught_damage, @attack_gain}

  defp resolve_interaction(:greet, {:greet, _}), do: {@greet_bonus, @greet_bonus}
  defp resolve_interaction(:greet, {:share_knowledge, _}), do: {@greet_bonus, @share_bonus}
  defp resolve_interaction(:greet, {:attack, _}), do: {@betrayal_gain, -@betrayal_damage}
  defp resolve_interaction(:greet, _), do: {0, 0}

  defp resolve_interaction(:share_knowledge, {:share_knowledge, _}),
    do: {@share_bonus, @share_bonus}

  defp resolve_interaction(:share_knowledge, {:greet, _}), do: {@share_bonus, @greet_bonus}

  defp resolve_interaction(:share_knowledge, {:attack, _}),
    do: {@betrayal_gain, -@betrayal_damage}

  defp resolve_interaction(:share_knowledge, _), do: {@share_bonus, 0}

  defp resolve_interaction(_, _), do: {0, 0}

  defp response_type({action, _}) when is_atom(action), do: action
  defp response_type(_), do: :ignore

  defp apply_energy(state, delta, death_cause) do
    new_state = %{state | energy: min(@max_energy, state.energy + delta)}

    if new_state.energy <= 0 do
      die(new_state, death_cause)
    else
      EvolvingMinds.StateStore.update_state(new_state.id, new_state)
      {:noreply, new_state}
    end
  end

  defp die(state, cause) do
    EvolvingMinds.GlobalEvents.report_event(%{type: :death, entity_id: state.id, cause: cause})

    :telemetry.execute([:evolving_minds, :entity, :death], %{count: 1}, %{
      id: state.id,
      cause: cause
    })

    Logger.info("Entity #{state.id} died (#{cause}).")
    # State and memory cleanup happens in StateStore, which monitors this
    # process and purges on :DOWN — the same path crashes take.
    {:stop, :normal, state}
  end
end
