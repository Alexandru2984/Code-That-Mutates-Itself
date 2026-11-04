defmodule EvolvingMindsWeb.Router do
  use EvolvingMindsWeb, :router

  import Phoenix.LiveDashboard.Router

  @secure_browser_headers %{
    "content-security-policy" =>
      "default-src 'self'; " <>
        "base-uri 'self'; " <>
        "connect-src 'self'; " <>
        "font-src 'self' data:; " <>
        "form-action 'self'; " <>
        "frame-ancestors 'none'; " <>
        "img-src 'self' data:; " <>
        "object-src 'none'; " <>
        "script-src 'self'; " <>
        "style-src 'self' 'unsafe-inline'",
    "permissions-policy" => "camera=(), microphone=(), geolocation=()",
    "x-frame-options" => "DENY"
  }

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug EvolvingMindsWeb.ClientIdentity
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

    live_session :public do
      live "/", WorldLive
      live "/tree", TreeLive
    end
  end

  scope "/", EvolvingMindsWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
    get "/api/world", WorldController, :export
  end

  pipeline :admin do
    plug EvolvingMindsWeb.AdminAuth
  end

  scope "/admin" do
    pipe_through [:browser, :admin]

    live_session :admin, on_mount: [{EvolvingMindsWeb.AdminAuth, :require_admin}] do
      live "/world", EvolvingMindsWeb.AdminLive
    end

    live_dashboard "/dashboard",
      metrics: EvolvingMindsWeb.Telemetry,
      on_mount: [{EvolvingMindsWeb.AdminAuth, :require_admin}]
  end
end
