# Render modes

CaravelaSvelte ships two transports for the same Svelte components:

| Mode | Transport | Real-time | Cacheable | Best for |
|---|---|---|---|---|
| **`:live`** | LiveView WebSocket | Built-in | No | Dashboards, forms with live validation, collaborative UIs |
| **`:rest`** | Inertia-style HTTP + SPA navigation | Opt-in via SSE | Yes (CDN / Varnish / Service Worker) | CRUD, content-heavy pages, offline-tolerant flows, mobile-friendly traffic |

Both modes render the **same** `.svelte` files through the **same**
SSR pipeline and land in the **same** client bundle. The only thing
that changes is how the server delivers props and how the browser
sends updates back.

## Picking a mode

```
                    ┌─────────────────────────────┐
                    │ Needs bidirectional          │
                    │ real-time? (chat, presence,  │
                    │ shared cursors, live forms)  │
                    └──────────────┬───────────────┘
                                   │
                  ┌────── yes ─────┴──── no ──────┐
                  ▼                               ▼
            Use :live              ┌─────────────────────────────┐
                                   │ Needs HTTP-level caching     │
                                   │ (CDN, Varnish, service       │
                                   │ worker, mobile-friendly)?    │
                                   └──────────────┬───────────────┘
                                                  │
                                   ┌───── yes ────┴──── no ──────┐
                                   ▼                             ▼
                             Use :rest                  Either works — default
                                                        to :live if unsure.
```

Finer-grained tiebreakers:

- **Offline tolerance.** `:rest` pages keep working through flaky
  networks; a closed WebSocket forces reconnection churn on `:live`.
- **Server-push real-time on an otherwise-cacheable page.** Use
  `:rest` with the SSE adapter (see [realtime in `:rest`](./rest.md#real-time-with-sse)).
  One-way updates don't justify a full LiveView socket.
- **Corporate proxies that strip streaming.** `:rest` + the
  polling fallback (`refreshInterval`) will work where SSE and
  WebSockets both fail.
- **CPU-bound server rendering.** `:rest` re-renders the full prop
  tree on every request; `:live` only pushes the diff. High-fanout
  updates hit `:live` harder on the network but lighter on CPU.

## Per-route, not per-project

Modes are declared per-route in the router:

```elixir
use CaravelaSvelte.Router

scope "/", MyAppWeb do
  pipe_through :browser

  caravela_live "/dashboard", DashboardLive            # real-time
  caravela_rest "/library/books", BookController       # CRUD
  caravela_rest "/metrics", MetricsController,
    realtime: true                                     # CRUD + SSE
end
```

A single Caravela app mixes modes freely. Users of the same app
can navigate between `:live` and `:rest` pages and the browser
back button works across the boundary.

## What stays identical across modes

The intent of the fork is that component authors don't branch on
transport:

- **Prop contract.** The server sends the same keys regardless of
  transport. Caravela's domain generator already emits
  mode-agnostic structures (no `%LiveView.Socket{}` leaks).
- **SSR pipeline.** Both modes call
  [`CaravelaSvelte.SSR`](../lib/caravela_svelte/ssr.ex) and reuse
  the same NodeJS pool.
- **Client bundle.** A single `app.js`; the runtime reads the
  `data-mode` attribute on the root element and mounts the right
  boot path.
- **Svelte compiler.** Upstream Svelte via Vite/esbuild —
  unchanged.

## What differs

- `:live` routes dispatch through Phoenix.LiveView.Plug and maintain
  a server-side process per connection. Updates flow over the
  LiveView channel.
- `:rest` routes dispatch through a plain controller. The first
  load returns a full HTML document; subsequent navigations
  driven by the client runtime (`navigate`, `useForm`, `<Link>`)
  go over Inertia-compatible JSON.
- `:rest` pages opt into real-time via `realtime: true`, which
  registers an SSE endpoint the client subscribes to via
  [`subscribe()`](./rest.md#real-time-with-sse).

## Further reading

- [Getting started](./getting_started.md) — installation + first
  page in each mode.
- [`:live` mode reference](./live.md).
- [`:rest` mode reference](./rest.md) (includes SSE real-time).
- [Caravela integration](./caravela.md) — field-access, changeset
  errors, entity-scoped SSE topics.
