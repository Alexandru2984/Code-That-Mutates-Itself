defmodule EvolvingMindsWeb.DiscoveryController do
  use EvolvingMindsWeb, :controller

  def robots(conn, _) do
    base = EvolvingMindsWeb.Endpoint.url()

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(
      200,
      "User-agent: *\nAllow: /\nDisallow: /admin/\nDisallow: /api/\nDisallow: /live/\nDisallow: /healthz\nSitemap: #{base}/sitemap.xml\n"
    )
  end

  def sitemap(conn, _) do
    base =
      EvolvingMindsWeb.Endpoint.url()
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(
      200,
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?><urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\"><url><loc>#{base}/</loc></url><url><loc>#{base}/tree</loc></url></urlset>"
    )
  end
end
