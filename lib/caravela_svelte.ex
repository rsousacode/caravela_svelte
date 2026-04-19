defmodule CaravelaSvelte do
  @moduledoc """
  CaravelaSvelte — Svelte + Phoenix with pluggable render modes.

  The `svelte/1` function component is the primary entry point; it
  dispatches assign preparation to the configured
  `CaravelaSvelte.Renderer` implementation (default
  `CaravelaSvelte.Live`) and emits the HEEx output.

  Phase B.1 ships the `:live` renderer only. Phase B.2 adds
  `CaravelaSvelte.Rest` (Inertia-style HTTP transport) and
  `CaravelaSvelte.svelte/1` gains mode-aware dispatch.

  This module is a fork of `live_svelte` by Wout De Puysseleir —
  see `NOTICE.md` for attribution.
  """

  use Phoenix.Component
  import Phoenix.HTML

  alias Phoenix.LiveView
  alias CaravelaSvelte.{Live, Renderer, Slots}

  # Override Phoenix's slot validation to accept arbitrary slot names.
  # This allows users to pass any named slot to Svelte components without
  # getting "undefined slot" warnings during compilation.
  @before_compile CaravelaSvelte.DynamicSlots

  attr :props, :map,
    default: %{},
    doc: "Props to pass to the Svelte component",
    examples: [%{foo: "bar"}, %{foo: "bar", baz: 1}, %{list: [], baz: 1, qux: %{a: 1, b: 2}}]

  attr :name, :string,
    required: true,
    doc: "Name of the Svelte component",
    examples: ["YourComponent", "directory/Example"]

  attr :id, :string,
    default: nil,
    doc:
      "Optional stable DOM id override. Auto-generated from the component name and props by " <>
        "default. Only needed when auto-detection is insufficient (e.g. two loops with the same component name)."

  attr :key, :any,
    default: nil,
    doc:
      "Identity key for stable DOM IDs in loops. When set, the DOM id becomes `name-key`. " <>
        "When not set, CaravelaSvelte auto-detects identity from props (id, key, index, idx keys)."

  attr :class, :string,
    default: nil,
    doc: "Class to apply to the Svelte component",
    examples: ["my-class", "my-class another-class"]

  attr :ssr, :boolean,
    default: true,
    doc: "Whether to render the component via NodeJS on the server",
    examples: [true, false]

  attr :socket, :map,
    default: nil,
    doc: "LiveView socket, only needed when ssr: true"

  attr :diff, :boolean,
    default: true,
    doc:
      "When true (and config enable_props_diff is true), only changed props are sent on update. Set to false to always send full props."

  slot :inner_block, doc: "Inner block of the Svelte component"

  slot(:loading,
    doc: "LiveView rendered markup to show while the component is loading client-side"
  )

  @doc """
  Renders a Svelte component on the server. Dispatches prep to the
  configured `CaravelaSvelte.Renderer`.
  """
  def svelte(assigns) do
    assigns = Renderer.configured().prepare(assigns)

    ~H"""
    <script>
      <%= raw(@ssr_render["head"]) %>
    </script>
    <div
      id={@svelte_id}
      data-name={@name}
      data-props={Live.json(@props_to_send)}
      data-props-diff={Live.json(@props_diff)}
      data-streams-diff={Live.json(@streams_diff)}
      data-use-diff={to_string(@use_diff)}
      data-ssr={@ssr_render != nil}
      data-slots={@slots |> Slots.base_encode_64() |> Live.json()}
      phx-hook="CaravelaSvelteHook"
      phx-update="ignore"
      class={@class}
    >
      <div id={"#{@svelte_id}-target"} data-svelte-target>
        {raw(@ssr_render["head"])}
        <style>
          <%= raw(@ssr_render["css"]["code"]) %>
        </style>
        {raw(@ssr_render["html"])}
        {render_slot(@loading)}
      </div>
    </div>
    """
  end

  @doc """
  Deprecated — call `svelte/1` instead.
  """
  def render(assigns) do
    IO.warn(
      "`CaravelaSvelte.render/1` is deprecated; call `CaravelaSvelte.svelte/1` instead.",
      Macro.Env.stacktrace(__ENV__)
    )

    svelte(assigns)
  end

  @reserved_prop_keys [:__changed__, :__given__, :svelte_opts, :ssr, :class, :socket]

  @doc false
  def get_props(assigns) do
    prop_keys =
      case Map.get(assigns, :__changed__) do
        nil -> Map.keys(assigns)
        changed when is_map(changed) -> Map.keys(changed)
      end

    assigns
    |> Map.filter(fn
      {k, _v} when k in @reserved_prop_keys -> false
      {k, _v} -> k in prop_keys
    end)
  end

  @doc false
  def get_socket(assigns) do
    case get_in(assigns, [:svelte_opts, :socket]) || assigns[:socket] do
      %LiveView.Socket{} = socket -> socket
      _ -> nil
    end
  end

  @doc false
  defmacro sigil_V({:<<>>, _meta, [string]}, []) do
    path = "./assets/svelte/_build/#{__CALLER__.module}.svelte"

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write!(path, string)
    end

    quote do
      ~H"""
      <CaravelaSvelte.svelte
        name={"_build/#{__MODULE__}"}
        props={get_props(assigns)}
        socket={get_socket(assigns)}
        ssr={get_in(assigns, [:svelte_opts, :ssr]) != false}
        class={get_in(assigns, [:svelte_opts, :class])}
      />
      """
    end
  end
end
