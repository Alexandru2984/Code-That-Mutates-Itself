defmodule EvolvingMindsWeb.OfflineHTML do
  use EvolvingMindsWeb, :html

  def page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html
      lang="en"
      data-worker-url={"/service-worker?v=" <> EvolvingMindsWeb.OfflineAssets.cache_id()}
    >
      <head>
        <meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#0b1012" />
        <meta name="robots" content={if @offline, do: "noindex, follow", else: "index, follow"} />
        <meta name="description" content={@metadata.description} />
        <title>
          {if @offline, do: "Offline Evolution Lab · Evolving Minds", else: @metadata.title}
        </title>
        <link rel="canonical" href={@metadata.canonical} />
        <meta property="og:type" content="website" /><meta
          property="og:site_name"
          content="Evolving Minds"
        />
        <meta property="og:title" content={@metadata.title} /><meta
          property="og:description"
          content={@metadata.description}
        />
        <meta property="og:url" content={@metadata.canonical} /><meta
          property="og:image"
          content={@metadata.image}
        />
        <meta name="twitter:card" content="summary_large_image" /><meta
          name="twitter:title"
          content={@metadata.title}
        />
        <meta name="twitter:description" content={@metadata.description} /><meta
          name="twitter:image"
          content={@metadata.image}
        />
        <link rel="manifest" href="/manifest.webmanifest" /><link
          rel="icon"
          href={@icon}
          type="image/svg+xml"
        />
        <link rel="stylesheet" href={@css} /><script defer src={@js}>
        </script>
      </head>
      <body>
        <a href="#main-content" class="skip-link">Skip to content</a><EvolvingMindsWeb.LabPage.page offline={
          @offline
        } />
      </body>
    </html>
    """
  end
end
