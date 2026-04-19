# Changelog

All notable changes to this project are documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

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
