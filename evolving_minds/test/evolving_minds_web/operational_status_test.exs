defmodule EvolvingMindsWeb.OperationalStatusTest do
  use ExUnit.Case, async: true
  alias EvolvingMindsWeb.OperationalStatus

  setup do
    dir = Path.join(System.tmp_dir!(), "em-operations-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, now: System.system_time(:second)}
  end

  test "fresh files and a verified offsite transfer are healthy", %{dir: dir, now: now} do
    File.write!(Path.join(dir, "world.snapshot"), "snapshot")
    File.write!(Path.join(dir, "world-2026-11-04T104809.123Z.snapshot.gz"), "archive")

    File.write!(
      Path.join(dir, "status.json"),
      Jason.encode!(%{
        version: 1,
        status: "ok",
        last_verified_at: DateTime.from_unix!(now) |> DateTime.to_iso8601()
      })
    )

    assert %{snapshot: %{status: :ok}, local_backup: %{status: :ok}, offsite: %{status: :ok}} =
             OperationalStatus.read(paths(dir), now: now)
  end

  test "stale snapshots and remote failures remain visible without leaking details", %{
    dir: dir,
    now: now
  } do
    File.write!(Path.join(dir, "world.snapshot"), "snapshot")
    File.touch!(Path.join(dir, "world.snapshot"), now - 200)

    File.write!(
      Path.join(dir, "status.json"),
      Jason.encode!(%{
        version: 1,
        status: "error",
        last_verified_at: DateTime.from_unix!(now - 600) |> DateTime.to_iso8601(),
        secret: "never-display"
      })
    )

    result = OperationalStatus.read(paths(dir), now: now)
    assert result.snapshot.status == :stale
    assert result.local_backup.status == :missing
    assert result.offsite == %{status: :error, age: 600}
    refute inspect(result) =~ "never-display"

    File.write!(
      Path.join(dir, "status.json"),
      Jason.encode!(%{version: 1, status: "error", last_verified_at: nil})
    )

    assert OperationalStatus.read(paths(dir), now: now).offsite == %{status: :error, age: nil}
  end

  test "unreadable, oversized and future-dated status data cannot claim a healthy backup", %{
    dir: dir,
    now: now
  } do
    path = Path.join(dir, "status.json")

    for value <- [
          "not-json",
          String.duplicate("x", 5000),
          Jason.encode!(%{
            version: 1,
            status: "ok",
            last_verified_at: DateTime.from_unix!(now + 3600) |> DateTime.to_iso8601()
          })
        ] do
      File.write!(path, value)
      assert OperationalStatus.read(paths(dir), now: now).offsite.status == :invalid
    end

    assert OperationalStatus.read([]).offsite.status == :disabled
  end

  defp paths(dir),
    do: [
      snapshot: Path.join(dir, "world.snapshot"),
      local_backups: dir,
      offsite: Path.join(dir, "status.json")
    ]
end
