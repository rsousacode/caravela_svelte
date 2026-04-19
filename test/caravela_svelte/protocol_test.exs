defmodule CaravelaSvelte.ProtocolTest do
  use ExUnit.Case, async: true

  alias CaravelaSvelte.Protocol

  defp conn(method \\ :get, path \\ "/", headers \\ []) do
    Plug.Test.conn(method, path)
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {k, v}, acc ->
        Plug.Conn.put_req_header(acc, k, v)
      end)
    end)
  end

  describe "request_kind/1" do
    test "returns :full_document when x-inertia header absent" do
      assert Protocol.request_kind(conn()) == :full_document
    end

    test "returns :navigation when x-inertia header present" do
      c = conn(:get, "/", [{"x-inertia", "true"}])
      assert Protocol.request_kind(c) == :navigation
    end
  end

  describe "client_version/1" do
    test "returns nil when header absent" do
      assert Protocol.client_version(conn()) == nil
    end

    test "returns the declared version" do
      c = conn(:get, "/", [{"x-inertia-version", "abc123"}])
      assert Protocol.client_version(c) == "abc123"
    end
  end

  describe "version_matches?/2" do
    test "matches when client omits the header (first-load)" do
      assert Protocol.version_matches?(conn(), "any")
    end

    test "matches on equal strings" do
      c = conn(:get, "/", [{"x-inertia-version", "v1"}])
      assert Protocol.version_matches?(c, "v1")
    end

    test "rejects mismatch" do
      c = conn(:get, "/", [{"x-inertia-version", "old"}])
      refute Protocol.version_matches?(c, "new")
    end
  end

  describe "page_object/4" do
    test "builds the canonical shape" do
      page = Protocol.page_object("BookIndex", %{foo: "bar"}, "/books", "v1")
      assert page.component == "BookIndex"
      assert page.props == %{foo: "bar"}
      assert page.url == "/books"
      assert page.version == "v1"
    end
  end

  describe "put_inertia_headers/1" do
    test "sets x-inertia: true and Vary: X-Inertia" do
      c = conn() |> Protocol.put_inertia_headers()
      assert Plug.Conn.get_resp_header(c, "x-inertia") == ["true"]
      assert Plug.Conn.get_resp_header(c, "vary") == ["X-Inertia"]
    end

    test "appends to an existing Vary header without duplicating" do
      c =
        conn()
        |> Plug.Conn.put_resp_header("vary", "Accept")
        |> Protocol.put_inertia_headers()

      assert Plug.Conn.get_resp_header(c, "vary") == ["Accept, X-Inertia"]
    end

    test "does not double-add when Vary already contains X-Inertia" do
      c =
        conn()
        |> Plug.Conn.put_resp_header("vary", "X-Inertia")
        |> Protocol.put_inertia_headers()

      assert Plug.Conn.get_resp_header(c, "vary") == ["X-Inertia"]
    end
  end

  describe "version_mismatch/2" do
    test "emits 409 with x-inertia-location header" do
      c = conn() |> Protocol.version_mismatch("/library/books")
      assert c.status == 409
      assert Plug.Conn.get_resp_header(c, "x-inertia-location") == ["/library/books"]
    end
  end

  describe "render_root_html/2" do
    test "escapes the page JSON into the data-page attribute" do
      page = Protocol.page_object("BookIndex", %{q: "a > b"}, "/books", "v1")
      html = IO.iodata_to_binary([Protocol.render_root_html(page)])

      assert html =~ ~s(data-mode="rest")
      assert html =~ ~s(data-page=")
      # > is html-escaped inside the attribute
      assert html =~ "&gt;"
    end
  end
end
