defmodule EvolvingMindsWeb.PublicAccess do
  @moduledoc "Limits connected mounts and UI events before their expensive handlers run."
  import Phoenix.LiveView
  alias EvolvingMindsWeb.RateLimiter

  def on_mount(:throttle, _params, session, socket) do
    key = session["visitor_key"]

    if connected?(socket) and
         (not is_binary(key) or not RateLimiter.allow?({:public_mount, key}, 30, 60_000)) do
      {:halt, redirect(socket, to: "/")}
    else
      socket =
        attach_hook(socket, :public_events, :handle_event, fn _, _, socket ->
          if RateLimiter.allow?({:ui_events, key}, 80, 10_000),
            do: {:cont, socket},
            else: {:halt, put_flash(socket, :error, "Please slow down and try again shortly.")}
        end)

      {:cont, socket}
    end
  end
end
