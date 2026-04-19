defmodule CaravelaSvelte.Router do
  @moduledoc """
  Router macros for declaring `:live` and `:rest` mode routes.

  `use CaravelaSvelte.Router` imports `caravela_live/2..4` (wrapping
  `Phoenix.LiveView.Router.live/2..4`) and `caravela_rest/2..3`
  (wrapping `Phoenix.Router.resources/2..4`).

      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        use CaravelaSvelte.Router

        scope "/", MyAppWeb do
          pipe_through :browser

          caravela_live "/dashboard", DashboardLive
          caravela_rest "/library/books", BookController
        end
      end

  Under the hood:

    * `caravela_live` expands 1:1 to `live/2..4` — the existing
      LiveView route helper. The extra sugar is a per-route
      metadata entry saying "this route is CaravelaSvelte's
      `:live` mode" so future plugs (B.4 SSE, auth integration)
      can branch on it.
    * `caravela_rest` expands to `resources/2..4` with sensible
      Inertia-style defaults (all 7 actions).

  Both macros accept the same optional args as their Phoenix
  counterparts; options are passed through.

  ## Action filtering

  To opt out of actions (e.g., a read-only resource), use `:only`
  or `:except` as with `resources`:

      caravela_rest "/library/books", BookController, only: [:index, :show]
  """

  @doc """
  Import `caravela_live/2..4` and `caravela_rest/2..3` into the
  caller. Assumes the caller already `use`s Phoenix.Router and
  has access to `Phoenix.LiveView.Router.live/4` (usually via
  `use MyAppWeb, :router`).
  """
  defmacro __using__(_opts) do
    quote do
      import Phoenix.LiveView.Router, only: [live: 2, live: 3, live: 4]
      import CaravelaSvelte.Router, only: [caravela_live: 2, caravela_live: 3, caravela_live: 4, caravela_rest: 2, caravela_rest: 3]
    end
  end

  @doc """
  Declare a `:live` mode route. Forwards to
  `Phoenix.LiveView.Router.live/2..4`.

  Accepts the same arguments: `path`, `live_view`, optional action
  atom, optional keyword options. Options are passed through to
  Phoenix's `live` macro.

  A `private: %{caravela_svelte_mode: :live}` entry is merged into
  the options so downstream plugs (see `CaravelaSvelte.Plug`) can
  identify the route's mode at runtime.
  """
  defmacro caravela_live(path, live_view, action \\ nil, opts \\ []) do
    opts = merge_mode_private(opts, :live)

    quote do
      live(unquote(path), unquote(live_view), unquote(action), unquote(opts))
    end
  end

  @doc """
  Declare a `:rest` mode route. Forwards to
  `Phoenix.Router.resources/2..4` and merges a
  `private: %{caravela_svelte_mode: :rest}` entry so downstream
  plugs can branch on the mode.

  ## Options

  All `resources/4` options are supported — `:only`, `:except`,
  `:as`, `:param`, `:singleton`. The `:private` map is merged,
  not overwritten.
  """
  defmacro caravela_rest(path, controller, opts \\ []) do
    opts = merge_mode_private(opts, :rest)

    quote do
      resources(unquote(path), unquote(controller), unquote(opts))
    end
  end

  # --- Helpers --------------------------------------------------------

  # Merges `private: %{caravela_svelte_mode: mode}` into the opts
  # keyword list without clobbering any existing `:private` entries.
  defp merge_mode_private(opts, mode) do
    case Keyword.fetch(opts, :private) do
      {:ok, {:%{}, meta, pairs}} ->
        # :private is a map AST literal
        merged_pairs = Keyword.put(pairs, :caravela_svelte_mode, mode)
        Keyword.put(opts, :private, {:%{}, meta, merged_pairs})

      {:ok, private} ->
        # :private is a runtime expression — we can't statically merge;
        # wrap at runtime.
        quoted =
          quote do
            Map.put(unquote(private), :caravela_svelte_mode, unquote(mode))
          end

        Keyword.put(opts, :private, quoted)

      :error ->
        Keyword.put(opts, :private, {:%{}, [], [caravela_svelte_mode: mode]})
    end
  end
end
