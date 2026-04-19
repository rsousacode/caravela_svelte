# `:rest` mode reference

`:rest` mode renders Svelte through an Inertia-compatible HTTP
protocol — no persistent WebSocket, one round-trip per navigation.
First loads are full HTML documents; subsequent in-app navigations
are XHR calls returning a JSON page object.

Compatible with Inertia 2.x devtools extensions out of the box.

## Router

```elixir
use CaravelaSvelte.Router

scope "/", MyAppWeb do
  pipe_through :browser

  caravela_rest "/library/books", BookController
end
```

Expands to `Phoenix.Router.resources/2` and tags the dispatched
conn with `private[:caravela_svelte_mode] = :rest`. All
`resources/4` options pass through (`:only`, `:except`, `:as`,
`:param`, `:singleton`).

## Controller

Replace `render/2` with `CaravelaSvelte.render/4`:

```elixir
def index(conn, _params) do
  CaravelaSvelte.render(conn, "BookIndex", %{books: Library.list_books()})
end
```

### Signature

```elixir
CaravelaSvelte.render(conn, component_name, props, opts \\ [])
```

- `component_name` — string matching the Svelte file's relative
  path inside `assets/svelte/`, without the `.svelte` extension.
- `props` — map, serialised to JSON and received by the component.
- `opts`:
  - `:layout` — `fn conn, assigns -> iodata end` wrapping the
    root `<div>` in an HTML layout. Defaults to a minimal shell
    that loads `/assets/app.{js,css}`.
  - `:ssr` — set to `false` to skip SSR (useful in dev or tests).
  - `:version` — override the asset version (default:
    md5 of `priv/static/manifest.json`).
  - `:url` — override the URL stamped on the page object.

### Form submissions

For validation errors, return JSON with `422` and an `errors` map.
The client-side `useForm` picks it up automatically:

```elixir
def create(conn, %{"book" => attrs}) do
  case Library.create_book(attrs) do
    {:ok, _book} ->
      redirect(conn, to: ~p"/library/books")

    {:error, changeset} ->
      conn
      |> put_status(422)
      |> json(%{errors: CaravelaSvelte.Caravela.errors(changeset)})
  end
end
```

## Client runtime

### `initRest({ resolveComponent })`

Boots the `:rest` runtime on pages with `data-mode="rest"`. Safe
to call unconditionally — no-ops on `:live` pages.

### `navigate(url, opts?)`

Imperative SPA navigation. Sends an Inertia-style XHR and swaps
the page without a full reload.

```ts
import { navigate } from "@caravela/svelte/rest"

await navigate("/library/books/42")
```

Options:

| Option | Type | Default | Notes |
|---|---|---|---|
| `method` | `"get" \| "post" \| "put" \| "patch" \| "delete"` | `"get"` | Non-GET sends `data` as JSON. |
| `data` | `Record<string, unknown>` | `{}` | Request body for non-GET. |
| `replace` | `boolean` | `false` | Replace current history entry. |
| `onSuccess` | `(page) => void` | — | Called with the new page object. |
| `onError` | `(errors) => void` | — | Called on 422 with the errors map. |
| `signal` | `AbortSignal` | — | Cancel an in-flight call. |

### `<Link href={...}>`

Anchor component that calls `navigate()` on click and falls back
to a normal anchor on middle-click / ctrl-click:

```svelte
<script>
  import { Link } from "@caravela/svelte/rest"
</script>

<Link href="/library/books">All books</Link>
```

### `useForm({ initial, action, method })`

Reactive form composable. Returns a readable store with `values`,
`errors`, `submitting` plus `submit()`, `change()`, `reset()`.

```svelte
<script>
  import { useForm } from "@caravela/svelte/rest"

  const form = useForm({
    initial: { title: "", isbn: "" },
    action: "/library/books",
    method: "post",
  })
</script>

<input
  value={$form.values.title}
  oninput={(e) => form.change("title", e.currentTarget.value)}
/>
{#if $form.errors.title}
  <span class="err">{$form.errors.title.join(", ")}</span>
{/if}
<button onclick={form.submit} disabled={$form.submitting}>Save</button>
```

### `useNavigate()`

Composable returning a `navigate` function, mostly for Svelte
idiom symmetry with `useForm`. Equivalent to importing `navigate`
directly.

## Real-time with SSE

Opt-in per route:

```elixir
caravela_rest "/dashboard", DashboardController, realtime: true
```

This registers an additional `GET /dashboard/__events` dispatching
to `CaravelaSvelte.SSE`. Server code broadcasts patches over
`Phoenix.PubSub`:

```elixir
CaravelaSvelte.SSE.publish("dashboard:user:#{user.id}", [
  ["replace", "/counter", new_value]
])
```

The client subscribes and applies patches to reactive state:

```svelte
<script>
  import { onMount } from "svelte"
  import { subscribe, pageState, currentPage } from "@caravela/svelte/rest"
  import { applyPatch } from "@caravela/svelte"

  let { counter }: { counter: number } = $props()

  onMount(() => {
    const stop = subscribe(`dashboard:user:42`, (ops) => {
      const page = currentPage()
      if (!page) return
      const nextProps = { ...page.props }
      applyPatch(nextProps, ops)
      pageState.set({ ...page, props: nextProps })
    })
    return stop
  })
</script>
```

### SSE plug options

Pass a keyword list instead of `true` to forward options to the
plug:

```elixir
caravela_rest "/dashboard", DashboardController,
  realtime: [
    heartbeat_ms: 30_000,     # keep-alive comment cadence
    retry_ms: 3_000,          # EventSource auto-reconnect hint
    topic_prefix: "dashboard:" # reject topics that don't start with this
  ]
```

### Polling fallback

Environments that strip streaming (old corporate proxies) can
fall back to polling:

```ts
subscribe("dashboard:user:42", onPatch, {
  refreshInterval: 10_000,   // re-fetch the page every 10s
  forcePolling: true,         // skip the EventSource attempt
})
```

Or poll without any SSE attempt:

```ts
import { poll } from "@caravela/svelte/rest"

const stop = poll(10_000)
```

## Protocol details

### Request classification

A request is `:navigation` when `x-inertia: true` is present, and
`:full_document` otherwise. Navigation responses are JSON page
objects; full-document responses are complete HTML with the page
object embedded in a `data-page` attribute on the root `<div>`.

### Version mismatch

If the client's `x-inertia-version` differs from the server's
asset version (md5 of `priv/static/manifest.json` by default),
the server returns **409 Conflict** with an `x-inertia-location`
header. The client hard-reloads to pick up the new bundle.

Override the version source per-app:

```elixir
# config/config.exs
config :caravela_svelte, :asset_version, fn -> MyApp.build_hash() end
```

### Response headers

- `x-inertia: true` on navigation responses.
- `vary: X-Inertia` so CDNs key separately on the header.
- `x-accel-buffering: no` on SSE responses (nginx hint).

## Non-goals for 1.0

- Partial reloads (`x-inertia-partial-data` / `-component`).
- Lazy / async / deferred props.
- History encryption / `clearHistory`.
- Bidirectional real-time on a `:rest` page — if you need it,
  that page belongs in `:live` mode.
