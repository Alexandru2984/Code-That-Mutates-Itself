defmodule EvolvingMinds.Snapshot do
  @moduledoc "Validates the complete persisted world before any state is restored."

  @max_bytes 4_000_000
  @actions [:attack, :greet, :share_knowledge]

  def read(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case IO.binread(file, @max_bytes + 1) do
          binary when is_binary(binary) and byte_size(binary) <= @max_bytes -> decode(binary)
          _ -> :corrupt
        end
      after
        File.close(file)
      end
    end
  end

  # Snapshots written by this application are uncompressed. Reject compressed
  # ETF before decoding so an advertised expansion cannot allocate arbitrary RAM.
  defp decode(<<131, 80, _::binary>>), do: :corrupt

  defp decode(binary) do
    snapshot = :erlang.binary_to_term(binary, [:safe])
    if valid?(snapshot), do: {:ok, snapshot}, else: :corrupt
  rescue
    _ -> :corrupt
  end

  defp valid?(
         %{
           version: 1,
           saved_at: %DateTime{},
           epoch: epoch,
           entities: entities,
           memories: memories
         } = snapshot
       ) do
    epoch in [:normal, :abundance, :famine] and
      bounded_list?(entities, 50, &entity?/1) and
      length(Enum.uniq_by(entities, & &1.id)) == length(entities) and
      bounded_list?(memories, 50, &memory?/1) and
      Enum.all?(memories, fn {id, _} -> Enum.any?(entities, &(&1.id == id)) end) and
      bounded_list?(Map.get(snapshot, :ancestry, []), 2000, &ancestor?/1) and
      stats?(Map.get(snapshot, :all_time, %{})) and data?(snapshot, 0)
  end

  defp valid?(_), do: false

  defp entity?(
         %{id: id, traits: %{aggression: aggression, curiosity: curiosity}, energy: energy} = e
       ) do
    id?(id) and trait?(aggression) and trait?(curiosity) and
      is_integer(energy) and energy in 1..100 and
      name?(Map.get(e, :name)) and Map.get(e, :tribe) in [nil, :solari, :umbra] and
      integer?(Map.get(e, :generation, 1), 1) and
      nullable_id?(Map.get(e, :parent_id)) and integer?(Map.get(e, :born_at, 0), 0) and
      integer?(Map.get(e, :kills, 0), 0)
  end

  defp entity?(_), do: false

  defp ancestor?(
         %{
           id: id,
           parent_id: parent,
           generation: generation,
           born_at: born,
           died_at: died,
           cause: cause,
           killer_id: killer
         } = record
       ) do
    id?(id) and nullable_id?(parent) and name?(record[:name]) and
      record[:tribe] in [nil, :solari, :umbra] and integer?(generation, 1) and
      integer?(born, 0) and (is_nil(died) or integer?(died, 0)) and
      cause in [nil, :exhaustion, :killed, :terminated, :crash] and nullable_id?(killer)
  end

  defp ancestor?(_), do: false

  defp memory?({id, memories}) do
    id?(id) and
      bounded_list?(memories, 100, fn
        {action, sender} -> action in @actions and id?(sender)
        _ -> false
      end)
  end

  defp memory?(_), do: false

  defp stats?(stats) when is_map(stats) do
    Enum.all?(
      [:births, :deaths, :mutations, :max_generation],
      &integer?(Map.get(stats, &1, 0), 0)
    ) and
      counters?(Map.get(stats, :deaths_by_cause, %{}), [:killed, :exhaustion, :terminated, :crash]) and
      counters?(Map.get(stats, :interactions, %{}), @actions) and
      tally?(Map.get(stats, :kills_by, %{})) and tally?(Map.get(stats, :children_by, %{})) and
      record?(Map.get(stats, :oldest), :age) and record?(Map.get(stats, :most_feared), :kills) and
      record?(Map.get(stats, :most_prolific), :children)
  end

  defp stats?(_), do: false

  defp counters?(map, keys) when is_map(map) do
    Enum.all?(map, fn {key, value} -> key in keys and integer?(value, 0) end)
  end

  defp counters?(_, _), do: false

  defp tally?(map) when is_map(map) and map_size(map) <= 200 do
    Enum.all?(map, fn
      {id, %{count: count, name: name}} -> id?(id) and integer?(count, 0) and name?(name)
      _ -> false
    end)
  end

  defp tally?(_), do: false
  defp record?(nil, _), do: true

  defp record?(%{id: id} = record, key),
    do: id?(id) and name?(record[:name]) and integer?(record[key], 0)

  defp record?(_, _), do: false

  defp bounded_list?(list, cap, fun),
    do: is_list(list) and length(list) <= cap and Enum.all?(list, fun)

  defp id?(value), do: is_binary(value) and byte_size(value) in 1..128 and String.valid?(value)
  defp nullable_id?(value), do: is_nil(value) or id?(value)

  defp name?(value),
    do: is_nil(value) or (is_binary(value) and byte_size(value) <= 100 and String.valid?(value))

  defp integer?(value, min),
    do: is_integer(value) and value >= min and value <= 9_223_372_036_854_775_807

  defp trait?(value), do: is_float(value) and value >= 0 and value <= 1

  defp data?(_, depth) when depth > 16, do: false
  defp data?(value, _) when is_atom(value) or is_number(value) or is_binary(value), do: true

  defp data?(value, depth) when is_map(value),
    do:
      Enum.all?(Map.to_list(value), fn {k, v} -> data?(k, depth + 1) and data?(v, depth + 1) end)

  defp data?(value, depth) when is_list(value), do: Enum.all?(value, &data?(&1, depth + 1))

  defp data?(value, depth) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.all?(&data?(&1, depth + 1))

  defp data?(_, _), do: false
end
