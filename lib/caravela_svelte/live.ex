defmodule CaravelaSvelte.Live do
  @moduledoc """
  Default renderer for `CaravelaSvelte` — implements the LiveView
  WebSocket transport (today's `live_svelte` behaviour).

  `prepare/1` takes the raw assigns that arrive at
  `CaravelaSvelte.svelte/1` and returns an enriched map with
  everything the HEEx template needs:

    * `:init`, `:svelte_id`, `:use_diff`
    * `:slots` — decoded for JS consumption
    * `:ssr_render` — SSR output, or `nil` when disabled / not
      first-render
    * `:props_to_send`, `:props_diff`, `:streams_diff`

  All diff / ID / encoder helpers live here too so that Phase B.2's
  `CaravelaSvelte.Rest` can reuse them without touching top-level
  `CaravelaSvelte`.
  """

  @behaviour CaravelaSvelte.Renderer

  alias Phoenix.LiveView
  alias Phoenix.LiveView.LiveStream
  alias CaravelaSvelte.Slots
  alias CaravelaSvelte.SSR

  @impl true
  def prepare(assigns) do
    init = assigns.__changed__ == nil
    dead = assigns.socket == nil or not LiveView.connected?(assigns.socket)
    ssr_active = Application.get_env(:caravela_svelte, :ssr, true)
    use_diff = diff_enabled?(assigns)

    svelte_id =
      assigns.id || key_based_id(assigns.name, assigns.key, assigns.props, assigns.__changed__)

    # Snapshot previous props BEFORE props_for_payload/5 updates the process dict.
    prev_for_diff =
      if use_diff and not init and not dead do
        case assigns.__changed__[:props] do
          old when is_map(old) -> old
          _ -> Process.get({:caravela_svelte_prev_props, svelte_id})
        end
      end

    props_to_send = props_for_payload(assigns, svelte_id, init, dead, use_diff)

    props_diff =
      if use_diff and not init and not dead and is_map(prev_for_diff) do
        assigns.props
        |> calculate_props_diff(prev_for_diff)
        |> Enum.map(&prepare_diff/1)
      else
        []
      end

    if init and ssr_active and assigns.ssr and Map.get(assigns, :loading, []) != [] do
      IO.warn(
        "The <:loading /> slot is incompatible with server-side rendering (ssr). Either remove the <:loading /> slot or set ssr={false}",
        Macro.Env.stacktrace(__ENV__)
      )
    end

    slots =
      assigns
      |> Slots.rendered_slot_map()
      |> Slots.js_process()

    ssr_code =
      if init and dead and ssr_active and assigns.ssr do
        try do
          props = Map.get(assigns, :props, %{})
          SSR.render(assigns.name, props, slots)
        rescue
          SSR.NotConfigured -> nil
        end
      end

    streams_diff = calculate_streams_diff(assigns, init or dead)

    assigns
    |> Map.put(:init, init)
    |> Map.put(:slots, slots)
    |> Map.put(:ssr_render, ssr_code)
    |> Map.put(:svelte_id, svelte_id)
    |> Map.put(:props_to_send, props_to_send)
    |> Map.put(:use_diff, use_diff)
    |> Map.put(:props_diff, props_diff)
    |> Map.put(:streams_diff, streams_diff)
  end

  # --- Props payload -------------------------------------------------

  @doc false
  def props_for_payload(assigns) do
    init = assigns.__changed__ == nil
    dead = assigns.socket == nil or not LiveView.connected?(assigns.socket)
    use_diff = diff_enabled?(assigns)
    props = Map.get(assigns, :props, %{})

    cond do
      init or dead or not use_diff ->
        props

      is_map(assigns.__changed__[:props]) ->
        props_changed_only(props, assigns.__changed__[:props])

      true ->
        props
    end
  end

  @doc false
  def props_for_payload(assigns, svelte_id, init, dead, use_diff) do
    props = Map.get(assigns, :props, %{})
    prev_key = {:caravela_svelte_prev_props, svelte_id}

    payload =
      cond do
        not use_diff -> props
        init or dead -> props
        is_map(assigns.__changed__[:props]) ->
          props_changed_only(props, assigns.__changed__[:props])

        true ->
          case Process.get(prev_key) do
            old when is_map(old) -> props_changed_only(props, old)
            _ -> props
          end
      end

    if use_diff, do: Process.put(prev_key, props)
    payload
  end

  @doc false
  def diff_enabled?(assigns) do
    config_enabled = Application.get_env(:caravela_svelte, :enable_props_diff, true)
    per_component = Map.get(assigns, :diff, true)
    config_enabled and per_component == true
  end

  @doc false
  def props_changed_only(new_props, old_props) when is_map(new_props) and is_map(old_props) do
    all_keys = (Map.keys(new_props) ++ Map.keys(old_props)) |> Enum.uniq()

    all_keys
    |> Enum.reduce(%{}, fn k, acc ->
      new_val = Map.get(new_props, k)
      old_val = Map.get(old_props, k)
      if new_val != old_val, do: Map.put(acc, k, new_val), else: acc
    end)
  end

  # --- Props diff (JSON Patch) --------------------------------------

  @doc false
  def calculate_props_diff(_current_props, nil), do: []

  def calculate_props_diff(current_props, prev_props)
      when is_map(current_props) and is_map(prev_props) do
    all_keys = (Map.keys(current_props) ++ Map.keys(prev_props)) |> Enum.uniq()

    diff =
      Enum.flat_map(all_keys, fn k ->
        in_current = Map.has_key?(current_props, k)
        in_prev = Map.has_key?(prev_props, k)
        new_v = Map.get(current_props, k)
        old_v = Map.get(prev_props, k)

        cond do
          in_current and not in_prev ->
            [%{op: "add", path: "/#{k}", value: encode_for_diff(new_v)}]

          in_prev and not in_current ->
            [%{op: "remove", path: "/#{k}"}]

          old_v == new_v ->
            []

          (is_map(old_v) or is_list(old_v)) and (is_map(new_v) or is_list(new_v)) ->
            Jsonpatch.diff(
              old_v,
              new_v,
              ancestor_path: "/#{k}",
              prepare_map: &encode_for_diff/1,
              object_hash: &object_hash/1
            )

          true ->
            [%{op: "replace", path: "/#{k}", value: encode_for_diff(new_v)}]
        end
      end)

    case diff do
      [] -> []
      ops -> [%{op: "test", path: "", value: :rand.uniform(10_000_000)} | ops]
    end
  end

  @doc false
  def prepare_diff(%{op: op, path: p, value: value}), do: [op, p, value]
  def prepare_diff(%{op: op, path: p}), do: [op, p]

  # --- Streams -------------------------------------------------------

  defp extract_streams(assigns) do
    Enum.reduce(assigns, %{}, fn {k, v}, acc ->
      if match?(%LiveStream{}, v), do: Map.put(acc, k, v), else: acc
    end)
  end

  defp calculate_streams_diff(assigns, initial) do
    streams = extract_streams(assigns)

    if streams == %{} do
      []
    else
      do_calculate_streams_diff(streams, initial)
    end
  end

  defp do_calculate_streams_diff(streams, true = _initial) do
    init_ops = Enum.map(streams, fn {k, _} -> %{op: "replace", path: "/#{k}", value: []} end)
    diff_ops = Enum.flat_map(streams, fn {k, stream} -> generate_stream_patches(k, stream) end)
    (init_ops ++ diff_ops) |> Enum.map(&prepare_diff/1)
  end

  defp do_calculate_streams_diff(streams, false = _initial) do
    streams
    |> Enum.flat_map(fn {k, stream} -> generate_stream_patches(k, stream) end)
    |> then(fn
      [] -> []
      ops -> [%{op: "test", path: "", value: :rand.uniform(10_000_000)} | ops]
    end)
    |> Enum.map(&prepare_diff/1)
  end

  defp generate_stream_patches(stream_name, stream) do
    reset? = Map.get(stream, :reset?, false)

    patches =
      if reset?,
        do: [%{op: "replace", path: "/#{stream_name}", value: []} | []],
        else: []

    patches =
      Enum.reduce(stream.deletes, patches, fn dom_id, acc ->
        [%{op: "remove", path: "/#{stream_name}/$$#{dom_id}"} | acc]
      end)

    patches =
      stream.inserts
      |> Enum.reverse()
      |> Enum.reduce(patches, fn insert, acc ->
        case insert do
          {dom_id, at, item, limit, update_only} ->
            item_map = encode_stream_item(item, dom_id)

            acc =
              if update_only do
                [%{op: "replace", path: "/#{stream_name}/$$#{dom_id}", value: item_map} | acc]
              else
                at_path = if at == -1, do: "-", else: to_string(at)
                [%{op: "upsert", path: "/#{stream_name}/#{at_path}", value: item_map} | acc]
              end

            if limit, do: [%{op: "limit", path: "/#{stream_name}", value: limit} | acc], else: acc

          {dom_id, at, item, limit} ->
            item_map = encode_stream_item(item, dom_id)
            at_path = if at == -1, do: "-", else: to_string(at)
            acc = [%{op: "upsert", path: "/#{stream_name}/#{at_path}", value: item_map} | acc]
            if limit, do: [%{op: "limit", path: "/#{stream_name}", value: limit} | acc], else: acc

          {dom_id, at, item} ->
            item_map = encode_stream_item(item, dom_id)
            at_path = if at == -1, do: "-", else: to_string(at)
            [%{op: "upsert", path: "/#{stream_name}/#{at_path}", value: item_map} | acc]
        end
      end)

    Enum.reverse(patches)
  end

  defp encode_stream_item(item, dom_id) do
    item
    |> CaravelaSvelte.Encoder.encode([])
    |> Map.put(:__dom_id, dom_id)
  end

  defp encode_for_diff(struct) when is_struct(struct),
    do: CaravelaSvelte.Encoder.encode(struct)

  defp encode_for_diff(other), do: other

  defp object_hash(%{id: id}) when not is_nil(id), do: id
  defp object_hash(_), do: nil

  # --- JSON ----------------------------------------------------------

  @doc false
  def json(props) do
    json_library =
      Application.get_env(:caravela_svelte, :json_library, CaravelaSvelte.JSON)

    if json_library == CaravelaSvelte.JSON do
      json_library.encode!(props)
    else
      props
      |> CaravelaSvelte.Encoder.encode([])
      |> json_library.encode!()
    end
  end

  # --- Deterministic ID generation ----------------------------------

  defp key_based_id(name, key, _props, _changed) when not is_nil(key) do
    "#{name}-#{key}"
  end

  defp key_based_id(name, nil, props, changed) do
    case extract_identity(props) do
      nil ->
        maybe_reset_id_counters_for_update(changed)
        counter_id(name)

      identity ->
        "#{name}-#{identity}"
    end
  end

  @identity_keys [:id, "id", :key, "key", :index, "index", :idx, "idx"]

  defp extract_identity(props) when is_map(props) do
    Enum.find_value(@identity_keys, fn k -> Map.get(props, k) end)
  end

  defp extract_identity(_), do: nil

  defp maybe_reset_id_counters_for_update(nil), do: :ok

  defp maybe_reset_id_counters_for_update(_changed) do
    total = Process.get(:caravela_svelte_total_counter, 0)
    expected = Process.get(:caravela_svelte_expected_total, :not_set)

    should_reset =
      case expected do
        :not_set -> total > 0
        n -> total >= n
      end

    if should_reset do
      Process.put(:caravela_svelte_expected_total, total)

      for name <- Process.get(:caravela_svelte_counter_names, []) do
        Process.put({:caravela_svelte_counter, name}, 0)
      end

      Process.put(:caravela_svelte_total_counter, 0)
    end

    :ok
  end

  defp counter_id(name) do
    Process.put(
      :caravela_svelte_counter_names,
      Enum.uniq([name | Process.get(:caravela_svelte_counter_names, [])])
    )

    Process.put(
      :caravela_svelte_total_counter,
      Process.get(:caravela_svelte_total_counter, 0) + 1
    )

    key = {:caravela_svelte_counter, name}
    count = Process.get(key, 0)
    Process.put(key, count + 1)
    if count == 0, do: name, else: "#{name}-#{count}"
  end
end
