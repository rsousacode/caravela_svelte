defmodule CaravelaSvelte.CaravelaTest do
  use ExUnit.Case, async: false

  alias CaravelaSvelte.Caravela

  @pubsub CaravelaSvelte.CaravelaTest.PubSub

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

  describe "put_field_access/2" do
    test "assigns :field_access on a Plug.Conn" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Caravela.put_field_access(%{title: :read_write, isbn: :read_only})

      assert conn.assigns[:field_access] == %{title: :read_write, isbn: :read_only}
    end

    test "assigns :field_access on a LiveView socket" do
      socket = %Phoenix.LiveView.Socket{}
      result = Caravela.put_field_access(socket, %{title: :read_write})
      assert result.assigns[:field_access] == %{title: :read_write}
    end
  end

  describe "errors/1" do
    defmodule FakeSchema do
      use Ecto.Schema
      import Ecto.Changeset

      embedded_schema do
        field(:title, :string)
        field(:isbn, :string)
        field(:count, :integer)
      end

      def cs(attrs \\ %{}) do
        %__MODULE__{}
        |> cast(attrs, [:title, :isbn, :count])
        |> validate_required([:title, :isbn])
        |> validate_length(:title, min: 3)
      end
    end

    test "translates a changeset into field => [msg, ...]" do
      errors = FakeSchema.cs(%{}) |> Caravela.errors()

      assert errors[:title] == ["can't be blank"]
      assert errors[:isbn] == ["can't be blank"]
    end

    test "interpolates %{count} placeholders from error opts" do
      errors = FakeSchema.cs(%{title: "x", isbn: "abc"}) |> Caravela.errors()
      assert errors[:title] == ["should be at least 3 character(s)"]
    end

    test "returns an empty map when the changeset has no errors" do
      changeset = FakeSchema.cs(%{title: "valid title", isbn: "978"})
      assert Caravela.errors(changeset) == %{}
    end
  end

  describe "entity_topic/2" do
    test "prefixes caravela: and lowercases atom entities" do
      assert Caravela.entity_topic(:Book, 42) == "caravela:book:actor:42"
    end

    test "lowercases string entities" do
      assert Caravela.entity_topic("Book", "alice") == "caravela:book:actor:alice"
    end

    test "omits actor segment when actor is nil" do
      assert Caravela.entity_topic(:book) == "caravela:book"
      assert Caravela.entity_topic("Report", nil) == "caravela:report"
    end
  end

  describe "broadcast_patch/3" do
    test "publishes on the conventional topic" do
      topic = Caravela.entity_topic(:book, 7)
      :ok = Phoenix.PubSub.subscribe(@pubsub, topic)

      :ok = Caravela.broadcast_patch(:book, 7, [["replace", "/title", "New"]])

      assert_receive {:caravela_svelte_patch, ^topic, [["replace", "/title", "New"]]}
    end

    test "broadcasts to the entity-wide topic when actor is nil" do
      topic = Caravela.entity_topic("Report")
      :ok = Phoenix.PubSub.subscribe(@pubsub, topic)

      :ok = Caravela.broadcast_patch("Report", nil, [["add", "/alerts/-", "x"]])

      assert_receive {:caravela_svelte_patch, ^topic, [["add", "/alerts/-", "x"]]}
    end
  end
end
