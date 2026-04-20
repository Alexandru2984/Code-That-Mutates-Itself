defmodule EvolvingMinds.World do
  @moduledoc """
  Manages the entities, messaging, and evolution.
  """

  def spawn_entity() do
    DynamicSupervisor.start_child(EvolvingMinds.EntitySupervisor, EvolvingMinds.Entity)
  end

  def spawn_entity(id) do
    DynamicSupervisor.start_child(EvolvingMinds.EntitySupervisor, {EvolvingMinds.Entity, [id: id]})
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
end