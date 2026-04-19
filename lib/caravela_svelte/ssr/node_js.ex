defmodule CaravelaSvelte.SSR.NodeJS do
  @moduledoc false
  @behaviour CaravelaSvelte.SSR

  def render(name, props, slots) do
    # Prepare props and slots for JSON serialization before passing to NodeJS.
    # This converts structs to maps, DateTime to ISO 8601 strings, and strips
    # Ecto metadata (__meta__). Required because NodeJS.call! uses Jason internally.
    prepared_props = CaravelaSvelte.JSON.prepare(props)
    prepared_slots = CaravelaSvelte.JSON.prepare(slots)

    try do
      NodeJS.call!({"server", "render"}, [name, prepared_props, prepared_slots], binary: true)
    catch
      :exit, {:noproc, _} ->
        message = """
        NodeJS is not configured. Please add the following to your application.ex:
        {NodeJS.Supervisor, [path: CaravelaSvelte.SSR.NodeJS.server_path(), pool_size: 4]},
        """

        raise %CaravelaSvelte.SSR.NotConfigured{message: message}
    end
  end

  def server_path() do
    {:ok, path} = :application.get_application()
    Application.app_dir(path, "/priv/svelte")
  end
end
