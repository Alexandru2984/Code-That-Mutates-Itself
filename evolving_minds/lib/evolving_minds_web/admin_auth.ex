defmodule EvolvingMindsWeb.AdminAuth do
  @moduledoc """
  Basic-auth gate for the admin area.

  Credentials come from `:admin_credentials` config (set from ADMIN_USER /
  ADMIN_PASS in production). When unconfigured, the admin area does not
  exist as far as visitors can tell: it responds 404.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:evolving_minds, :admin_credentials) do
      [username: user, password: pass] when is_binary(user) and is_binary(pass) ->
        Plug.BasicAuth.basic_auth(conn, username: user, password: pass, realm: "Evolving Minds")

      _ ->
        conn
        |> send_resp(:not_found, "Not Found")
        |> halt()
    end
  end
end
