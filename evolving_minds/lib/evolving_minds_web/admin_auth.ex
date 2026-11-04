defmodule EvolvingMindsWeb.AdminAuth do
  @moduledoc """
  Basic-auth gate for the admin area.

  Credentials come from `:admin_credentials` config (set from ADMIN_USER /
  ADMIN_PASS in production). When unconfigured, the admin area does not
  exist as far as visitors can tell: it responds 404.
  """

  import Plug.Conn

  @salt "admin-access-v1"
  @max_age 3600

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:evolving_minds, :admin_credentials) do
      [username: user, password: pass] = credentials
      when is_binary(user) and byte_size(user) > 0 and is_binary(pass) and byte_size(pass) > 0 ->
        if EvolvingMindsWeb.RateLimiter.allow?(
             {:admin_login, EvolvingMindsWeb.ClientIdentity.key(conn)},
             30,
             60_000
           ) do
          conn =
            Plug.BasicAuth.basic_auth(conn,
              username: user,
              password: pass,
              realm: "Evolving Minds"
            )

          if conn.halted do
            conn
          else
            token = Phoenix.Token.sign(EvolvingMindsWeb.Endpoint, @salt, fingerprint(credentials))

            conn
            |> put_resp_header("cache-control", "no-store")
            |> put_resp_header("x-robots-tag", "noindex, nofollow")
            |> put_session(:admin_access, token)
          end
        else
          conn
          |> put_resp_header("retry-after", "60")
          |> send_resp(429, "Too many attempts")
          |> halt()
        end

      _ ->
        conn
        |> send_resp(:not_found, "Not Found")
        |> halt()
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    token = session["admin_access"]

    if authorized?(token) do
      socket = Phoenix.Component.assign(socket, :admin_access, token)

      socket =
        Phoenix.LiveView.attach_hook(socket, :admin_events, :handle_event, fn _event,
                                                                              _params,
                                                                              socket ->
          authorize_socket(socket)
        end)

      socket =
        Phoenix.LiveView.attach_hook(socket, :admin_updates, :handle_info, fn _message, socket ->
          authorize_socket(socket)
        end)

      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  defp authorize_socket(socket) do
    if authorized?(socket.assigns.admin_access) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  defp authorized?(token) when is_binary(token) do
    with [username: user, password: pass] = credentials
         when is_binary(user) and byte_size(user) > 0 and is_binary(pass) and byte_size(pass) > 0 <-
           Application.get_env(:evolving_minds, :admin_credentials),
         {:ok, proof} when is_binary(proof) <-
           Phoenix.Token.verify(EvolvingMindsWeb.Endpoint, @salt, token, max_age: @max_age) do
      Plug.Crypto.secure_compare(proof, fingerprint(credentials))
    else
      _ -> false
    end
  end

  defp authorized?(_), do: false

  defp fingerprint(credentials) do
    :crypto.mac(
      :hmac,
      :sha256,
      EvolvingMindsWeb.Endpoint.config(:secret_key_base),
      :erlang.term_to_binary(credentials)
    )
  end
end
