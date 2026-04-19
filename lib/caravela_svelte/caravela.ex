defmodule CaravelaSvelte.Caravela do
  @moduledoc """
  Integration surface for Caravela-generated apps.

  The generators shipped by the `caravela` framework stitch
  controllers, LiveViews, and Svelte components together. The
  helpers in this module exist so generated code can do the
  glue in one line instead of re-deriving it in every template:

    * `put_field_access/2` — attach the entity's `field_access`
      map to a conn or LiveView socket so it lands as a prop on
      the Svelte component under both `:rest` and `:live` modes.
    * `errors/1` — translate an `Ecto.Changeset` into the
      `%{field => [msg, ...]}` shape consumed by `useForm` (REST)
      and `useLiveForm` (LiveView).
    * `broadcast_patch/2` / `entity_topic/2` — publish a
      JSON-Patch on the conventional topic for a Caravela entity
      + actor pair, for SSE real-time pages.

  Caravela's generators are expected to call these helpers at
  well-known points; end-user code rarely touches the module
  directly, though it's safe to.

  `Ecto` and `Phoenix.LiveView` are optional dependencies. Their
  clauses are compiled out when the module is missing.
  """

  @doc """
  Attach a `field_access` map to a Plug.Conn or LiveView socket.

  Works uniformly in `:rest` and `:live` modes:

    * In a Phoenix controller (`:rest`), call before
      `CaravelaSvelte.render/4`:

          conn
          |> CaravelaSvelte.Caravela.put_field_access(field_access)
          |> CaravelaSvelte.render("BookIndex", %{books: books, field_access: field_access})

    * In a LiveView (`:live`), call during `mount/3` or
      `handle_params/3`:

          {:ok, CaravelaSvelte.Caravela.put_field_access(socket, field_access)}

  The function just assigns `:field_access` so downstream code
  can read `@field_access` in templates and pass it as a prop to
  `<CaravelaSvelte.svelte>`.
  """
  @spec put_field_access(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def put_field_access(%Plug.Conn{} = conn, field_access) when is_map(field_access) do
    Plug.Conn.assign(conn, :field_access, field_access)
  end

  if Code.ensure_loaded?(Phoenix.LiveView) do
    @spec put_field_access(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
    def put_field_access(%Phoenix.LiveView.Socket{} = socket, field_access)
        when is_map(field_access) do
      Phoenix.Component.assign(socket, :field_access, field_access)
    end
  end

  @doc """
  Translate an `Ecto.Changeset` into the `%{field => [msg, ...]}`
  shape both `useForm` (REST) and `useLiveForm` (LiveView)
  consume.

  Merges the changeset's `:action` before traversal so templates
  that haven't explicitly marked the changeset as validated still
  surface errors. Interpolates `%{count}` placeholders from the
  error `opts`.

  Requires `Ecto` at runtime; raises otherwise.
  """
  if Code.ensure_loaded?(Ecto.Changeset) do
    @spec errors(Ecto.Changeset.t()) :: %{optional(atom()) => [String.t()]}
    def errors(%Ecto.Changeset{} = changeset) do
      changeset
      |> Ecto.Changeset.traverse_errors(&translate_error/1)
    end

    defp translate_error({msg, opts}) do
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end
  else
    def errors(_changeset) do
      raise "CaravelaSvelte.Caravela.errors/1 requires Ecto to be loaded"
    end
  end

  @doc """
  Build the conventional SSE topic string for an entity scoped
  to an actor. Centralised so Caravela's generators and runtime
  agree on the wire format.

      iex> CaravelaSvelte.Caravela.entity_topic("Book", 42)
      "caravela:book:actor:42"

      iex> CaravelaSvelte.Caravela.entity_topic(:book, nil)
      "caravela:book"

  Entity names are normalised to lowercase. `nil` actors drop
  the `:actor:<id>` suffix for broadcast-to-all patterns.
  """
  @spec entity_topic(atom() | String.t(), term() | nil) :: String.t()
  def entity_topic(entity, actor_id \\ nil)

  def entity_topic(entity, nil), do: "caravela:" <> normalise_entity(entity)

  def entity_topic(entity, actor_id) do
    "caravela:" <> normalise_entity(entity) <> ":actor:" <> to_string(actor_id)
  end

  @doc """
  Publish a JSON-Patch on the conventional topic for an entity
  + actor pair. Thin wrapper over `CaravelaSvelte.SSE.publish/2`
  that derives the topic via `entity_topic/2`.

      CaravelaSvelte.Caravela.broadcast_patch(:book, actor.id, [
        ["replace", "/title", "Updated"]
      ])

  Pass `nil` as the actor to broadcast to every subscriber of
  the entity — useful for admin dashboards.
  """
  @spec broadcast_patch(atom() | String.t(), term() | nil, list()) ::
          :ok | {:error, term()}
  def broadcast_patch(entity, actor_id, ops) when is_list(ops) do
    CaravelaSvelte.SSE.publish(entity_topic(entity, actor_id), ops)
  end

  # --- Internals ------------------------------------------------------

  defp normalise_entity(entity) when is_atom(entity),
    do: entity |> Atom.to_string() |> String.downcase()

  defp normalise_entity(entity) when is_binary(entity),
    do: String.downcase(entity)
end
