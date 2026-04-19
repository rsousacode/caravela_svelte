# CaravelaSvelte

**Svelte + Phoenix with pluggable render modes.**

`CaravelaSvelte` lets you mount the same Svelte component over two
different transports, chosen per route:

- **`:live`** — LiveView WebSocket (diff-based, real-time). This is
  today's `live_svelte` story.
- **`:rest`** — Inertia-style HTTP (first-load HTML + SPA navigation
  over JSON). Cacheable, offline-tolerant, no persistent socket.

Same components. Same prop contract. Same SSR pipeline. Same client
bundle. Per-route mode selection.

```elixir
use CaravelaSvelte.Router

caravela_live "/dashboard", DashboardLive                   # real-time (LiveView)
caravela_rest "/library/books", BookController              # classic CRUD
caravela_rest "/metrics", MetricsController, realtime: true # CRUD + SSE push
```

## Documentation

- [Render modes](docs/render_modes.md) — overview + pick-a-mode
  decision tree
- [Getting started](docs/getting_started.md) — installation +
  first page in each mode
- [`:live` mode reference](docs/live.md)
- [`:rest` mode reference](docs/rest.md) — router, controller,
  client helpers, SSE real-time, polling fallback
- [Caravela integration](docs/caravela.md) — field-access,
  changeset errors, entity-scoped SSE topics

## Status

**Phase C.1 — Caravela generator integration.** Transports are
complete: `:live` (LiveView) and `:rest` (Inertia-compatible HTTP)
both ship, router macros (`caravela_live` / `caravela_rest`) pick
per-route, and opt-in SSE real-time for `:rest` is wired. The
caravela_svelte-side enrichment helpers
(`CaravelaSvelte.Caravela`) are live; the matching Caravela
generator templates are the in-progress part of C.1.

See the [phase plan](https://github.com/rsousacode/caravela_plan/blob/master/phoenix/render_modes.md)
for the roadmap.

## Relation to `live_svelte`

CaravelaSvelte is a fork of [live_svelte](https://github.com/woutdp/live_svelte)
by Wout De Puysseleir. See [NOTICE.md](NOTICE.md) for attribution
and [UPSTREAM.md](UPSTREAM.md) for the sync policy.

## License

MIT — see [LICENSE](LICENSE).
