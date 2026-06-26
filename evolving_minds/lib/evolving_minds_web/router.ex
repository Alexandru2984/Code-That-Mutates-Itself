defmodule EvolvingMindsWeb.Router do
  use EvolvingMindsWeb, :router

  @secure_browser_headers %{
    "content-security-policy" =>
      "default-src 'self'; " <>
        "base-uri 'self'; " <>
        "connect-src 'self' ws: wss:; " <>
        "font-src 'self' data:; " <>
        "form-action 'self'; " <>
        "frame-ancestors 'none'; " <>
        "img-src 'self' data:; " <>
        "object-src 'none'; " <>
        "script-src 'self'; " <>
        "style-src 'self' 'unsafe-inline'"
  }

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EvolvingMindsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, @secure_browser_headers
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
