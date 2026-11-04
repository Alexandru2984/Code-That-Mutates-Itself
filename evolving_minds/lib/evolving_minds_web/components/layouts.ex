defmodule EvolvingMindsWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use EvolvingMindsWeb, :controller` and
  `use EvolvingMindsWeb, :live_view`.
  """
  use EvolvingMindsWeb, :html

  embed_templates "layouts/*"

  def metadata(conn) do
    base = EvolvingMindsWeb.Endpoint.url()
    path = if conn.request_path == "/tree", do: "/tree", else: "/"

    {title, description} =
      if path == "/tree" do
        {"Dynasties & Genealogy",
         "Explore the ancestry of a living digital world. Follow parent-child lineages, discover tribes, and search the lives of autonomous minds."}
      else
        {"Live Artificial Life Observatory",
         "Watch digital minds cooperate, compete, inherit traits and evolve. Explore a persistent artificial-life simulation with live traits, lineages, watchlists and comparisons."}
      end

    %{
      title: title <> " · Evolving Minds",
      description: description,
      canonical: base <> path,
      image: base <> "/images/social-card.png",
      robots:
        if(String.starts_with?(conn.request_path, "/admin"),
          do: "noindex, nofollow",
          else: "index, follow"
        )
    }
  end
end
