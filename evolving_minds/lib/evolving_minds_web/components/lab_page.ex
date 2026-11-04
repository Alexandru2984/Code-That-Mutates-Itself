defmodule EvolvingMindsWeb.LabPage do
  use EvolvingMindsWeb, :html

  attr :offline, :boolean, default: false

  def page(assigns) do
    ~H"""
    <div class="observatory">
      <header class="site-header">
        <a href="/" class="brand"><span
          class="brand-mark"
          aria-hidden="true"
        >◎</span><span>Evolving <strong>Minds</strong><small>THE LIVING OBSERVATORY</small></span></a><nav aria-label="Main navigation">
          <a href="/">Observatory</a><a href="/tree">Dynasties</a><a
            href="/lab"
            class="nav-active"
          >Evolution Lab</a>
        </nav><span class="connection-state"><i></i>{if @offline,
          do: "Standalone private lab",
          else: "Your private experiment"}</span>
      </header>
      <main id="main-content" class="observatory-main lab-main">
        <section class="tree-intro">
          <p class="eyebrow">ASK WHAT IF. THEN FIND OUT.</p><h1>Evolution Lab</h1><p>
            Build a world of your own. Change the conditions. Follow the consequences.
          </p><p class="muted">
            A simplified, reproducible model runs privately in this browser. Experiments do not change the shared live world.
          </p>
        </section>
        <aside :if={@offline} class="notice offline-context" aria-labelledby="offline-context-heading">
          <h2 id="offline-context-heading">Your lab works without a connection</h2><p data-offline-state>
            The shared observatory needs a connection. Your experiments and saved library stay available on this device.
          </p><a href="/" class="text-button">Try the live observatory →</a>
        </aside>
        <noscript><style>
          [data-lab-startup] { display:none }
        </style><p class="notice">
          Enable JavaScript to run private experiments, or return to the observatory to see the shared world.
        </p></noscript>
        <p data-lab-startup class="muted" role="status">Preparing your private simulator…</p>
        <div
          id="evolution-lab"
          inert
          aria-busy="true"
        >
          <div class="lab-scenarios" role="group" aria-label="Experiment presets">
            <button data-scenario="balanced"><strong>01 · A delicate balance</strong><span>Mixed personalities, normal resources.</span></button><button data-scenario="cooperation"><strong>02 · Better together</strong><span>Curious minds in a generous world.</span></button><button data-scenario="conflict"><strong>03 · Clash of strategies</strong><span>High aggression. Who survives?</span></button><button data-scenario="survival"><strong>04 · The long famine</strong><span>Scarce resources, rapid mutation.</span></button>
          </div>
          <details class="lab-missions panel" data-missions>
            <summary>Field missions <span>Three guided experiments · local milestones</span></summary>
            <p class="muted">
              Start a mission to build a fresh world. Follow its targets, then change the conditions to discover another strategy. Milestones stay in this browser; they are not a competitive leaderboard.
            </p>
            <div data-mission-list class="mission-list"></div>
            <section data-active-mission hidden class="active-mission" aria-labelledby="mission-title">
              <div class="section-heading">
                <h2 id="mission-title" data-mission-title></h2><button
                  type="button"
                  data-mission-stop
                  class="text-button"
                >Close mission</button>
              </div>
              <div data-mission-targets class="mission-targets"></div>
              <p data-mission-hint class="muted"></p><p data-mission-result class="mission-result">
              </p>
            </section>
          </details>
          <div class="lab-library">
            <div>
              <label class="lab-save-label" for="lab-save-name">Experiment name<input
                id="lab-save-name"
                data-save-name
                type="text"
                maxlength="60"
                placeholder="Name this experiment"
              /></label><button data-action="save" class="button button-quiet">Save in browser</button><button
                data-action="load"
                class="button button-quiet"
              >Load latest save</button><label class="button button-quiet lab-import-label">Import JSON<input
                data-import
                type="file"
                accept="application/json,.json"
                aria-label="Import experiment JSON snapshot"
              /></label>
              <a href="#library-heading" class="button button-quiet">View library ↓</a><button
                type="button"
                data-share-conditions
                class="button button-quiet"
              >Share starting conditions ↗</button>
            </div><div data-share-result hidden class="lab-share-result">
              <label for="lab-share-link">Reproducible starting conditions link</label><input
                id="lab-share-link"
                data-share-link
                type="url"
                readonly
              /><small>This link starts a new world at step zero. Export JSON to share the current snapshot.</small>
            </div><p data-lab-notice class="muted" role="status">
              Save a world here, or import an exported experiment to continue its story.
            </p>
          </div>
          <div class="lab-layout">
            <section class="panel lab-controls" aria-labelledby="controls-heading">
              <h2 id="controls-heading">Set the conditions</h2><form id="lab-config-form">
                <fieldset disabled>
                  <label>Experiment seed<input
                    name="seed"
                    type="text"
                    value="first-light"
                    maxlength="80"
                    autocomplete="off"
                  /><small>The same seed and settings repeat the same experiment.</small></label><label>Starting population
                  <output>24</output><input
                    name="population"
                    type="range"
                    min="2"
                    max="60"
                    step="1"
                    value="24"
                  /></label><label>Aggression
                  <output>50%</output><input
                    name="aggression"
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    value="0.5"
                  /></label><label>Curiosity
                  <output>50%</output><input
                    name="curiosity"
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    value="0.5"
                  /></label><label>Mutation range
                  <output>12%</output><input
                    name="mutation"
                    type="range"
                    min="0"
                    max="0.3"
                    step="0.01"
                    value="0.12"
                  /></label><label>Environment<select name="epoch"><option value="normal">
                    Normal · 5 energy per step
                  </option><option value="abundance">Abundance · 3 energy per step</option><option value="famine">
                    Famine · 8 energy per step
                  </option></select></label><button type="submit" class="button button-primary">↻ Build / reset experiment</button>
                </fieldset>
              </form><p class="muted">
                Conditions apply when you build or reset. Presets start a fresh experiment immediately.
              </p>
            </section>
            <section class="lab-stage" aria-labelledby="lab-map-heading">
              <div class="panel lab-map-panel">
                <div class="section-heading">
                  <h2 id="lab-map-heading">Your population</h2><span>Step
                  <strong data-stat="tick">0</strong></span>
                </div><div class="lab-canvas-wrap">
                  <canvas role="img" aria-label="Private experiment trait map"></canvas>
                </div><div class="map-axis"><span>↑ Curiosity</span><span>Aggression →</span></div><div class="lab-playback">
                  <button data-action="play" class="button button-primary" aria-pressed="false">▶ Run experiment</button><button
                    data-action="step"
                    class="button button-quiet"
                  >One step →</button><label>Speed
                  <input name="speed" type="range" min="1" max="10" value="2" /><output>2×</output></label>
                </div><p data-extinct hidden class="notice">
                  This population became extinct. Change the conditions and build a new experiment.
                </p>
              </div>
              <div class="lab-metrics">
                <div><span>Living minds</span><strong data-stat="population">24</strong></div><div>
                  <span>Mean energy</span><strong><span data-stat="energy">100</span>%</strong>
                </div><div><span>Generation</span><strong data-stat="generation">1</strong></div><div>
                  <span>Births / deaths</span><strong><span data-stat="births">24</span>
                  / <span data-stat="deaths">0</span></strong>
                </div>
              </div>
              <section class="panel lab-inspector">
                <label for="lab-inspect">Inspect a mind</label><select id="lab-inspect" data-inspect><option value="">
                  Choose a mind to inspect
                </option></select><p data-mind-detail class="muted">
                  Select a dot or choose a mind above to inspect its traits.
                </p>
              </section>
            </section>
            <aside class="lab-sidebar">
              <section class="panel">
                <div class="section-heading">
                  <h2>Population over time</h2><span>up to 120 steps</span>
                </div><svg
                  viewBox="0 0 100 100"
                  preserveAspectRatio="none"
                  class="trend-chart"
                  role="img"
                  aria-label="Experiment population history, from zero to sixty minds"
                ><polyline
                  data-lab-chart
                  points="0,60"
                  fill="none"
                  stroke="#b9efd2"
                  stroke-width="2"
                  vector-effect="non-scaling-stroke"
                /></svg><div class="chart-legend">
                  <span class="solari">● Solari <strong data-stat="solari">0</strong></span><span class="umbra">● Umbra
                  <strong data-stat="umbra">0</strong></span>
                </div><dl class="record-counters">
                  <div>
                    <dt>Cooperations</dt><dd data-stat="cooperations">0</dd>
                  </div><div>
                    <dt>Attacks</dt><dd data-stat="attacks">0</dd>
                  </div><div>
                    <dt>Mutations</dt><dd data-stat="mutations">0</dd>
                  </div>
                </dl><button data-action="export" class="text-button">Export experiment JSON ↗</button><button
                  data-action="export_csv"
                  class="text-button"
                >Export history CSV ↗</button>
              </section><section class="panel">
                <h2>Experiment journal</h2><ol data-lab-events class="lab-events">
                  <li>Build a world to begin.</li>
                </ol>
              </section>
            </aside>
          </div>
          <section class="lab-saved panel" aria-labelledby="library-heading">
            <div class="section-heading">
              <h2 id="library-heading">Your experiment library</h2><span data-library-count>0/6</span>
            </div><p class="muted">
              Keep six named snapshots in this browser and compare up to three. Loading a snapshot leaves its saved copy unchanged.
            </p><div class="library-transfer">
              <button type="button" data-entry-action="export_library" class="button button-quiet">Export library</button><label class="button button-quiet lab-import-label">Import library<input
                data-import-library
                type="file"
                accept="application/json,.json"
                aria-label="Import experiment library archive"
              /></label><span class="muted">Up to 2 MB · imports merge, never overwrite saves</span>
            </div>
            <div data-library-problem hidden class="notice" role="alert">
              <h3>Your saved library needs attention</h3><p>
                Download the original data before resetting. The experiment currently open is still available to export as JSON.
              </p><div class="library-transfer">
                <button type="button" data-entry-action="backup_raw" class="button button-quiet">Download original data</button><button
                  type="button"
                  data-entry-action="reset_library"
                  class="button button-quiet"
                >Reset unreadable library</button>
              </div>
            </div>
            <button data-entry-action="undo" data-library-undo hidden class="text-button">↶ Undo last removal</button><p
              data-library-empty
              class="muted"
            >
              No saved experiments yet. Name your current world and save it to begin a collection.
            </p><div data-library-list class="saved-experiment-list"></div><section
              data-saved-comparison
              hidden
              class="saved-comparison"
            >
              <div class="section-heading">
                <h3>Compare saved experiments</h3><button
                  data-entry-action="clear_compare"
                  class="text-button"
                >Clear selection</button>
              </div><div data-comparison-cards class="saved-comparison-cards"></div><svg
                data-comparison-chart
                class="saved-comparison-chart"
                viewBox="0 0 100 100"
                preserveAspectRatio="none"
                role="img"
                aria-label="Population history of selected saved experiments"
              ></svg><p data-comparison-axis class="muted"></p><button
                data-entry-action="export_compare"
                class="text-button"
              >Export comparison CSV ↗</button>
            </section>
          </section>
          <section class="panel lab-method">
            <h2>How this model works</h2><p>
              Each step, minds meet one another and spend energy. Cooperation rewards curiosity; fights drain rivals. Energetic parents reproduce every two steps, passing on slightly changed traits. A world holds at most 60 minds. If none survive, the experiment ends.
            </p><p>
              This sandbox uses a seeded random generator and a simplified economy. It is a learning tool, not a prediction of the shared world. Keep a seed and export your results to compare experiments. Save in this browser or export before leaving. Imported snapshots are validated before your current experiment is replaced.
            </p>
          </section>
        </div>
        <section class="panel offline-tools" aria-labelledby="offline-heading">
          <div class="section-heading">
            <h2 id="offline-heading">Take your lab with you</h2><span data-pwa-mode>Browser edition</span>
          </div>
          <p class="muted">
            Keep the private simulator, missions and saved experiments available without a connection. Live observations need internet.
          </p>
          <div class="library-transfer">
            <button type="button" data-enable-offline class="button button-quiet">Enable offline lab</button><a
              href="/offline"
              class="button button-quiet"
            >Open standalone lab</a><button
              type="button"
              data-install-app
              hidden
              class="button button-primary"
            >Install app</button><button
              type="button"
              data-apply-update
              hidden
              class="button button-quiet"
            >Reload to update</button>
          </div>
          <button type="button" data-remove-offline hidden class="text-button">Remove offline files</button>
          <p data-pwa-status class="muted" role="status">
            Enable offline access while connected. Saved experiments stay in this browser; export a library to transfer them to another device.
          </p>
          <p data-pwa-update-note hidden class="muted">
            An update is ready. Save or export your current experiment before reloading.
          </p>
          <details>
            <summary>Installation and storage</summary><p class="muted">
              In a supported browser, use Install app or your browser's Add to Home Screen option. Browser storage may be cleared by the browser or device; exported library files are your portable backup.
            </p>
          </details>
        </section>
        <footer class="site-footer">
          <span>EVOLVING MINDS · EXPERIMENT, OBSERVE, DISCOVER</span><a href="/">Visit the shared world ↗</a>
        </footer>
      </main>
    </div>
    """
  end
end
