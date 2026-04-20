defmodule EvolvingMindsWeb.Router do
  use EvolvingMindsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EvolvingMindsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EvolvingMindsWeb do
    pipe_through :browser

    live "/", WorldLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", EvolvingMindsWeb do
  #   pipe_through :api
  # end
end
