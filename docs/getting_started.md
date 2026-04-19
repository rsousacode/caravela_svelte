# Getting started

This walks through installing CaravelaSvelte in a Phoenix app,
wiring the Vite bundle + SSR pool, and rendering one page in each
mode.

## Prerequisites

- Phoenix `~> 1.7`
- `phoenix_live_view ~> 1.0`
- Node.js on the server (for SSR — optional in dev)
- Vite (wired through `phoenix_vite ~> 0.4`)

## Installation

### 1. Add the hex dep

```elixir
# mix.exs
defp deps do
  [
    {:caravela_svelte, "~> 0.1"},
    # ... your other deps
  ]
end
```

### 2. Add the npm package

```json
// package.json
{
  "dependencies": {
    "@caravela/svelte": "^0.1.0"
  }
}
```

Or, during development from a path:

```json
{
  "dependencies": {
    "@caravela/svelte": "file:../caravela_svelte"
  }
}
```

### 3. Wire the Vite plugin

```js
// vite.config.js
import { defineConfig } from "vite"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import caravelaSvelte from "@caravela/svelte/vitePlugin"

export default defineConfig({
  plugins: [svelte(), caravelaSvelte()],
})
```

### 4. Boot the client

The Vite plugin shipped with caravela_svelte exposes a
`virtual:live-svelte-components` module that flattens your
`assets/svelte/**/*.svelte` tree into a component map. Pass it
straight to `getHooks` for `:live` mode, and to `initRest` via a
resolver for `:rest` mode:

```js
// assets/js/app.js
import { getHooks } from "@caravela/svelte"
import { initRest } from "@caravela/svelte/rest"
import Components from "virtual:live-svelte-components"
import { LiveSocket } from "phoenix_live_view"

// :live mode — LiveView hooks
const liveSocket = new LiveSocket("/live", Socket, {
  hooks: getHooks(Components),
})
liveSocket.connect()

// :rest mode — boots on data-mode="rest" pages; no-op otherwise.
initRest({
  resolveComponent: (name) => Components[name],
})
```

The single `app.js` handles both modes. `initRest()` checks the
root element's `data-mode` attribute and only activates when the
page was rendered in `:rest` mode.

> **Alternative — `getHooks` also accepts a `{ resolveComponent }`
> object** from v0.1.1 onward, mirroring `initRest`'s shape:
>
> ```js
> const resolveComponent = (name) => Components[name]
> hooks: getHooks({ resolveComponent })
> ```
>
> Use whichever reads cleaner. `getHooks(Components)` is the
> shortest spelling for apps that use the Vite virtual module.

### 5. Configure PubSub (required for SSE real-time only)

```elixir
# config/config.exs
config :caravela_svelte, pubsub: MyApp.PubSub
```

## First page — `:live`

```elixir
# lib/my_app_web/router.ex
use CaravelaSvelte.Router

scope "/", MyAppWeb do
  pipe_through :browser

  caravela_live "/dashboard", DashboardLive
end
```

```elixir
# lib/my_app_web/live/dashboard_live.ex
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, counter: 0)}
  end

  def handle_event("inc", _, socket) do
    {:noreply, update(socket, :counter, &(&1 + 1))}
  end

  def render(assigns) do
    ~H"""
    <CaravelaSvelte.svelte name="Dashboard" props={%{counter: @counter}} />
    """
  end
end
```

```svelte
<!-- assets/svelte/Dashboard.svelte -->
<script lang="ts">
  import { useEventReply } from "@caravela/svelte"

  let { counter, live }: { counter: number; live: any } = $props()
  const pushEvent = useEventReply(live)
</script>

<p>Counter: {counter}</p>
<button onclick={() => pushEvent("inc", {})}>+</button>
```

## First page — `:rest`

```elixir
# lib/my_app_web/router.ex
scope "/", MyAppWeb do
  pipe_through :browser

  caravela_rest "/library/books", BookController
end
```

```elixir
# lib/my_app_web/controllers/book_controller.ex
defmodule MyAppWeb.BookController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    books = Library.list_books()
    CaravelaSvelte.render(conn, "BookIndex", %{books: books})
  end

  def new(conn, _params) do
    CaravelaSvelte.render(conn, "BookForm", %{book: %{}, errors: %{}})
  end

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
end
```

```svelte
<!-- assets/svelte/BookIndex.svelte -->
<script lang="ts">
  import { Link } from "@caravela/svelte/rest"

  let { books }: { books: Array<{ id: number; title: string }> } = $props()
</script>

<ul>
  {#each books as book}
    <li><Link href={`/library/books/${book.id}`}>{book.title}</Link></li>
  {/each}
</ul>
<Link href="/library/books/new">New book</Link>
```

## Next steps

- Deeper reference by mode: [`:live`](./live.md), [`:rest`](./rest.md).
- Adding real-time updates to a `:rest` page: [real-time with SSE](./rest.md#real-time-with-sse).
- When used from a Caravela app: [Caravela integration](./caravela.md).
- Deciding which mode fits a given page: [render modes](./render_modes.md).
