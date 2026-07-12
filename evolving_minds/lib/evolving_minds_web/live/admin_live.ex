defmodule EvolvingMindsWeb.AdminLive do
  @moduledoc """
  God-mode panel behind basic auth: pause/resume the world, set the
  epoch, spawn minds, kill a mind by id, and force a snapshot.
  """

  use EvolvingMindsWeb, :live_view

  alias EvolvingMinds.Environment
  alias EvolvingMinds.Persistence
  alias EvolvingMinds.World
  alias EvolvingMindsWeb.WorldPublisher

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: WorldPublisher.subscribe()

    {:ok, refresh(socket), layout: {EvolvingMindsWeb.Layouts, :screen}}
  end

  @impl true
  def handle_info({:world_update, _snapshot}, socket) do
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("pause", _params, socket) do
    World.pause()
    {:noreply, socket |> put_flash(:info, "World paused.") |> refresh()}
  end

  @impl true
  def handle_event("resume", _params, socket) do
    World.resume()
    {:noreply, socket |> put_flash(:info, "World resumed.") |> refresh()}
  end

  @impl true
  def handle_event("set_epoch", %{"epoch" => epoch}, socket) do
    epoch = String.to_existing_atom(epoch)

    if epoch in Environment.epochs() do
      Environment.set_epoch(epoch)
    end

    {:noreply, socket |> put_flash(:info, "Epoch set to #{epoch}.") |> refresh()}
  end

  @impl true
  def handle_event("spawn", %{"count" => count}, socket) do
    count = String.to_integer(count)
    for _ <- 1..count, do: World.spawn_entity()

    {:noreply, socket |> put_flash(:info, "Spawned #{count} minds.") |> refresh()}
  end

  @impl true
  def handle_event("kill", %{"kill" => %{"id" => id}}, socket) do
    id = String.trim(id)

    case Registry.lookup(EvolvingMinds.EntityRegistry, id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(EvolvingMinds.EntitySupervisor, pid)
        {:noreply, socket |> put_flash(:info, "Mind #{id} terminated.") |> refresh()}

      [] ->
        {:noreply, put_flash(socket, :error, "No living mind with id #{id}.")}
    end
  end

  @impl true
  def handle_event("save_snapshot", _params, socket) do
    case Persistence.save_now() do
      :ok -> {:noreply, put_flash(socket, :info, "World snapshot saved.")}
      error -> {:noreply, put_flash(socket, :error, "Snapshot failed: #{inspect(error)}")}
    end
  end

  defp refresh(socket) do
    socket
    |> assign(:population, length(World.get_all_entities()))
    |> assign(:paused, World.paused?())
    |> assign(:epoch, Environment.current_epoch())
    |> assign(:all_time, EvolvingMinds.AllTimeStats.get_stats())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen w-full bg-[#050608] text-slate-300 font-sans p-6 md:p-10">
      <div class="max-w-3xl mx-auto">
        <header class="mb-8 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-black text-white">
              World
              <span class="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-indigo-500">
                Administration
              </span>
            </h1>
            <p class="text-[10px] text-slate-500 font-mono uppercase tracking-[0.3em] mt-1">
              God mode enabled
            </p>
          </div>
          <div class="flex gap-3">
            <a
              href="/admin/dashboard"
              class="px-4 py-2 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 text-[10px] font-black text-slate-400 uppercase tracking-widest"
            >
              LiveDashboard
            </a>
            <a
              href="/"
              class="px-4 py-2 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 text-[10px] font-black text-slate-400 uppercase tracking-widest"
            >
              ← World
            </a>
          </div>
        </header>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <div class="bg-slate-900/40 border border-white/10 rounded-2xl p-4">
            <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">Population</span>
            <span class="text-2xl font-black text-white tabular-nums">{@population}</span>
          </div>
          <div class="bg-slate-900/40 border border-white/10 rounded-2xl p-4">
            <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">Status</span>
            <span class={"text-2xl font-black #{if @paused, do: "text-rose-400", else: "text-emerald-400"}"}>
              {if @paused, do: "Paused", else: "Running"}
            </span>
          </div>
          <div class="bg-slate-900/40 border border-white/10 rounded-2xl p-4">
            <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">Epoch</span>
            <span class="text-2xl font-black text-amber-400 capitalize">{@epoch}</span>
          </div>
          <div class="bg-slate-900/40 border border-white/10 rounded-2xl p-4">
            <span class="text-[8px] text-slate-500 uppercase font-black block mb-1">
              Births / Deaths
            </span>
            <span class="text-2xl font-black text-white tabular-nums">
              {@all_time.births}/{@all_time.deaths}
            </span>
          </div>
        </div>

        <div class="space-y-6">
          <section class="bg-slate-900/40 border border-white/10 rounded-2xl p-6">
            <h2 class="text-[10px] font-black text-slate-400 uppercase tracking-[0.3em] mb-4">
              Simulation
            </h2>
            <div class="flex flex-wrap gap-3">
              <%= if @paused do %>
                <button
                  phx-click="resume"
                  class="px-4 py-2 rounded-xl border border-emerald-500/30 bg-emerald-500/10 hover:bg-emerald-500/20 text-[10px] font-black text-emerald-400 uppercase tracking-widest"
                >
                  Resume World
                </button>
              <% else %>
                <button
                  phx-click="pause"
                  class="px-4 py-2 rounded-xl border border-rose-500/30 bg-rose-500/10 hover:bg-rose-500/20 text-[10px] font-black text-rose-400 uppercase tracking-widest"
                >
                  Pause World
                </button>
              <% end %>
              <button
                phx-click="spawn"
                phx-value-count="1"
                class="px-4 py-2 rounded-xl border border-cyan-500/30 bg-cyan-500/10 hover:bg-cyan-500/20 text-[10px] font-black text-cyan-400 uppercase tracking-widest"
              >
                Spawn 1
              </button>
              <button
                phx-click="spawn"
                phx-value-count="5"
                class="px-4 py-2 rounded-xl border border-cyan-500/30 bg-cyan-500/10 hover:bg-cyan-500/20 text-[10px] font-black text-cyan-400 uppercase tracking-widest"
              >
                Spawn 5
              </button>
              <button
                phx-click="save_snapshot"
                class="px-4 py-2 rounded-xl border border-white/10 bg-white/[0.02] hover:bg-white/10 text-[10px] font-black text-slate-400 uppercase tracking-widest"
              >
                Save Snapshot
              </button>
            </div>
          </section>

          <section class="bg-slate-900/40 border border-white/10 rounded-2xl p-6">
            <h2 class="text-[10px] font-black text-slate-400 uppercase tracking-[0.3em] mb-4">
              Epoch
            </h2>
            <div class="flex flex-wrap gap-3">
              <%= for epoch <- EvolvingMinds.Environment.epochs() do %>
                <button
                  phx-click="set_epoch"
                  phx-value-epoch={epoch}
                  class={"px-4 py-2 rounded-xl border text-[10px] font-black uppercase tracking-widest #{if epoch == @epoch, do: "border-amber-500/50 bg-amber-500/20 text-amber-300", else: "border-white/10 bg-white/[0.02] hover:bg-white/10 text-slate-400"}"}
                >
                  {epoch}
                </button>
              <% end %>
            </div>
          </section>

          <section class="bg-slate-900/40 border border-white/10 rounded-2xl p-6">
            <h2 class="text-[10px] font-black text-slate-400 uppercase tracking-[0.3em] mb-4">
              Terminate a Mind
            </h2>
            <form phx-submit="kill" class="flex gap-3" id="kill-form">
              <input
                type="text"
                name="kill[id]"
                placeholder="Full entity id"
                class="flex-1 h-10 rounded-xl border border-white/10 bg-black/30 px-4 text-sm text-slate-200 placeholder:text-slate-600 focus:border-rose-500/60"
              />
              <button
                type="submit"
                class="px-4 py-2 rounded-xl border border-rose-500/30 bg-rose-500/10 hover:bg-rose-500/20 text-[10px] font-black text-rose-400 uppercase tracking-widest"
              >
                Terminate
              </button>
            </form>
          </section>
        </div>
      </div>
    </div>
    """
  end
end
