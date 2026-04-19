defmodule CaravelaSvelte.SSR.NotConfigured do
  @moduledoc false

  defexception [:message]
end

defmodule CaravelaSvelte.SSR do
  @moduledoc """
  A behaviour for rendering Svelte components server-side.

  Shared by every `CaravelaSvelte.Renderer` implementation — the
  `:live` and (future) `:rest` renderers both delegate SSR here so
  pool/config/telemetry are single-sourced.

  To define a custom renderer, change the application config in `config.exs`:

      config :caravela_svelte, ssr_module: MyCustomSSRModule

  ## Telemetry

  Exposes a telemetry span for each render under the key `[:caravela_svelte, :ssr]`.

  The following events are emitted:

    * `[:caravela_svelte, :ssr, :start]` — fired when a render begins.
      Metadata: `%{component: name, props: props, slots: slots}`.

    * `[:caravela_svelte, :ssr, :stop]` — fired when a render completes successfully.
      Metadata: same. Measurements include `%{duration: duration}` in native time units
      (convert with `:erlang.convert_time_unit(duration, :native, :millisecond)`).

    * `[:caravela_svelte, :ssr, :exception]` — fired when the renderer raises.
      The exception is re-raised after the event is emitted.
  """

  @type component_name :: String.t()
  @type props :: %{optional(String.t() | atom) => any}
  @type slots :: %{optional(String.t() | atom) => any}

  @typedoc """
  A render response which should take the shape:
      %{
        "css" => %{
          "code" => String.t | nil,
          "map" => String.t | nil
        },
        "head" => String.t,
        "html" => String.t
      }
  """
  @type render_response :: %{
          required(String.t()) =>
            %{
              required(String.t()) => String.t() | nil
            }
            | String.t()
        }

  @callback render(component_name, props, slots) :: render_response | no_return

  @spec render(component_name, props, slots) :: render_response | no_return
  def render(name, props, slots) do
    mod = Application.get_env(:caravela_svelte, :ssr_module, CaravelaSvelte.SSR.NodeJS)
    meta = %{component: name, props: props, slots: slots}

    :telemetry.span([:caravela_svelte, :ssr], meta, fn ->
      {mod.render(name, props, slots), meta}
    end)
  end

  @deprecated "Use CaravelaSvelte.SSR.NodeJS.server_path/0 instead."
  def server_path() do
    CaravelaSvelte.SSR.NodeJS.server_path()
  end
end
