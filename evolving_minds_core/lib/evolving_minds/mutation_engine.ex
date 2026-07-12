defmodule EvolvingMinds.MutationEngine do
  @moduledoc """
  Builds each mind's behavior from its traits.

  A behavior is a plain closure mapping an incoming interaction to a
  response action; `generate_behavior/1` renders the equivalent source
  shown in the UI. Nothing is eval-ed at runtime.
  """

  # Returns the display source mirroring the closure built below.
  def generate_behavior(traits) do
    aggression = Map.get(traits, :aggression, 0.5)
    curiosity = Map.get(traits, :curiosity, 0.5)

    base_response = if aggression > 0.7, do: ":attack", else: ":greet"
    secondary_response = if curiosity > 0.6, do: ":share_knowledge", else: ":ignore"
    fight_response = if aggression > 0.5, do: ":attack", else: ":flee"
    share_reciprocity = if curiosity > 0.5, do: ":share_knowledge", else: ":greet"

    """
    fn
      {:greet, sender_id} ->
        if :rand.uniform() > 0.5 do
          {#{base_response}, sender_id}
        else
          {#{secondary_response}, sender_id}
        end
      {:attack, sender_id} ->
        {#{fight_response}, sender_id}
      {:share_knowledge, sender_id} ->
        {#{share_reciprocity}, sender_id}
      _ ->
        {:ignore, nil}
    end
    """
  end

  # Builds a behavior closure directly from traits — no dynamic code compilation.
  def compile_behavior(traits) do
    aggression = Map.get(traits, :aggression, 0.5)
    curiosity = Map.get(traits, :curiosity, 0.5)

    base_response = if aggression > 0.7, do: :attack, else: :greet
    secondary_response = if curiosity > 0.6, do: :share_knowledge, else: :ignore
    fight_response = if aggression > 0.5, do: :attack, else: :flee
    share_reciprocity = if curiosity > 0.5, do: :share_knowledge, else: :greet

    fn
      {:greet, sender_id} ->
        if :rand.uniform() > 0.5,
          do: {base_response, sender_id},
          else: {secondary_response, sender_id}

      {:attack, sender_id} ->
        {fight_response, sender_id}

      {:share_knowledge, sender_id} ->
        {share_reciprocity, sender_id}

      _ ->
        {:ignore, nil}
    end
  end

  def mutate(traits, current_source, current_fn) do
    new_traits = %{
      aggression: min(1.0, max(0.0, traits.aggression + (:rand.uniform() - 0.5) * 0.2)),
      curiosity: min(1.0, max(0.0, traits.curiosity + (:rand.uniform() - 0.5) * 0.2))
    }

    if :rand.uniform() > 0.8 do
      new_source = generate_behavior(new_traits)
      {new_traits, new_source, compile_behavior(new_traits)}
    else
      # Reuse existing compiled function — no recompilation needed
      {new_traits, current_source, current_fn}
    end
  end

  @doc """
  Jitters inherited traits at birth: children resemble their parent but
  are never identical.
  """
  def inherit(parent_traits) do
    %{
      aggression: min(1.0, max(0.0, parent_traits.aggression + (:rand.uniform() - 0.5) * 0.3)),
      curiosity: min(1.0, max(0.0, parent_traits.curiosity + (:rand.uniform() - 0.5) * 0.3))
    }
  end
end
