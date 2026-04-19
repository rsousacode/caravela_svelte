defmodule CaravelaSvelte.RestTest do
  use ExUnit.Case, async: true

  alias CaravelaSvelte.Rest

  defp conn(method \\ :get, path \\ "/books", headers \\ []) do
    Plug.Test.conn(method, path)
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {k, v}, acc ->
        Plug.Conn.put_req_header(acc, k, v)
      end)
    end)
  end

  describe "full-document response" do
    test "returns 200 with HTML body and data-page attribute" do
      c = Rest.render(conn(), "BookIndex", %{foo: "bar"}, version: "v1", ssr: false)

      assert c.status == 200
      assert Plug.Conn.get_resp_header(c, "content-type") == ["text/html; charset=utf-8"]
      assert c.resp_body =~ ~s(data-mode="rest")
      assert c.resp_body =~ ~s(data-page=)
      assert c.resp_body =~ "BookIndex"
      # CSS/JS shell
      assert c.resp_body =~ "/assets/app.js"
    end

    test "supports a custom :layout function" do
      layout = fn _conn, %{root_html: root, page: page} ->
        [
          ~s(<html><body data-test="),
          page.component,
          ~s(">),
          root,
          ~s(</body></html>)
        ]
      end

      c =
        Rest.render(conn(), "BookIndex", %{foo: "bar"},
          version: "v1",
          ssr: false,
          layout: layout
        )

      assert c.resp_body =~ ~s(data-test="BookIndex")
      assert c.resp_body =~ ~s(data-mode="rest")
    end
  end

  describe "navigation response" do
    test "returns 200 JSON with inertia headers when x-inertia: true" do
      c =
        conn(:get, "/books", [
          {"x-inertia", "true"},
          {"x-inertia-version", "v1"}
        ])
        |> Rest.render("BookIndex", %{foo: "bar"}, version: "v1", ssr: false)

      assert c.status == 200
      assert Plug.Conn.get_resp_header(c, "content-type") == ["application/json; charset=utf-8"]
      assert Plug.Conn.get_resp_header(c, "x-inertia") == ["true"]
      assert Plug.Conn.get_resp_header(c, "vary") == ["X-Inertia"]

      decoded = :json.decode(c.resp_body)
      assert decoded["component"] == "BookIndex"
      assert decoded["props"]["foo"] == "bar"
      assert decoded["url"] =~ "/books"
      assert decoded["version"] == "v1"
    end
  end

  describe "version mismatch" do
    test "returns 409 with x-inertia-location when client version differs" do
      c =
        conn(:get, "/books", [
          {"x-inertia", "true"},
          {"x-inertia-version", "stale"}
        ])
        |> Rest.render("BookIndex", %{foo: "bar"}, version: "current", ssr: false)

      assert c.status == 409
      assert Plug.Conn.get_resp_header(c, "x-inertia-location") == ["/books"]
    end
  end

  describe "top-level delegation" do
    test "CaravelaSvelte.render/4 reaches Rest.render/4" do
      c = CaravelaSvelte.render(conn(), "BookIndex", %{foo: "bar"}, version: "v1", ssr: false)
      assert c.status == 200
    end
  end
end
