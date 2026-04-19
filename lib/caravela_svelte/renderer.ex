defmodule CaravelaSvelte.Renderer do
  @moduledoc """
  Behaviour for Svelte render backends.

  A renderer knows how to turn raw component assigns (name, props,
  slots, options) into a *prepared* assigns map that downstream code
  — usually the `CaravelaSvelte.svelte/1` function component — uses
  to emit the final output.

  The seam exists so `CaravelaSvelte.Rest` (Phase B.2) can reuse the
  same SSR pipeline and client-payload packaging, but emit a
  Plug.Conn response instead of HEEx.

  Today the only implementation is `CaravelaSvelte.Live`, which
  preserves the behaviour `live_svelte` has always had.

  ## Prepared assigns shape

  The prepared assigns map MUST include every key the
  `CaravelaSvelte.svelte/1` template reads:

    * `:init` — true on first render / dead render
    * `:slots` — decoded slot map
    * `:ssr_render` — result of SSR (or nil when disabled)
    * `:svelte_id` — stable DOM id
    * `:props_to_send` — map that will be JSON-encoded onto `data-props`
    * `:use_diff` — boolean flag
    * `:props_diff` — compressed JSON-patch ops list
    * `:streams_diff` — compressed stream patch ops list

  Plus whatever the original assigns carried (name, class, etc.).

  ## Configuration

  The default renderer is `CaravelaSvelte.Live`. Override per-app:

      config :caravela_svelte, :renderer, MyApp.CustomRenderer

  """

  @type assigns :: map()
  @type prepared :: map()

  @doc """
  Prepare component assigns for rendering. See the moduledoc for
  the required output shape.
  """
  @callback prepare(assigns) :: prepared

  @doc "Returns the configured renderer module. Defaults to `CaravelaSvelte.Live`."
  @spec configured() :: module()
  def configured do
    Application.get_env(:caravela_svelte, :renderer, CaravelaSvelte.Live)
  end
end
