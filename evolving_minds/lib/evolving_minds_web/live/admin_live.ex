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

    {:ok, socket |> assign(:page_title, "World Administration") |> refresh(),
     layout: {EvolvingMindsWeb.Layouts, :screen}}
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
    case Map.fetch(%{"normal" => :normal, "abundance" => :abundance, "famine" => :famine}, epoch) do
      {:ok, value} ->
        Environment.set_epoch(value)
        {:noreply, socket |> put_flash(:info, "Epoch set to #{epoch}.") |> refresh()}

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid epoch.")}
    end
  end

  @impl true
  def handle_event("spawn", %{"count" => count}, socket) when count in ["1", "5"] do
    results = for _ <- 1..String.to_integer(count), do: World.spawn_entity()
    spawned = Enum.count(results, &match?({:ok, _}, &1))

    {:noreply,
     socket
     |> put_flash(:info, "Spawned #{spawned} minds (population limit applies).")
     |> refresh()}
  end

  @impl true
  def handle_event("kill", %{"kill" => %{"id" => id}}, socket)
      when is_binary(id) and byte_size(id) <= 128 do
    id = String.trim(id)

    case World.terminate_entity(id) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Mind #{id} terminated.") |> refresh()}

      {:error, :not_found} ->
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

  @impl true
  def handle_event(_event, _params, socket),
    do: {:noreply, put_flash(socket, :error, "Invalid command.")}

  defp refresh(socket) do
    socket
    |> assign(:population, length(World.get_all_entities()))
    |> assign(:paused, World.paused?())
    |> assign(:epoch, Environment.current_epoch())
    |> assign(:all_time, EvolvingMinds.AllTimeStats.get_stats())
    |> assign(:operations, EvolvingMindsWeb.OperationalStatus.read())
  end

  defp status_label(:ok), do: "Healthy"
  defp status_label(:stale), do: "Overdue"
  defp status_label(:error), do: "Transfer failed"
  defp status_label(:disabled), do: "Not configured"
  defp status_label(:missing), do: "No record yet"
  defp status_label(_), do: "Check required"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="observatory admin-page">
      <header class="site-header">
        <a href="/" class="brand"><span
          class="brand-mark"
          aria-hidden="true"
        >◎</span><span>Evolving <strong>Minds</strong><small>WORLD ADMINISTRATION</small></span></a><nav aria-label="Administration navigation">
          <a href="/admin/dashboard">LiveDashboard</a><a href="/">← Observatory</a>
        </nav>
      </header>
      <main id="main-content" class="observatory-main admin-main">
        <section class="tree-intro">
          <p class="eyebrow">God mode enabled</p><h1>World Administration</h1><p>
            Manage the shared world and check the safety of its stored history.
          </p>
        </section>
        <section class="world-metrics" aria-label="Simulation status">
          <div>
            <span class="metric-label">Population</span><strong>{@population}<small>/ 50</small></strong><span>living minds</span>
          </div><div>
            <span class="metric-label">Status</span><strong>{if @paused, do: "Paused", else: "Running"}</strong><span>shared simulation</span>
          </div><div>
            <span class="metric-label">Epoch</span><strong>{String.capitalize(to_string(@epoch))}</strong><span>current environment</span>
          </div><div>
            <span class="metric-label">Births / Deaths</span><strong>{@all_time.births}
            <small>/ {@all_time.deaths}</small></strong><span>recorded lives</span>
          </div>
        </section>
        <section class="panel admin-operations" aria-labelledby="operations-heading">
          <div class="section-heading">
            <h2 id="operations-heading">Persistence & recovery</h2><span>freshness checks</span>
          </div><div class="operations-grid">
            <article
              :for={
                {key, label, explanation} <- [
                  {:snapshot, "World snapshot", "Written about every 30 seconds."},
                  {:local_backup, "Local backup", "Verified gzip archive on this VPS."},
                  {:offsite, "Encrypted offsite backup", "Google Drive copy, verified by download."}
                ]
              }
              id={"operation-#{key}"}
            >
              <h3>{label}</h3><strong class={"operation-status status-#{@operations[key].status}"}>{status_label(
                @operations[key].status
              )}</strong><p :if={is_integer(@operations[key].age)}>
                Last {if key == :offsite, do: "verified", else: "written"} {EvolvingMindsWeb.Observatory.age(
                  @operations[key].age
                )} ago
              </p><p :if={is_nil(@operations[key].age)}>No usable timestamp available.</p><small>{explanation}</small>
            </article>
          </div><p class="muted">
            Freshness thresholds: 2 minutes for snapshots, 30 hours for local archives, 8 hours for verified offsite copies. An error or overdue copy needs attention; these checks do not send external alerts.
          </p>
        </section>
        <div class="admin-controls-grid">
          <section class="panel">
            <h2>Simulation controls</h2><p class="muted">
              Pausing freezes actions and reproduction for everyone.
            </p><div class="admin-actions">
              <button :if={!@paused} phx-click="pause" class="button button-quiet">Ⅱ Pause World</button><button
                :if={@paused}
                phx-click="resume"
                class="button button-primary"
              >▶ Resume World</button><button
                phx-click="spawn"
                phx-value-count="1"
                class="button button-quiet"
              >Spawn 1</button><button
                phx-click="spawn"
                phx-value-count="5"
                class="button button-quiet"
              >Spawn 5</button><button phx-click="save_snapshot" class="button button-quiet">Save Snapshot</button>
            </div>
          </section><section class="panel">
            <h2>Choose the environment</h2><p class="muted">
              The new energy cost applies to the whole population.
            </p><div class="admin-actions">
              <button
                :for={epoch <- EvolvingMinds.Environment.epochs()}
                phx-click="set_epoch"
                phx-value-epoch={epoch}
                class={"button #{if epoch == @epoch, do: "button-primary", else: "button-quiet"}"}
                aria-pressed={to_string(epoch == @epoch)}
              >{String.capitalize(to_string(epoch))}</button>
            </div>
          </section>
        </div>
        <section class="panel admin-terminate">
          <h2>Terminate a mind</h2><p class="muted">
            This ends its life in the shared world and records the cause in the ancestry book.
          </p><form id="kill-form" phx-submit="kill">
            <label for="kill-id">Full entity ID</label><div>
              <input
                id="kill-id"
                type="text"
                name="kill[id]"
                maxlength="128"
                required
                placeholder="Full entity id"
              /><button type="submit" class="button button-quiet">Terminate</button>
            </div>
          </form>
        </section>
        <footer class="site-footer">
          <span>EVOLVING MINDS · ADMINISTRATION</span><a href="/">Return to the living world ↗</a>
        </footer>
      </main>
    </div>
    """
  end
end
