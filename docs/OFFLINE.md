# Offline lab and installation

`/lab` is a stateless page running the private simulator directly in the browser.
It does not open a LiveView socket, fetch a visitor session or render a CSRF token.
The observatory and genealogy remain live Phoenix views. `/offline` renders the
same workspace with an explicit explanation that live observations need internet.

## User flow

1. Open the lab while connected and choose **Enable offline lab**.
2. Wait for **Offline ready**, then use the lab after a reload without a connection.
3. Use **Install app** when offered, or the browser's Add to Home Screen menu.
4. Save named experiments and export the library for transfer or a portable backup.
5. **Remove offline files** unregisters this worker and deletes only this app's
   offline caches. The saved library remains in browser storage.

The current working experiment has a separate per-tab sessionStorage checkpoint.
World state, random stream, name, speed and mission recover paused after a reload.
Shared condition links always start at step zero on first opening; after an actual
change and successful checkpoint, their parameters are removed from the address
so a reload resumes that working session. Corrupt recovery is preserved until an
explicit reset. This per-tab checkpoint is not a portable or permanent backup.

The install prompt depends on the browser/platform. Storage can be cleared by the
browser or the owner of the device; availability is not a substitute for exporting
important experiments. No background notifications or accounts are introduced.

## Cache boundary

The service worker precaches exactly seven public resources: a dedicated stateless
HTML shell, the lab JavaScript bundle, CSS, favicon, two installation icons and the
manifest. Requests use credentials:omit and reject redirects, failed responses,
unexpected content types, files over 1 MB and downloads taking more than 15 seconds.
The shell must carry the matching version marker and must not contain a CSRF or
LiveView session/static token. The URLs are generated exclusively from server-owned
static paths. Each cache version includes compiled page/controller and asset hashes.

Public navigations use the network first and may fall back to the offline lab when
the network fails or the backend returns 5xx. Live HTML is never stored in the
service worker cache. Admin paths, API responses, health checks, other origins and
non-GET requests keep normal networking behavior. Missing live data is not replaced
by a cached world. The private simulator's localStorage library is independent from
CacheStorage; removing offline assets does not delete experiments or preferences.

A new worker waits for the current one to retire. The user may explicitly reload
to apply an update after saving or exporting the current experiment. Activation
cleans only caches with the evolving-minds-offline- prefix. No forced update/reload
is triggered merely by visiting the lab.

## Production and verification

The lab and offline shell use the application's strict CSP and receive no Nginx
analytics transformation. The canonical worker URL has no static-file extension and includes a server-owned
version query. It is served with browser/CDN no-store directives and updateViaCache:none.
This avoids the four-hour browser TTL that was observed rewriting the original .js
endpoint at Cloudflare. The legacy .js route remains only for existing registrations.
See [Cloudflare browser TTL](https://developers.cloudflare.com/cache/how-to/edge-browser-cache-ttl/)
and [CDN cache controls](https://developers.cloudflare.com/cache/concepts/cdn-cache-control/). The offline shell is noindex and canonicalizes to /lab; it is not added to
the sitemap. The main lab retains canonical and social metadata.

Controller tests verify stateless, visitor-independent documents and resource
contracts. Chromium tests enable caching, inspect its exact contents, load real
admin/API responses without caching them, reload offline, operate and load saved
worlds, and remove offline files while preserving the library. The public HTTP
verification script checks the deployed manifest, worker, shell and lab headers.

Sources: [service worker lifecycle](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API/Using_Service_Workers),
[installation UI](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/How_to/Trigger_install_prompt).
