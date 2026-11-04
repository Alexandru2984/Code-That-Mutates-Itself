defmodule EvolvingMindsWeb.ClientIdentity do
  @moduledoc "Derives an opaque budget key, trusting X-Real-IP only from a configured loopback proxy."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts), do: put_session(conn, :visitor_key, key(conn))

  def key(conn) do
    ip =
      if Application.get_env(:evolving_minds, :trust_local_proxy, false) and
           conn.remote_ip in [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}] do
        case get_req_header(conn, "x-real-ip") do
          [value] when byte_size(value) <= 45 ->
            case :inet.parse_address(String.to_charlist(value)) do
              {:ok, ip} -> ip
              _ -> conn.remote_ip
            end

          _ ->
            conn.remote_ip
        end
      else
        conn.remote_ip
      end

    :crypto.hash(:sha256, :erlang.term_to_binary(ip)) |> Base.url_encode64(padding: false)
  end
end
