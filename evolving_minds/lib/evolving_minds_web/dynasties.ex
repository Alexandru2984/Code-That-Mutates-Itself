defmodule EvolvingMindsWeb.Dynasties do
  @moduledoc "Summaries of retained families, with memoized roots and safe legacy cycle handling."

  def summarize(records) do
    by_id = Map.new(records, &{&1.id, &1})

    roots =
      Enum.reduce(records, %{}, fn record, memo ->
        {_root, memo} = resolve(record.id, by_id, memo, MapSet.new(), [])
        memo
      end)

    records
    |> Enum.group_by(&roots[&1.id].id)
    |> Enum.map(fn {id, members} ->
      root = roots[id]
      founder = by_id[id]

      %{
        id: id,
        name: founder.name || String.slice(id, 0, 8),
        tribe: founder.tribe,
        total: length(members),
        alive: Enum.count(members, & &1.alive),
        max_generation: Enum.max(Enum.map(members, & &1.generation)),
        incomplete: root.incomplete,
        cyclic: root.cyclic,
        member_ids: MapSet.new(members, & &1.id)
      }
    end)
    |> Enum.sort_by(&{-&1.alive, -&1.total, &1.name, &1.id})
  end

  defp resolve(id, by_id, memo, seen, trail) do
    cond do
      Map.has_key?(memo, id) ->
        finish(memo[id], memo, trail)

      MapSet.member?(seen, id) ->
        # Only members of the loop choose its representative, not a descendant
        # that led us into it. Each record is resolved once for the full refresh.
        cycle = [id | Enum.take_while(trail, &(&1 != id))]
        finish(%{id: Enum.min(cycle), incomplete: false, cyclic: true}, memo, trail)

      true ->
        record = Map.fetch!(by_id, id)
        trail = [id | trail]

        cond do
          is_nil(record.parent_id) ->
            finish(%{id: id, incomplete: false, cyclic: false}, memo, trail)

          not Map.has_key?(by_id, record.parent_id) ->
            finish(%{id: id, incomplete: true, cyclic: false}, memo, trail)

          true ->
            resolve(record.parent_id, by_id, memo, MapSet.put(seen, id), trail)
        end
    end
  end

  defp finish(root, memo, trail),
    do: {root, Enum.reduce(trail, memo, &Map.put(&2, &1, root))}
end
