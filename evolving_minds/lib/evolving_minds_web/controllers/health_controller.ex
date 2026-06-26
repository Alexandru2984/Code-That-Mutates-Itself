defmodule EvolvingMindsWeb.HealthController do
  use EvolvingMindsWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
