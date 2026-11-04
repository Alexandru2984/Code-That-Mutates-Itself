defmodule EvolvingMindsWeb.OfflineAssets do
  @moduledoc "An explicit, versioned cache allowlist. Public live HTML and admin data never enter it."
  alias EvolvingMindsWeb.Endpoint

  def resources do
    [
      %{url: "/offline", kind: "shell"},
      %{url: Endpoint.static_path("/assets/app.css"), kind: "style"},
      %{url: Endpoint.static_path("/assets/offline_lab.js"), kind: "script"},
      %{url: Endpoint.static_path("/images/favicon.svg"), kind: "image"},
      %{url: Endpoint.static_path("/images/app-icon-192.png"), kind: "image"},
      %{url: Endpoint.static_path("/images/app-icon-512.png"), kind: "image"},
      %{url: "/manifest.webmanifest", kind: "manifest"}
    ]
  end

  def cache_id do
    source = [
      Jason.encode!(resources()),
      __MODULE__.module_info(:md5),
      EvolvingMindsWeb.LabPage.module_info(:md5),
      EvolvingMindsWeb.OfflineHTML.module_info(:md5),
      EvolvingMindsWeb.OfflineController.module_info(:md5)
    ]

    digest = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower) |> String.slice(0, 24)
    "evolving-minds-offline-v1-" <> digest
  end

  def manifest do
    %{
      id: "/",
      name: "Evolving Minds",
      short_name: "Minds",
      lang: "en",
      description:
        "Explore a living digital world and run private artificial-life experiments offline.",
      start_url: "/lab",
      scope: "/",
      display: "standalone",
      background_color: "#0b1012",
      theme_color: "#0b1012",
      icons:
        for(
          size <- [192, 512],
          do: %{
            src: Endpoint.static_path("/images/app-icon-#{size}.png"),
            sizes: "#{size}x#{size}",
            type: "image/png",
            purpose: "any maskable"
          }
        ),
      shortcuts: [%{name: "Private lab", url: "/lab"}, %{name: "Live observatory", url: "/"}]
    }
  end
end
