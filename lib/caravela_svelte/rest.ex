defmodule CaravelaSvelte.Rest do
  @moduledoc """
  REST (HTTP-transport) renderer for `CaravelaSvelte`.

  Turns a `{name, props}` pair into either a full-document HTML
  response (first hit on a URL) or an Inertia-compatible JSON
  navigation response (subsequent Inertia-client fetches).

  Shares the SSR pipeline with `CaravelaSvelte.Live` via
  `CaravelaSvelte.SSR`. Shares no socket/diff machinery: every REST
  response carries the full prop payload, because there's no
  persistent connection to diff against.

  Controllers typically don't call this module directly — they
  call `CaravelaSvelte.render/4`, which picks the renderer, runs
  SSR, constructs the page object, and sends the right response
  shape per the `CaravelaSvelte.Protocol`.

  ### Scope

  Phase B.2 ships:

    * SSR-backed rendering (fires on every non-Inertia first load)
    * Full-document + navigation response shapes
    * Version-mismatch 409 handling

  **Deferred** (B.3 and later):

    * `useForm` / `navigate` client helpers
    * SSE real-time (B.4)
    * Partial / lazy / async props (post-1.0)
  """

  alias CaravelaSvelte.{Protocol, SSR}

  @doc """
  Render a Svelte component as a REST response. Returns a
  `%Plug.Conn{}` ready to send.

  ## Options

    * `:layout` — a 2-arity function `fn conn, assigns -> iodata end`
      that wraps the data-page `<div>` in an HTML layout. Only used
      on first-load (non-Inertia) responses. When omitted, renders
      a minimal built-in shell that loads `/assets/app.js` and
      `/assets/app.css`.
    * `:version` — override the server's asset version (defaults
      to `CaravelaSvelte.Protocol.asset_version/0`).
    * `:ssr` — set to `false` to skip SSR (useful in dev or tests).
    * `:url` — override the URL stamped on the page object
      (defaults to the conn's request path + query string).
  """
  @spec render(Plug.Conn.t(), String.t(), map(), keyword()) :: Plug.Conn.t()
  def render(%Plug.Conn{} = conn, component_name, props, opts \\ [])
      when is_binary(component_name) and is_map(props) do
    version = Keyword.get_lazy(opts, :version, &Protocol.asset_version/0)

    if Protocol.version_matches?(conn, version) do
      url = Keyword.get_lazy(opts, :url, fn -> request_url(conn) end)
      ssr? = Keyword.get(opts, :ssr, Application.get_env(:caravela_svelte, :ssr, true))

      ssr_output =
        if ssr? do
          try do
            SSR.render(component_name, props, %{})
          rescue
            SSR.NotConfigured -> nil
          end
        end

      page = Protocol.page_object(component_name, props, url, version)

      case Protocol.request_kind(conn) do
        :navigation -> navigation_response(conn, page)
        :full_document -> full_document_response(conn, page, ssr_output, opts)
      end
    else
      conn
      |> Protocol.version_mismatch(request_url(conn))
    end
  end

  # --- Internals -----------------------------------------------------

  defp navigation_response(conn, page) do
    body = page |> Protocol.navigation_body() |> CaravelaSvelte.JSON.encode!()

    conn
    |> Protocol.put_inertia_headers()
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(200, body)
  end

  defp full_document_response(conn, page, ssr_output, opts) do
    layout = Keyword.get(opts, :layout, &default_layout/2)

    body =
      layout.(conn, %{
        root_html: Protocol.render_root_html(page, mode: "rest"),
        ssr: ssr_output,
        page: page
      })

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.resp(200, IO.iodata_to_binary(body))
  end

  defp request_url(%Plug.Conn{} = conn) do
    case conn.query_string do
      "" -> conn.request_path
      nil -> conn.request_path
      qs -> conn.request_path <> "?" <> qs
    end
  end

  # Minimal default layout — loads /assets/app.{js,css}. Apps are
  # expected to pass their own `:layout` function once they have a
  # Phoenix layout they want to embed the `data-page` div into.
  defp default_layout(_conn, %{root_html: root_html, ssr: ssr}) do
    head = if ssr, do: ssr["head"] || "", else: ""
    css = if ssr, do: get_in(ssr, ["css", "code"]) || "", else: ""
    html = if ssr, do: ssr["html"] || "", else: ""
    root_html_string = IO.iodata_to_binary([root_html])

    root_with_ssr =
      String.replace(
        root_html_string,
        ~s(></div>),
        ~s(>) <> html <> ~s(</div>),
        global: false
      )

    [
      ~s(<!DOCTYPE html>\n),
      ~s(<html lang="en">\n),
      ~s(<head>\n),
      ~s(<meta charset="utf-8"/>\n),
      ~s(<meta name="viewport" content="width=device-width, initial-scale=1"/>\n),
      head,
      ~s(<style>),
      css,
      ~s(</style>\n),
      ~s(<link rel="stylesheet" href="/assets/app.css"/>\n),
      ~s(<script type="module" src="/assets/app.js" defer></script>\n),
      ~s(</head>\n),
      ~s(<body>\n),
      root_with_ssr,
      ~s(\n</body>\n),
      ~s(</html>\n)
    ]
  end
end
