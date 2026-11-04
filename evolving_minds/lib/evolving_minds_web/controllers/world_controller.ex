defmodule EvolvingMindsWeb.WorldController do
  use EvolvingMindsWeb, :controller

  alias EvolvingMindsWeb.{ClientIdentity, RateLimiter, WorldPublisher}

  def export(conn, _params) do
    if RateLimiter.allow?({:export, ClientIdentity.key(conn)}, 30, 60_000) do
      snapshot = WorldPublisher.current_snapshot()

      entities =
        Enum.map(
          snapshot.entities,
          &Map.take(&1, [
            :id,
            :name,
            :tribe,
            :traits,
            :energy,
            :generation,
            :parent_id,
            :born_at,
            :kills
          ])
        )

      conn
      |> put_resp_header("content-disposition", ~s(attachment; filename="evolving-minds.json"))
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> json(%{
        version: 1,
        exported_at: DateTime.utc_now(),
        epoch: snapshot.epoch,
        summary: EvolvingMindsWeb.Observatory.summary(entities),
        entities: entities,
        statistics: snapshot.stats,
        records: snapshot.all_time
      })
    else
      conn
      |> put_status(429)
      |> put_resp_header("retry-after", "60")
      |> json(%{error: "Rate limit reached"})
    end
  end
end
