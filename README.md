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

caravela_live "/dashboard", DashboardLive       # real-time
caravela_rest "/library/books", BookController  # classic CRUD
```

## Status

**Phase B.1 — fork + rename + `Renderer` behaviour.** Only `:live`
mode is implemented today; it mirrors upstream `live_svelte`
behaviour with the modules renamed and a `Renderer` behaviour
introduced as the seam for `:rest`.

See the [phase plan](https://github.com/rsousacode/caravela_plan/blob/master/phoenix/render_modes.md)
for the roadmap.

## Relation to `live_svelte`

CaravelaSvelte is a fork of [live_svelte](https://github.com/woutdp/live_svelte)
by Wout De Puysseleir. See [NOTICE.md](NOTICE.md) for attribution
and [UPSTREAM.md](UPSTREAM.md) for the sync policy.

## License

MIT — see [LICENSE](LICENSE).
