# Caravela integration

`CaravelaSvelte` is the Svelte transport for the
[Caravela](https://github.com/rsousacode/caravela) framework.
Caravela's generators emit controllers, LiveViews, and Svelte
components that plug directly into the helpers described here.

End-user code rarely imports this module — the generator-emitted
code does — but it's safe to reach for when hand-rolling a page
inside a Caravela app.

All helpers live under `CaravelaSvelte.Caravela`.

## Field-access propagation

Caravela's policy DSL compiles to a `compute_field_access/2`
function on each context, returning a map of
`%{field => :read | :write | :hidden}` (or similar) for the
current actor.

`put_field_access/2` assigns that map onto a `Plug.Conn` or
`Phoenix.LiveView.Socket` so the Svelte component receives it as
a prop regardless of transport.

### `:rest`

```elixir
def index(conn, _params) do
  books = Library.list_books()
  field_access = Library.compute_field_access(:book, conn.assigns.current_actor)

  conn
  |> CaravelaSvelte.Caravela.put_field_access(field_access)
  |> CaravelaSvelte.render("BookIndex", %{
       books: books,
       field_access: field_access
     })
end
```

### `:live`

```elixir
def mount(_params, _session, socket) do
  field_access =
    Library.compute_field_access(:book, socket.assigns.current_actor)

  {:ok,
   socket
   |> CaravelaSvelte.Caravela.put_field_access(field_access)
   |> assign(:books, Library.list_books())}
end
```

### Consuming on the client

The component reads `field_access` like any other prop:

```svelte
<script lang="ts">
  type BookFieldAccess = Record<"title" | "isbn" | "price", "read" | "write" | "hidden">

  let { books, field_access }: {
    books: Book[]
    field_access: BookFieldAccess
  } = $props()
</script>

{#if field_access.price === "read"}
  <td>{book.price}</td>
{/if}
```

## Changeset error translation

`errors/1` turns an `Ecto.Changeset` into the exact shape both
`useForm` (REST) and `useLiveForm` (LiveView) expect:

```elixir
def create(conn, %{"book" => attrs}) do
  case Library.create_book(attrs) do
    {:ok, _} ->
      redirect(conn, to: ~p"/library/books")

    {:error, changeset} ->
      conn
      |> put_status(422)
      |> json(%{errors: CaravelaSvelte.Caravela.errors(changeset)})
  end
end
```

Output shape:

```elixir
%{
  title: ["can't be blank"],
  isbn: ["should be at least 3 character(s)"]
}
```

`%{count}`-style placeholders in `Ecto.Changeset` errors are
interpolated from their `opts` (e.g. `min: 3` becomes `"3"` in the
rendered message), so the client receives final display strings.

## SSE real-time with entity topics

Caravela encourages per-entity, per-actor real-time channels so
dashboards only receive patches for data the current user can see.

### `entity_topic/2`

Build the conventional topic string:

```elixir
iex> CaravelaSvelte.Caravela.entity_topic(:book, 42)
"caravela:book:actor:42"

iex> CaravelaSvelte.Caravela.entity_topic("Book")
"caravela:book"
```

Shape: `caravela:<entity>[:actor:<id>]`. Both sides (server
broadcast, client subscribe) derive the same string.

### `broadcast_patch/3`

Publish a JSON Patch on the entity topic:

```elixir
def update(conn, %{"id" => id, "book" => attrs}) do
  actor = conn.assigns.current_actor
  {:ok, book} = Library.update_book(id, attrs)

  CaravelaSvelte.Caravela.broadcast_patch(:book, actor.id, [
    ["replace", "/books/$$#{book.id}/title", book.title]
  ])

  redirect(conn, to: ~p"/library/books/#{book.id}")
end
```

Pass `nil` as the actor to broadcast to every subscriber of the
entity (admin dashboards, audit pages):

```elixir
CaravelaSvelte.Caravela.broadcast_patch(:book, nil, ops)
```

### Client subscription

On the Svelte side, derive the same topic string:

```svelte
<script>
  import { onMount } from "svelte"
  import { subscribe, pageState, currentPage } from "@caravela/svelte/rest"
  import { applyPatch } from "@caravela/svelte"

  let { books, actor_id } = $props()

  onMount(() => {
    const stop = subscribe(`caravela:book:actor:${actor_id}`, (ops) => {
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

## Optional dependencies

`CaravelaSvelte.Caravela` references `Ecto.Changeset` and
`Phoenix.LiveView.Socket`. Both are optional deps. The matching
clauses compile out when the module isn't loaded, so apps that use
only one side (say, pure REST without Ecto) don't pay for the
other.

```elixir
# mix.exs
defp deps do
  [
    {:caravela_svelte, "~> 0.1"},
    {:ecto, ">= 3.0.0"},            # only needed for errors/1
    {:phoenix_live_view, "~> 1.0"}  # only needed for :live mode
  ]
end
```

## Generator integration (in progress)

Caravela 1.0 will ship `mix caravela.gen.live Library Book frontend: :rest`
that emits:

- A controller wired with `put_field_access/2`, `errors/1`, and
  `broadcast_patch/3`.
- A Svelte component with typed `field_access` + entity props and
  a stub `useForm` block.
- Router macro lines (`caravela_rest`, `caravela_live`) according
  to the entity's `frontend:` declaration.

That work is tracked in the
[C.1 phase plan](https://github.com/rsousacode/caravela_plan/blob/master/phoenix/render_modes/phase_c1_generator_integration.md)
and lands in the `caravela` repo; the helpers in this module are
the stable surface the generators will call into.
