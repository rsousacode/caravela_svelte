# NOTICE

## Attribution

CaravelaSvelte is a fork of [live_svelte](https://github.com/woutdp/live_svelte),
originally authored by Wout De Puysseleir and contributors. The fork is
distributed under the same MIT license as upstream.

Significant portions of the Elixir and JavaScript code in this
repository originate from live_svelte and are redistributed with
copyright preserved. See [LICENSE](LICENSE) for the full text and
copyright notice.

## Divergence

CaravelaSvelte adds:

- `CaravelaSvelte.Renderer` behaviour — a pluggable render-mode
  abstraction.
- `CaravelaSvelte.Rest` — an Inertia-2.x-compatible HTTP renderer
  (Phase B.2; not yet present at the time of initial fork).
- `CaravelaSvelte.Router` macros for per-route mode selection
  (Phase B.3).
- SSE real-time adapter for `:rest` mode (Phase B.4).

See the parent plan at [docs/render_modes.md](./docs/render_modes.md)
for the full divergence narrative.

## Upstream sync

This fork tracks upstream `live_svelte` for security patches and
bug fixes. The last synced SHA is recorded in
[UPSTREAM.md](./UPSTREAM.md).
