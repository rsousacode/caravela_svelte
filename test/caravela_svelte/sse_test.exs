defmodule CaravelaSvelte.SSETest do
  use ExUnit.Case, async: false

  alias CaravelaSvelte.SSE

  @pubsub CaravelaSvelte.SSETest.PubSub

  setup_all do
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    :ok
  end

  setup do
    prev = Application.get_env(:caravela_svelte, :pubsub)
    Application.put_env(:caravela_svelte, :pubsub, @pubsub)

    on_exit(fn ->
      if prev do
        Application.put_env(:caravela_svelte, :pubsub, prev)
      else
        Application.delete_env(:caravela_svelte, :pubsub)
      end
    end)

    :ok
  end

  describe "format_patch/1" do
    test "emits a JSON patch frame with event: patch" do
      frame = SSE.format_patch([["replace", "/counter", 7]]) |> IO.iodata_to_binary()
      assert frame == ~s(event: patch\ndata: [["replace","/counter",7]]\n\n)
    end

    test "handles empty ops list" do
      frame = SSE.format_patch([]) |> IO.iodata_to_binary()
      assert frame == "event: patch\ndata: []\n\n"
    end
  end

  describe "publish/2,3" do
    test "broadcasts to subscribers on the given topic" do
      topic = "sse_test:publish_2"
      :ok = Phoenix.PubSub.subscribe(@pubsub, topic)

      assert :ok = SSE.publish(topic, [["replace", "/x", 1]])

      assert_receive {:caravela_svelte_patch, ^topic, [["replace", "/x", 1]]}
    end

    test "errors when no pubsub is configured" do
      Application.delete_env(:caravela_svelte, :pubsub)
      assert SSE.publish("t", [["add", "/a", 1]]) == {:error, :no_pubsub}
    end

    test "publish/3 accepts an explicit pubsub module" do
      topic = "sse_test:publish_3"
      :ok = Phoenix.PubSub.subscribe(@pubsub, topic)

      assert :ok = SSE.publish(@pubsub, topic, [["add", "/y", 2]])
      assert_receive {:caravela_svelte_patch, ^topic, [["add", "/y", 2]]}
    end
  end

  describe "call/2 — request validation" do
    test "returns 400 when topic is missing" do
      conn = Plug.Test.conn(:get, "/__events") |> SSE.call([])
      assert conn.status == 400
      assert conn.halted
    end

    test "returns 400 when topic prefix doesn't match" do
      conn =
        Plug.Test.conn(:get, "/__events?topic=other:foo")
        |> SSE.call(topic_prefix: "allowed:")

      assert conn.status == 400
    end

    test "returns 500 when no pubsub is configured and none in opts" do
      Application.delete_env(:caravela_svelte, :pubsub)
      conn = Plug.Test.conn(:get, "/__events?topic=foo") |> SSE.call([])
      assert conn.status == 500
    end
  end

  describe "call/2 — streaming" do
    # The SSE loop blocks on `receive`. We run it inside a Task and
    # drive it with direct messages — `:caravela_svelte_patch` (what
    # Phoenix.PubSub would deliver) and `:caravela_sse_stop` to
    # terminate cleanly.
    test "streams retry hint, patch frame, and heartbeat chunks" do
      topic = "sse_test:stream"

      task =
        Task.async(fn ->
          Plug.Test.conn(:get, "/__events?topic=#{topic}")
          |> SSE.call(pubsub: @pubsub, heartbeat_ms: 25, retry_ms: 1500)
        end)

      # Give the plug a chance to subscribe + emit the retry hint.
      Process.sleep(20)

      send(task.pid, {:caravela_svelte_patch, topic, [["replace", "/n", 42]]})

      # Let at least one heartbeat fire.
      Process.sleep(60)

      send(task.pid, {:caravela_sse_stop, :test_done})

      conn = Task.await(task, 1_000)

      body = conn.resp_body
      assert body =~ "retry: 1500\n\n"
      assert body =~ ~s(event: patch\ndata: [["replace","/n",42]])
      assert body =~ ": keepalive"

      assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/event-stream"]
      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-cache, no-transform"]
      assert Plug.Conn.get_resp_header(conn, "x-accel-buffering") == ["no"]
    end

    test "forwards real Phoenix.PubSub broadcasts into the chunked response" do
      topic = "sse_test:pubsub_integration"

      task =
        Task.async(fn ->
          Plug.Test.conn(:get, "/__events?topic=#{topic}")
          |> SSE.call(pubsub: @pubsub, heartbeat_ms: 10_000, retry_ms: 3000)
        end)

      # Broadcast a few times with sleeps — the subscribe call
      # inside the task is synchronous so one retry is enough, but
      # the second broadcast defends against a slow scheduler.
      Process.sleep(30)
      :ok = SSE.publish(@pubsub, topic, [["add", "/z", 9]])
      Process.sleep(20)
      :ok = SSE.publish(@pubsub, topic, [["add", "/z", 9]])
      Process.sleep(20)

      send(task.pid, {:caravela_sse_stop, :done})
      conn = Task.await(task, 1_000)

      assert conn.resp_body =~ ~s(data: [["add","/z",9]])
    end
  end
end
