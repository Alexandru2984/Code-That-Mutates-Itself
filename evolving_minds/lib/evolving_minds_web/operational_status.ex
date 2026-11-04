defmodule EvolvingMindsWeb.OperationalStatus do
  @moduledoc "Read-only freshness checks; exposes no credentials or detailed transfer logs."

  def read(paths \\ Application.get_env(:evolving_minds, :operational_paths, []), opts \\ []) do
    now = Keyword.get(opts, :now, System.system_time(:second))

    %{
      snapshot: file_status(paths[:snapshot], now, 120),
      local_backup: latest_backup(paths[:local_backups], now),
      offsite: offsite_status(paths[:offsite], now)
    }
  end

  defp file_status(nil, _, _), do: %{status: :disabled, age: nil}

  defp file_status(path, now, max_age) do
    case File.stat(path, time: :posix) do
      {:ok, %{type: :regular, size: size, mtime: modified}} when size > 0 ->
        case age(now, modified) do
          nil -> %{status: :invalid, age: nil}
          seconds -> %{status: if(seconds <= max_age, do: :ok, else: :stale), age: seconds}
        end

      _ ->
        %{status: :missing, age: nil}
    end
  end

  defp latest_backup(nil, _), do: %{status: :disabled, age: nil}

  defp latest_backup(directory, now) do
    case File.ls(directory) do
      {:ok, names} ->
        names
        |> Enum.filter(
          &Regex.match?(~r/^world-\d{4}-\d{2}-\d{2}T\d{6}(?:\.\d+)?Z\.snapshot\.gz$/, &1)
        )
        |> Enum.flat_map(fn name ->
          case File.lstat(Path.join(directory, name), time: :posix) do
            {:ok, %{type: :regular, mtime: modified, size: size}} when size > 0 ->
              [{modified, name}]

            _ ->
              []
          end
        end)
        |> Enum.max(fn -> nil end)
        |> case do
          nil -> %{status: :missing, age: nil}
          {_, name} -> file_status(Path.join(directory, name), now, 30 * 3600)
        end

      _ ->
        %{status: :missing, age: nil}
    end
  end

  defp offsite_status(nil, _), do: %{status: :disabled, age: nil}

  defp offsite_status(path, now) do
    with {:ok, %{type: :regular, size: size}} when size <= 4096 <- File.stat(path),
         {:ok, binary} <- bounded_read(path),
         {:ok, %{"version" => 1, "status" => status, "last_verified_at" => verified}}
         when status in ["ok", "error"] and is_binary(verified) <- Jason.decode(binary),
         {:ok, date, _} <- DateTime.from_iso8601(verified),
         seconds when is_integer(seconds) <- age(now, DateTime.to_unix(date)) do
      %{
        status:
          cond do
            status == "error" -> :error
            seconds > 8 * 3600 -> :stale
            true -> :ok
          end,
        age: seconds
      }
    else
      {:ok, %{"version" => 1, "status" => "error", "last_verified_at" => nil}} ->
        %{status: :error, age: nil}

      {:error, :enoent} ->
        %{status: :missing, age: nil}

      _ ->
        %{status: :invalid, age: nil}
    end
  end

  defp bounded_read(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case IO.binread(file, 4097) do
          binary when is_binary(binary) and byte_size(binary) <= 4096 -> {:ok, binary}
          _ -> {:error, :invalid}
        end
      after
        File.close(file)
      end
    end
  end

  defp age(now, timestamp) when timestamp <= now + 300, do: max(now - timestamp, 0)
  defp age(_, _), do: nil
end
