defmodule CaravelaSvelte.RouterTest do
  use ExUnit.Case, async: true

  defmodule FakeLive do
    use Phoenix.LiveView
    def render(assigns), do: ~H""
  end

  defmodule FakeController do
    use Phoenix.Controller, formats: [:html, :json]

    # Capture the mode from conn.private in the response headers so
    # tests can observe what the router tagged.
    defp echo(conn, label) do
      mode = conn.private[:caravela_svelte_mode] || :none

      conn
      |> Plug.Conn.put_resp_header("x-cs-mode", to_string(mode))
      |> Plug.Conn.put_resp_header("x-cs-action", label)
      |> Plug.Conn.send_resp(200, label)
    end

    def index(conn, _), do: echo(conn, "index")
    def show(conn, _), do: echo(conn, "show")
    def new(conn, _), do: echo(conn, "new")
    def edit(conn, _), do: echo(conn, "edit")
    def create(conn, _), do: echo(conn, "create")
    def update(conn, _), do: echo(conn, "update")
    def delete(conn, _), do: echo(conn, "delete")
  end

  defmodule FakeRouter do
    use Phoenix.Router
    use CaravelaSvelte.Router

    caravela_live("/dashboard", CaravelaSvelte.RouterTest.FakeLive)

    caravela_rest("/library/books", CaravelaSvelte.RouterTest.FakeController)

    caravela_rest("/library/authors", CaravelaSvelte.RouterTest.FakeController,
      only: [:index, :show]
    )

    caravela_rest("/widgets", CaravelaSvelte.RouterTest.FakeController,
      only: [:index],
      realtime: true
    )

    caravela_rest("/metrics", CaravelaSvelte.RouterTest.FakeController,
      only: [:index],
      realtime: [heartbeat_ms: 45_000, topic_prefix: "metrics:"]
    )

    caravela_live("/admin", CaravelaSvelte.RouterTest.FakeLive, :index,
      private: %{layout: :admin}
    )
  end

  defp call(method, path, body \\ nil) do
    Plug.Test.conn(method, path, body) |> FakeRouter.call(FakeRouter.init([]))
  end

  describe "caravela_live" do
    test "registers the live route at the given path" do
      paths = Enum.map(FakeRouter.__routes__(), & &1.path)
      assert "/dashboard" in paths
      assert "/admin" in paths
    end

    test "dispatches /dashboard through Phoenix.LiveView.Plug" do
      route = Enum.find(FakeRouter.__routes__(), &(&1.path == "/dashboard"))
      assert route.plug == Phoenix.LiveView.Plug
    end
  end

  describe "caravela_rest" do
    test "expands to the 8 standard resource routes by default" do
      # Phoenix emits 8 routes for resources/2 because :update has
      # both PUT and PATCH verbs.
      paths =
        FakeRouter.__routes__()
        |> Enum.map(& &1.path)
        |> Enum.filter(&String.starts_with?(&1, "/library/books"))

      assert "/library/books" in paths
      assert "/library/books/new" in paths
      assert "/library/books/:id" in paths
      assert "/library/books/:id/edit" in paths
      assert length(paths) == 8
    end

    test "honours :only" do
      paths =
        FakeRouter.__routes__()
        |> Enum.filter(&String.starts_with?(&1.path, "/library/authors"))
        |> Enum.map(& &1.path)

      assert "/library/authors" in paths
      assert "/library/authors/:id" in paths
      refute Enum.any?(paths, &String.ends_with?(&1, "/new"))
      refute Enum.any?(paths, &String.ends_with?(&1, "/edit"))
    end

    test "tags each dispatched conn with caravela_svelte_mode: :rest" do
      conn = call(:get, "/library/books")
      assert Plug.Conn.get_resp_header(conn, "x-cs-mode") == ["rest"]
      assert Plug.Conn.get_resp_header(conn, "x-cs-action") == ["index"]
    end

    test "works for member routes too" do
      conn = call(:get, "/library/books/42")
      assert Plug.Conn.get_resp_header(conn, "x-cs-mode") == ["rest"]
      assert Plug.Conn.get_resp_header(conn, "x-cs-action") == ["show"]
    end

    test "tags still apply after :only filtering" do
      conn = call(:get, "/library/authors")
      assert Plug.Conn.get_resp_header(conn, "x-cs-mode") == ["rest"]
      assert Plug.Conn.get_resp_header(conn, "x-cs-action") == ["index"]
    end
  end

  describe "caravela_rest + realtime: true" do
    test "registers a GET <path>/__events route dispatching to the SSE plug" do
      events_route =
        Enum.find(FakeRouter.__routes__(), &(&1.path == "/widgets/__events"))

      assert events_route
      assert events_route.verb == :get
      assert events_route.plug == CaravelaSvelte.SSE
      assert events_route.plug_opts == []
    end

    test "the resource routes still register alongside the SSE route" do
      paths =
        FakeRouter.__routes__()
        |> Enum.map(& &1.path)
        |> Enum.filter(&String.starts_with?(&1, "/widgets"))

      assert "/widgets" in paths
      assert "/widgets/__events" in paths
    end

    test "passes realtime keyword list through as plug opts" do
      route =
        Enum.find(FakeRouter.__routes__(), &(&1.path == "/metrics/__events"))

      assert route
      assert route.plug == CaravelaSvelte.SSE
      assert route.plug_opts[:heartbeat_ms] == 45_000
      assert route.plug_opts[:topic_prefix] == "metrics:"
    end

    test "realtime: false (default) does not register an SSE route" do
      paths = Enum.map(FakeRouter.__routes__(), & &1.path)
      refute "/library/books/__events" in paths
      refute "/library/authors/__events" in paths
    end
  end
end
