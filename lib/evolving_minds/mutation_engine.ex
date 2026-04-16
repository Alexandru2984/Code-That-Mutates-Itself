defmodule EvolvingMinds.MutationEngine do
  # Returns a new function source code for processing messages
  def generate_behavior(traits) do
    aggression = Map.get(traits, :aggression, 0.5)
    curiosity = Map.get(traits, :curiosity, 0.5)

    base_response = if aggression > 0.7, do: ":attack", else: ":greet"
    secondary_response = if curiosity > 0.6, do: ":share_knowledge", else: ":ignore"

    """
    fn
      {:greet, sender_id} ->
        if :rand.uniform() > 0.5 do
          {#{base_response}, sender_id}
        else
          {#{secondary_response}, sender_id}
        end
      {:attack, sender_id} ->
        {:flee, sender_id}
      {:share_knowledge, sender_id} ->
        {:greet, sender_id}
      _ ->
        {:ignore, nil}
    end
    """
  end

  def compile_behavior(source_code) do
    {fun, _} = Code.eval_string(source_code)
    fun
  end

  def mutate(traits, current_source) do
    new_traits = %{
      aggression: min(1.0, max(0.0, traits.aggression + (:rand.uniform() - 0.5) * 0.2)),
      curiosity: min(1.0, max(0.0, traits.curiosity + (:rand.uniform() - 0.5) * 0.2))
    }
    
    if :rand.uniform() > 0.8 do
      new_source = generate_behavior(new_traits)
      {new_traits, new_source, compile_behavior(new_source)}
    else
      {new_traits, current_source, compile_behavior(current_source)}
    end
  end
end