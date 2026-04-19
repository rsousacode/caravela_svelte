defmodule CaravelaSvelte.SSE do
  @moduledoc """
  Server-Sent Events adapter for `:rest` mode real-time updates.

  Turns a long-lived HTTP connection into an opt-in push channel:
  server code broadcasts a JSON-Patch via `Phoenix.PubSub`, this
  plug forwards each patch to subscribed browsers as an SSE
  `event: patch` frame. The client-side `subscribe()` helper
  parses the frame and hands the ops to the caller (typically
  `applyPatch($pageState.props, ops)`).

  Scope: SSE is one-way server → client. Pages that need
  bidirectional real-time should use `:live` mode.

  ## Publishing

      CaravelaSvelte.SSE.publish("dashboard:user:42", [
        ["replace", "/counter", 7]
      ])

  The topic is an opaque string matched against subscriptions.
  Consumers should namespace it to avoid collisions with other
  apps sharing the PubSub.

  ## Subscribing (route opt-in)

  Wire up via `CaravelaSvelte.Router`:

      caravela_rest "/dashboard", DashboardController, realtime: true

  This registers `GET /dashboard/__events` → this plug. The
  client calls `subscribe("dashboard:user:42", onPatch)` which
  opens an `EventSource` at that path, passing the topic as a
  query-string parameter.

  ## Options (plug init / route opts)

    * `:pubsub` — the `Phoenix.PubSub` module. Falls back to
      `config :caravela_svelte, :pubsub, MyApp.PubSub`.
    * `:heartbeat_ms` — interval between keep-alive comments
      (default `15_000`). Proxies sometimes close idle connections
      silently; a comment every 15 s keeps the stream warm.
    * `:retry_ms` — initial `retry:` hint sent once on connect.
      EventSource uses this when auto-reconnecting. Default `3_000`.
    * `:topic_prefix` — required prefix for accepted topics.
      Defaults to `""` (any). Set this to avoid clients subscribing
      to topics the app did not intend to expose.

  ## Heartbeat & reconnect

  EventSource auto-reconnects. We send `retry: <ms>\\n\\n` once on
  open; browsers honour it. Heartbeat comments flow every
  `:heartbeat_ms` milliseconds; they carry no payload and exist
  only to exercise the TCP path.

  ## Termination

  The plug exits when the client disconnects (the next `chunk/2`
  returns `{:error, :closed}`). The process-dictionary has no
  lingering PubSub subscription because the BEAM cleans up
  automatically when the handler process exits.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @default_heartbeat_ms 15_000
  @default_retry_ms 3_000

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{} = conn, opts) do
    with {:ok, topic} <- fetch_topic(conn, opts),
         {:ok, pubsub} <- fetch_pubsub(opts) do
      heartbeat_ms = Keyword.get(opts, :heartbeat_ms, @default_heartbeat_ms)
      retry_ms = Keyword.get(opts, :retry_ms, @default_retry_ms)

      :ok = Phoenix.PubSub.subscribe(pubsub, topic)

      conn
      |> put_sse_headers()
      |> send_chunked(200)
      |> send_initial(retry_ms)
      |> stream_loop(heartbeat_ms)
    else
      {:error, :invalid_topic} ->
        conn |> resp(400, "invalid topic") |> halt()

      {:error, :no_pubsub} ->
        Logger.error("[caravela_svelte] SSE: no PubSub configured")
        conn |> resp(500, "sse misconfigured") |> halt()
    end
  end

  @doc """
  Broadcast a JSON-Patch `ops` list on `topic` so subscribed SSE
  clients receive it. Looks up the PubSub from app config when
  not passed explicitly.

  `ops` is a list of compressed patch entries matching the
  client-side `applyPatch` input shape — e.g.
  `[["replace", "/counter", 7]]`.
  """
  @spec publish(String.t(), list()) :: :ok | {:error, term()}
  def publish(topic, ops) when is_binary(topic) and is_list(ops) do
    case configured_pubsub() do
      nil -> {:error, :no_pubsub}
      mod -> publish(mod, topic, ops)
    end
  end

  @spec publish(module(), String.t(), list()) :: :ok
  def publish(pubsub, topic, ops)
      when is_atom(pubsub) and is_binary(topic) and is_list(ops) do
    Phoenix.PubSub.broadcast(pubsub, topic, {:caravela_svelte_patch, topic, ops})
  end

  @doc """
  Format a JSON-Patch ops list as an SSE frame. Pure — exported
  for tests.
  """
  @spec format_patch(list()) :: iodata()
  def format_patch(ops) when is_list(ops) do
    [
      "event: patch\n",
      "data: ",
      CaravelaSvelte.JSON.encode!(ops),
      "\n\n"
    ]
  end

  # --- Internals ------------------------------------------------------

  defp put_sse_headers(conn) do
    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache, no-transform")
    |> put_resp_header("connection", "keep-alive")
    # Nginx: disable response buffering for this endpoint.
    |> put_resp_header("x-accel-buffering", "no")
  end

  defp send_initial(conn, retry_ms) do
    case chunk(conn, "retry: #{retry_ms}\n\n") do
      {:ok, conn} -> conn
      {:error, _} -> halt(conn)
    end
  end

  defp stream_loop(conn, heartbeat_ms) do
    :timer.send_interval(heartbeat_ms, self(), :caravela_sse_heartbeat)
    do_loop(conn)
  end

  defp do_loop(conn) do
    receive do
      {:caravela_svelte_patch, _topic, ops} ->
        case chunk(conn, format_patch(ops)) do
          {:ok, conn} -> do_loop(conn)
          {:error, _} -> halt(conn)
        end

      :caravela_sse_heartbeat ->
        case chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> do_loop(conn)
          {:error, _} -> halt(conn)
        end

      {:caravela_sse_stop, reason} ->
        Logger.debug("[caravela_svelte] SSE stop: #{inspect(reason)}")
        halt(conn)
    end
  end

  defp fetch_topic(conn, opts) do
    conn = fetch_query_params(conn)
    raw = conn.query_params["topic"]
    prefix = Keyword.get(opts, :topic_prefix, "")

    cond do
      is_nil(raw) or raw == "" -> {:error, :invalid_topic}
      not is_binary(raw) -> {:error, :invalid_topic}
      prefix != "" and not String.starts_with?(raw, prefix) -> {:error, :invalid_topic}
      true -> {:ok, raw}
    end
  end

  defp fetch_pubsub(opts) do
    case Keyword.get(opts, :pubsub) || configured_pubsub() do
      nil -> {:error, :no_pubsub}
      mod -> {:ok, mod}
    end
  end

  defp configured_pubsub, do: Application.get_env(:caravela_svelte, :pubsub)
end
