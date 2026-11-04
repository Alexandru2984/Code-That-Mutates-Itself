defmodule EvolvingMindsWeb.HealthController do
  use EvolvingMindsWeb, :controller

  def show(conn, _params) do
    ready =
      Enum.all?(
        [
          EvolvingMinds.EntitySupervisor,
          EvolvingMinds.StateStore,
          EvolvingMinds.Memory,
          EvolvingMinds.Persistence,
          EvolvingMindsWeb.RateLimiter
        ],
        &is_pid(Process.whereis(&1))
      ) and EvolvingMindsWeb.WorldPublisher.ready?()

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(if ready, do: 200, else: 503)
    |> json(%{status: if(ready, do: "ok", else: "unavailable")})
  end
end
