# Changelog

All notable changes to this project are documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.1] — 2026-04-19

*First-run-friction pass driven by [bug_improvements_3.md](https://github.com/rsousacode/caravela-plan/blob/main/reviews/bug_improvements_3.md)
§2.1 and the npm-name audit it triggered. Every bug a fresh user
following the docs would hit on first mount.*

### Fixed

- **`getHooks({ resolveComponent })` silently failed at first
  mount** (bug_improvements_3 §2.1). The getting-started doc
  taught `getHooks({ resolveComponent })` but the implementation
  only recognised the pre-built `{ [name]: Component }` map and
  the Vite glob shape — passing an object with a function
  resolver fell through `normalizeComponents` unchanged, then
  `components[componentName]` returned `undefined` and the hook
  threw `"Unable to find <name> component."` on the very first
  render.

  v0.1.1 teaches `getHooks/1` to accept
  `{ resolveComponent: (name) => Component }` as a first-class
  third shape, mirroring what `initRest/1` already accepted.
  Apps can now use one loader pattern across both runtimes, or
  pass `Components` straight to `getHooks` for the shortest
  spelling.

- **Installer wrote the unscoped npm name `"caravela_svelte"`**
  while every doc example used the scoped `"@caravela/svelte"`
  that [package.json](package.json) actually publishes. Fresh
  users who ran `mix igniter.install caravela_svelte`, then
  followed the docs, hit import errors because the alias the
  installer wrote didn't match what the docs taught. The
  installer now emits `"@caravela/svelte"` across
  `package.json`, `vite.config.mjs`'s `optimizeDeps.include` and
  plugin import, `app.js`, and `server.js`. Old imports
  (`"caravela_svelte"`) are still recognised as the "already
  configured" marker, so re-running the task on an upgraded
  project is a no-op instead of a duplicate-write.

- **`applyPatch` was referenced in
  [docs/rest.md](docs/rest.md#L172) but not exported from the
  package entry point.** SSE subscribers following the
  documented pattern hit `SyntaxError: ...applyPatch is not a
  function`. Now re-exported from [index.ts](assets/js/caravela_svelte/index.ts).

### Changed

- **`CaravelaSvelte` moduledoc** no longer talks about "Phase B.1
  / B.2" — v0.1.0 shipped both renderers simultaneously; the
  phase labels were an artefact of the pre-release plan. Updated
  to describe the actual v0.1+ surface: `svelte/1` for `:live`
  mode, `render/3,4` for `:rest` mode, shared component tree.

- **[docs/getting_started.md](docs/getting_started.md)** §4 was
  rewritten to match the working pattern. Primary example uses
  `import Components from "virtual:live-svelte-components"` +
  `getHooks(Components)` (matches the installer's output); the
  `{ resolveComponent }` alternative is shown as a secondary
  style for apps that want one shape across `getHooks` and
  `initRest`.

### Added

- **Regression test** (`test/caravela_svelte/installer_npm_name_test.exs`)
  that reads the installer source and asserts every emitted
  import / package-key uses `@caravela/svelte`. Stops the npm-
  name drift from recurring.

- **Vitest test** (`assets/js/caravela_svelte/hooks.test.ts`)
  covering all three component input shapes for `getHooks/1`.
  Not yet wired into the default CI matrix (which runs
  `mix test` only); captures intent for when Vitest lands in
  CI.

## [0.1.0] — 2026-04-19

First public release. Fork of [live_svelte](https://github.com/woutdp/live_svelte)
renamed to `CaravelaSvelte` with a `Renderer` behaviour split
and two concrete transports.

### Added

- **`CaravelaSvelte.Renderer` behaviour** — seam that lets the
  library ship multiple transports behind a single
  `<CaravelaSvelte.svelte>` component.
- **`:live` mode** (`CaravelaSvelte.Live`) — LiveView WebSocket
  transport. Mirrors the upstream `live_svelte` behaviour with
  modules renamed. Includes prop-diff optimisation that ships
  only changed keys across updates.
- **`:rest` mode** (`CaravelaSvelte.Rest`) — Inertia-compatible
  HTTP transport. First-load HTML + SPA navigation over JSON.
  Handles `x-inertia` / `x-inertia-version` headers and 409
  version-mismatch responses.
- **Router macros** (`CaravelaSvelte.Router`) — `caravela_live`
  and `caravela_rest` to declare per-route modes:

  ```elixir
  caravela_live "/dashboard", DashboardLive
  caravela_rest "/library/books", BookController
  caravela_rest "/metrics", MetricsController, realtime: true
  ```

- **SSE real-time adapter** (`CaravelaSvelte.SSE`) — one-way
  server → client push of JSON-Patch ops via `Phoenix.PubSub`.
  Opt-in per route via `realtime: true`. Heartbeats,
  auto-reconnect, and a polling fallback.
- **Client helpers under `@caravela/svelte`**:
  - `getHooks`, `useLiveForm`, `useEventReply`, `useLiveUpload`,
    `useLiveConnection`, `<Link>` — for `:live` pages.
  - `initRest`, `navigate`, `<Link>`, `useForm`, `useNavigate`,
    `subscribe`, `poll`, `pageState`, `currentPage` — for
    `:rest` pages, under `@caravela/svelte/rest`.
- **Caravela enrichment helpers** (`CaravelaSvelte.Caravela`):
  - `put_field_access/2` — assign a `field_access` map onto a
    conn or LiveView socket.
  - `errors/1` — translate an `Ecto.Changeset` to the
    `%{field => [msg, ...]}` shape `useForm` / `useLiveForm`
    consume.
  - `entity_topic/2` + `broadcast_patch/3` — conventional SSE
    topic format for entity-scoped real-time.
- **Documentation** — five guides under [`docs/`](docs/):
  render modes, getting started, `:live` reference, `:rest`
  reference, Caravela integration.
- **GitHub Actions** — CI (format, compile, test), GitHub Pages
  docs deploy, and Hex release on `v*.*.*` tags.

### Relation to upstream

See [UPSTREAM.md](UPSTREAM.md) for the fork's sync policy and
[NOTICE.md](NOTICE.md) for attribution.

[0.1.0]: https://github.com/rsousacode/caravela_svelte/releases/tag/v0.1.0
