defmodule EvolvingMinds.World do
  @moduledoc """
  Manages the entities, messaging, and evolution.
  """

  @doc """
  Spawns an entity. Accepts a binary id, a keyword list of entity options
  (`:id`, `:traits`, `:generation`, `:parent_id`, `:energy`, `:born_at`),
  or nothing for a fully random mind.
  """
  def spawn_entity(id_or_opts \\ [])

  def spawn_entity(opts) when is_list(opts) do
    DynamicSupervisor.start_child(EvolvingMinds.EntitySupervisor, {EvolvingMinds.Entity, opts})
  end

  def spawn_entity(id) when is_binary(id), do: spawn_entity(id, [])

  def spawn_entity(id, opts) when is_binary(id) and is_list(opts) do
    spawn_entity([id: id] ++ opts)
  end

  @doc "Returns the registered id of a live entity pid."
  def id_of(pid) do
    EvolvingMinds.EntityRegistry |> Registry.keys(pid) |> List.first()
  end

  def get_all_entities() do
    Registry.select(EvolvingMinds.EntityRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def get_random_entity(exclude_id) do
    entities = get_all_entities() |> Enum.reject(&(&1 == exclude_id))
    if entities == [], do: nil, else: Enum.random(entities)
  end

  def send_message(target_id, type, sender_id) do
    case Registry.lookup(EvolvingMinds.EntityRegistry, target_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:message, type, sender_id})

      [] ->
        :ok
    end
  end

  def inject_energy(target_id) do
    case Registry.lookup(EvolvingMinds.EntityRegistry, target_id) do
      [{pid, _}] ->
        GenServer.cast(pid, :inject_energy)

      [] ->
        :ok
    end
  end

  @paused_key {__MODULE__, :paused}

  @doc "Freezes the simulation: entities keep their timers but skip acting."
  def pause, do: :persistent_term.put(@paused_key, true)

  def resume, do: :persistent_term.put(@paused_key, false)

  def paused?, do: :persistent_term.get(@paused_key, false)

  @doc """
  Applies a raw energy transfer to an entity (interaction settlements).
  Unlike messages, adjustments never trigger behavior responses.
  """
  def adjust_energy(target_id, delta) do
    case Registry.lookup(EvolvingMinds.EntityRegistry, target_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:adjust_energy, delta})

      [] ->
        :ok
    end
  end
end
