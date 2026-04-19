# `:live` mode reference

`:live` mode mounts a Svelte component inside a Phoenix LiveView.
The server process keeps state; prop changes flow as diffs over
the LiveView WebSocket; DOM updates are minimal.

This is the transport `live_svelte` pioneered. CaravelaSvelte
preserves its behaviour and extends it with a prop-diff
optimisation (changes only) and mode-agnostic client helpers.

## Router

```elixir
use CaravelaSvelte.Router

scope "/", MyAppWeb do
  pipe_through :browser

  caravela_live "/dashboard", DashboardLive
end
```

Expands 1:1 to `Phoenix.LiveView.Router.live/2..4` and tags the
conn with `private[:caravela_svelte_mode] = :live`.

## LiveView

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, counter: 0, books: [])}
  end

  def render(assigns) do
    ~H"""
    <CaravelaSvelte.svelte
      name="Dashboard"
      props={%{counter: @counter, books: @books}}
    />
    """
  end
end
```

## `<CaravelaSvelte.svelte>` attributes

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `name` | `string` (required) | — | Relative path under `assets/svelte/`, no extension. |
| `props` | `map` | `%{}` | Serialised to JSON, received by the component. |
| `ssr` | `boolean` | `true` | Server-render on first mount. |
| `socket` | `Phoenix.LiveView.Socket` | auto | Usually inferred; only needed in edge cases. |
| `class` | `string` | `nil` | Applied to the wrapper `<div>`. |
| `id` | `string` | auto | Stable DOM id. Auto-generated from name + key. |
| `key` | `any` | `nil` | Identity key for stable ids in `{#each}` loops. |
| `diff` | `boolean` | `true` | Send only changed props when possible. Set `false` to always send full props. |

### Prop diffs

When `diff` is `true` (the default) and the config flag
`enable_props_diff` is on, CaravelaSvelte sends a compressed
JSON Patch of prop changes instead of the full prop tree. The
client applies the patch against its existing `$state`.

```elixir
# config/config.exs
config :caravela_svelte, enable_props_diff: true
```

Large flat props (a 1000-row table where only one row changed)
ship a ~100-byte patch instead of the full table. See
[`lib/caravela_svelte/live.ex`](../lib/caravela_svelte/live.ex)
for the diff algorithm.

## Client-side — inside the component

### `useLiveForm`

LiveView-native form composable. Wires `phx-change` / `phx-submit`
and returns reactive `values` / `errors` stores.

```svelte
<script>
  import { useLiveForm } from "@caravela/svelte"

  let { live, form_data, form_errors }: {
    live: any; form_data: any; form_errors: any
  } = $props()

  const form = useLiveForm(live, {
    initial: form_data,
    errors: form_errors,
  })
</script>

<input
  name="title"
  value={$form.values.title}
  onchange={(e) => form.change("title", e.currentTarget.value)}
/>
<button onclick={form.submit}>Save</button>
```

### `useEventReply`

Send an event to the LiveView and await a reply:

```svelte
<script>
  import { useEventReply } from "@caravela/svelte"

  let { live } = $props()
  const pushEvent = useEventReply(live)

  async function save() {
    const { ok } = await pushEvent("save", { title: "..." })
    if (ok) alert("Saved")
  }
</script>
```

### `useLiveUpload`

Wire Phoenix's upload machinery into a Svelte component:

```svelte
<script>
  import { useLiveUpload } from "@caravela/svelte"

  let { live, uploads } = $props()
  const upload = useLiveUpload(live, uploads.avatar)
</script>

<input type="file" onchange={upload.handleFileInput} />
{#each $upload.entries as entry}
  <p>{entry.name} — {entry.progress}%</p>
{/each}
```

### `useLiveConnection`

Observe the LiveView socket's connection state. Useful for
offline banners:

```svelte
<script>
  import { useLiveConnection } from "@caravela/svelte"

  const connection = useLiveConnection()
</script>

{#if $connection === "disconnected"}
  <div class="banner">You're offline — reconnecting…</div>
{/if}
```

### `<Link href={...}>`

Mode-aware link component. In `:live` pages it pushes a navigate
event; in `:rest` pages it calls the REST `navigate`. Same JSX
surface either way.

```svelte
<script>
  import { Link } from "@caravela/svelte"
</script>

<Link href="/library/books">Books</Link>
```

## Slots

`<CaravelaSvelte.svelte>` supports arbitrary HEEx slots that the
Svelte component can render:

```elixir
<CaravelaSvelte.svelte name="Modal">
  <:header>Confirm delete</:header>
  <:body>Are you sure? <.link phx-click="delete">Yes</.link></:body>
</CaravelaSvelte.svelte>
```

```svelte
<script>
  let { header, body } = $props()
</script>

<div class="modal">
  <h2>{@html header}</h2>
  <div>{@html body}</div>
</div>
```

A `<:loading>` slot may be used to show HEEx markup until the
component hydrates, but it is **incompatible with SSR** — set
`ssr={false}` on the component if you use it.

## Streams

Streams work transparently. Pass a Phoenix.LiveView.LiveStream
as a prop and the diff protocol converts inserts / removes / limits
into JSON Patch ops the client applies to the Svelte `$state`
array.

## Non-goals

- `:rest`-style HTTP responses on a LiveView route — for that,
  declare a `caravela_rest` route instead.
- Nested LiveViews inside a Svelte component — use slots or split
  the page.
