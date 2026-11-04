defmodule EvolvingMindsWeb.DiscoveryControllerTest do
  use EvolvingMindsWeb.ConnCase, async: true

  test "robots points to the real sitemap and excludes operational paths", %{conn: conn} do
    body = conn |> get("/robots.txt") |> response(200)
    assert body =~ "Disallow: /admin/"
    assert body =~ "Disallow: /live/"
    assert body =~ "Sitemap: #{EvolvingMindsWeb.Endpoint.url()}/sitemap.xml"
  end

  test "sitemap lists only indexable canonical product pages", %{conn: conn} do
    body = conn |> get("/sitemap.xml") |> response(200)
    assert body =~ "#{EvolvingMindsWeb.Endpoint.url()}/tree</loc>"
    refute body =~ "/admin"
    refute body =~ "?mind="
  end

  test "canonical and social metadata use the configured host, not request input", %{conn: conn} do
    conn = %{conn | host: "untrusted.example"}
    html = conn |> get("/tree") |> html_response(200)
    assert html =~ ~s(rel="canonical" href="#{EvolvingMindsWeb.Endpoint.url()}/tree")
    assert html =~ "Dynasties &amp; Genealogy"
    assert html =~ "summary_large_image"
    refute html =~ "untrusted.example"
  end

  test "admin metadata prohibits indexing", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Basic " <> Base.encode64("admin:secret"))
      |> get("/admin/world")

    assert html_response(conn, 200) =~ ~s(name="robots" content="noindex, nofollow")
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
  end
end
