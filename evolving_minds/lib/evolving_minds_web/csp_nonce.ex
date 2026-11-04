defmodule EvolvingMindsWeb.CSPNonce do
  @moduledoc "Authorizes LiveDashboard's own inline bootstrap scripts per response."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if String.starts_with?(conn.request_path, "/admin/dashboard") do
      nonce = Base.encode64(:crypto.strong_rand_bytes(24))
      [policy] = get_resp_header(conn, "content-security-policy")
      policy = String.replace(policy, "script-src 'self';", "script-src 'self' 'nonce-#{nonce}';")
      conn |> assign(:csp_nonce, nonce) |> put_resp_header("content-security-policy", policy)
    else
      conn
    end
  end
end
