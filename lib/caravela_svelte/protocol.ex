defmodule CaravelaSvelte.Protocol do
  @moduledoc """
  Inertia-2.x-compatible request/response shape for
  `CaravelaSvelte.Rest`.

  Pure functions only — no SSR, no controller logic. Read a
  `%Plug.Conn{}`, emit response data; the caller decides how to
  send it.

  ## Protocol summary

  A non-Inertia GET request receives a full HTML document with an
  embedded page object:

      <div id="app" data-page='{"component":"BookIndex",...}'></div>

  Subsequent navigations from the Inertia client arrive with an
  `x-inertia: true` request header and a `x-inertia-version: <digest>`.
  The server returns JSON with the page object:

      {"component":"BookIndex","props":{...},"url":"/library/books","version":"<digest>"}

  Response carries `x-inertia: true` and `vary: X-Inertia`.

  ### Version mismatch

  If the client's `x-inertia-version` differs from the server's
  current version, the server returns **409 Conflict** with an
  `x-inertia-location: <url>` header. The client reacts by doing
  a hard page reload (which bootstraps the new asset bundle).

  ### Scope

  Phase B.2 ships the minimum protocol surface that covers CRUD:

    * first-load full-document response
    * SPA navigation (JSON)
    * version header handling + 409 mismatch

  **Not implemented** (deferred — see
  [phase_b2_rest_renderer.md](../../../caravela_plan/phoenix/render_modes/phase_b2_rest_renderer.md)
  for the non-goals):

    * partial reloads (`x-inertia-partial-data` / `-component`)
    * lazy / async / deferred props
    * history encryption / clearHistory
  """

  @inertia_header "x-inertia"
  @version_header "x-inertia-version"
  @location_header "x-inertia-location"

  @type request_kind :: :full_document | :navigation
  @type page_object :: %{
          required(:component) => String.t(),
          required(:props) => map(),
          required(:url) => String.t(),
          required(:version) => String.t()
        }

  @doc """
  Classify an incoming request. Returns `:navigation` when the
  Inertia client header is present, `:full_document` otherwise.
  """
  @spec request_kind(Plug.Conn.t()) :: request_kind()
  def request_kind(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, @inertia_header) do
      ["true"] -> :navigation
      [_] -> :navigation
      [] -> :full_document
    end
  end

  @doc """
  Extract the client's declared asset version, or `nil` when the
  header is absent.
  """
  @spec client_version(Plug.Conn.t()) :: String.t() | nil
  def client_version(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, @version_header) do
      [v | _] -> v
      [] -> nil
    end
  end

  @doc """
  Build the page object sent to the client (both in full-document
  and navigation responses).
  """
  @spec page_object(String.t(), map(), String.t(), String.t()) :: page_object()
  def page_object(component, props, url, version)
      when is_binary(component) and is_map(props) and is_binary(url) and is_binary(version) do
    %{component: component, props: props, url: url, version: version}
  end

  @doc """
  Return `true` when the client's declared version matches the
  server's. First-load requests (no version header) are treated as
  matching so we don't bounce them.
  """
  @spec version_matches?(Plug.Conn.t(), String.t()) :: boolean()
  def version_matches?(%Plug.Conn{} = conn, server_version)
      when is_binary(server_version) do
    case client_version(conn) do
      nil -> true
      ^server_version -> true
      _ -> false
    end
  end

  @doc """
  Server-side asset version. Defaults to the md5 of
  `priv/static/manifest.json` if the file exists, otherwise to the
  release hash, otherwise to `"dev"`.

  Override per-app:

      config :caravela_svelte, :asset_version, fn -> MyApp.asset_version() end

  The config value may be a string or a zero-arity function.
  """
  @spec asset_version() :: String.t()
  def asset_version do
    case Application.get_env(:caravela_svelte, :asset_version) do
      nil -> derive_asset_version()
      fun when is_function(fun, 0) -> fun.()
      value when is_binary(value) -> value
    end
  end

  # --- Response builders -----------------------------------------------

  @doc """
  Mark a response conn as Inertia-aware (sets the `x-inertia` and
  `vary` headers). Used by both navigation responses and the
  mismatch fallback.
  """
  @spec put_inertia_headers(Plug.Conn.t()) :: Plug.Conn.t()
  def put_inertia_headers(%Plug.Conn{} = conn) do
    conn
    |> Plug.Conn.put_resp_header(@inertia_header, "true")
    |> merge_vary_header("X-Inertia")
  end

  @doc """
  Build the response body for a navigation response. The caller
  wraps it with JSON encoding + headers.
  """
  @spec navigation_body(page_object()) :: map()
  def navigation_body(page_object), do: page_object

  @doc """
  Build a 409 version-mismatch response. The caller sends it and
  halts.
  """
  @spec version_mismatch(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def version_mismatch(%Plug.Conn{} = conn, location) when is_binary(location) do
    conn
    |> Plug.Conn.put_resp_header(@location_header, location)
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.resp(409, "Inertia asset version mismatch")
  end

  @doc """
  Serialise the page object as the `data-page` attribute for a
  first-load full document. Caller is responsible for the
  surrounding HTML; `render_root_html/2` is a convenience.
  """
  @spec data_page_attribute(page_object()) :: String.t()
  def data_page_attribute(page_object) do
    page_object
    |> CaravelaSvelte.JSON.encode!()
    |> Plug.HTML.html_escape()
  end

  @doc """
  Render the root `<div>` Inertia clients bootstrap from. Not a
  full HTML document — callers typically embed this inside a
  Phoenix layout.
  """
  @spec render_root_html(page_object(), keyword()) :: iolist()
  def render_root_html(page_object, opts \\ []) do
    id = Keyword.get(opts, :id, "caravela-svelte-app")
    mode = Keyword.get(opts, :mode, "rest")
    ~s(<div id="#{id}" data-mode="#{mode}" data-page="#{data_page_attribute(page_object)}"></div>)
  end

  # --- Helpers --------------------------------------------------------

  defp derive_asset_version do
    priv =
      :caravela_svelte
      |> Application.app_dir()
      |> Path.join("..")
      |> Path.expand()

    candidates = [
      # Consumer app's static manifest
      Application.get_env(:caravela_svelte, :manifest_path, "priv/static/manifest.json"),
      Path.join(priv, "priv/static/manifest.json")
    ]

    Enum.find_value(candidates, "dev", fn path ->
      case File.read(path) do
        {:ok, content} ->
          :crypto.hash(:md5, content) |> Base.encode16(case: :lower)

        _ ->
          nil
      end
    end)
  end

  defp merge_vary_header(conn, value) do
    case Plug.Conn.get_resp_header(conn, "vary") do
      [] ->
        Plug.Conn.put_resp_header(conn, "vary", value)

      [existing | _] ->
        if String.contains?(existing, value) do
          conn
        else
          Plug.Conn.put_resp_header(conn, "vary", existing <> ", " <> value)
        end
    end
  end
end
