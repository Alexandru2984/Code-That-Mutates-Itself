defmodule EvolvingMindsWeb.OfflineController do
  use EvolvingMindsWeb, :controller
  alias EvolvingMindsWeb.{Endpoint, OfflineAssets, OfflineHTML}

  @worker_path Path.expand("../../../assets/js/service_worker.js", __DIR__)
  @external_resource @worker_path
  @worker File.read!(@worker_path)

  def show(conn, _) do
    # This document deliberately has no session, visitor identity, CSRF token or LiveView bootstrap.
    offline = conn.request_path == "/offline"

    html =
      OfflineHTML.page(%{
        offline: offline,
        metadata: EvolvingMindsWeb.Layouts.metadata(%{conn | request_path: "/lab"}),
        icon: Endpoint.static_path("/images/favicon.svg"),
        css: Endpoint.static_path("/assets/app.css"),
        js: Endpoint.static_path("/assets/offline_lab.js")
      })

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "public, max-age=0, must-revalidate, no-transform")
    |> put_resp_header("x-robots-tag", if(offline, do: "noindex, follow", else: "index, follow"))
    |> put_resp_header("x-offline-shell", if(offline, do: "1", else: "0"))
    |> put_resp_header("x-offline-version", OfflineAssets.cache_id())
    |> send_resp(200, Phoenix.HTML.Safe.to_iodata(html))
  end

  def worker(conn, _) do
    script =
      @worker
      |> String.replace("__OFFLINE_RESOURCES__", Jason.encode!(OfflineAssets.resources()))
      |> String.replace("__OFFLINE_CACHE__", Jason.encode!(OfflineAssets.cache_id()))

    conn
    |> put_resp_content_type("application/javascript")
    |> put_resp_header("cache-control", "no-cache, no-transform")
    |> put_resp_header("service-worker-allowed", "/")
    |> send_resp(200, script)
  end

  def manifest(conn, _) do
    conn
    |> put_resp_content_type("application/manifest+json")
    |> put_resp_header("cache-control", "public, max-age=0, must-revalidate, no-transform")
    |> send_resp(200, Jason.encode!(OfflineAssets.manifest()))
  end
end
