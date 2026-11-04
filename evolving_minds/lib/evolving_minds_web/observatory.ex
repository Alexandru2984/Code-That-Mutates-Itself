defmodule EvolvingMindsWeb.Observatory do
  @moduledoc "Public, deterministic projections of the living world."

  @sorts ~w(energy_desc energy_asc aggression_desc curiosity_desc generation_desc oldest)
  @tribes ~w(all solari umbra)
  @statuses ~w(all thriving critical descendants)

  def filters(params) when is_map(params) do
    %{
      query: text(params["query"], 100),
      sort: allowed(params["sort"], @sorts, "energy_desc"),
      tribe: allowed(params["tribe"], @tribes, "all"),
      status: allowed(params["status"], @statuses, "all")
    }
  end

  def visible(entities, filters, watched, only_watched) do
    query = String.downcase(filters.query)

    entities
    |> Enum.filter(fn e ->
      (String.contains?(String.downcase(e.name || ""), query) or
         String.contains?(String.downcase(e.id), query)) and
        (filters.tribe == "all" or to_string(e.tribe) == filters.tribe) and
        status?(e, filters.status) and
        (not only_watched or e.id in watched)
    end)
    |> Enum.sort_by(&sort_key(&1, filters.sort))
  end

  def summary(entities) do
    count = length(entities)

    %{
      population: count,
      energy:
        if(count == 0, do: 0, else: round(Enum.sum(Enum.map(entities, & &1.energy)) / count)),
      generation: Enum.max(Enum.map(entities, & &1.generation), fn -> 0 end),
      solari: Enum.count(entities, &(&1.tribe == :solari)),
      umbra: Enum.count(entities, &(&1.tribe == :umbra)),
      critical: Enum.count(entities, &(&1.energy <= 25))
    }
  end

  def personality(%{aggression: a}) when a >= 0.7, do: "Warrior"
  def personality(%{curiosity: c}) when c >= 0.6, do: "Explorer"
  def personality(%{aggression: a}) when a < 0.3, do: "Diplomat"
  def personality(_), do: "Balancer"

  def age(seconds) when seconds >= 3600,
    do: "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"

  def age(seconds) when seconds >= 60, do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  def age(seconds), do: "#{max(seconds, 0)}s"

  def text(value, max) when is_binary(value), do: value |> String.slice(0, max) |> String.trim()
  def text(_, _), do: ""
  def id?(id), do: is_binary(id) and byte_size(id) in 1..128 and String.valid?(id)
  defp allowed(value, choices, default), do: if(value in choices, do: value, else: default)
  defp status?(e, "thriving"), do: e.energy >= 75
  defp status?(e, "critical"), do: e.energy <= 25
  defp status?(e, "descendants"), do: e.generation > 1
  defp status?(_, _), do: true
  defp sort_key(e, "energy_asc"), do: {e.energy, e.id}
  defp sort_key(e, "aggression_desc"), do: {-e.traits.aggression, e.id}
  defp sort_key(e, "curiosity_desc"), do: {-e.traits.curiosity, e.id}
  defp sort_key(e, "generation_desc"), do: {-e.generation, e.id}
  defp sort_key(e, "oldest"), do: {e.born_at, e.id}
  defp sort_key(e, _), do: {-e.energy, e.id}
end
