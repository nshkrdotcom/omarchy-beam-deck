defmodule BeamDeck.Discovery do
  @moduledoc false

  @node_re ~r/^[A-Za-z0-9_.-]+@[A-Za-z0-9_.:-]+$/

  def candidates(config, learned \\ []) do
    epmd = epmd_nodes()
    explicit = config["nodes"] |> List.wrap() |> Enum.map(&node_name/1) |> Enum.reject(&is_nil/1)
    learned = learned |> Enum.map(&node_name/1) |> Enum.reject(&is_nil/1)

    (epmd ++ explicit ++ learned)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&helper_node?/1)
    |> Enum.take(64)
  end

  def epmd_nodes do
    host = System.get_env("BEAM_DECK_LOCAL_HOST") || local_short_host()

    case :net_adm.names() do
      {:ok, names} ->
        for {name, _port} <- names,
            not String.starts_with?(to_string(name), "beam_deck_") do
          safe_node("#{name}@#{host}")
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def node_name(%{"name" => name}) when is_binary(name), do: safe_node(name)
  def node_name(name) when is_binary(name), do: safe_node(name)
  def node_name(name) when is_atom(name), do: name
  def node_name(_), do: nil

  def local_node?(node) when is_atom(node), do: local_node?(Atom.to_string(node))

  def local_node?(name) when is_binary(name) do
    case String.split(name, "@", parts: 2) do
      [_node, host] ->
        local = local_short_host()
        host in [local, System.get_env("BEAM_DECK_LOCAL_HOST"), "localhost", "127.0.0.1", "::1"]

      _ ->
        false
    end
  end

  def local_node?(_), do: false

  def metadata(config, node) do
    name = to_string(node)

    case Enum.find(List.wrap(config["nodes"]), fn entry ->
           is_map(entry) and entry["name"] == name
         end) do
      nil ->
        %{configured: false, required: false, expected_peers: []}

      entry ->
        expected =
          entry["expected_peers"]
          |> List.wrap()
          |> Enum.filter(&(is_binary(&1) and Regex.match?(@node_re, &1)))

        %{
          configured: true,
          required: entry["required"] == true,
          expected_peers: Enum.uniq(expected)
        }
    end
  end

  def apply_cookie(entry) when is_map(entry) do
    with name when is_binary(name) <- entry["name"],
         env when is_binary(env) <- entry["cookie_env"],
         cookie when is_binary(cookie) and byte_size(cookie) in 1..255 <- System.get_env(env),
         node when not is_nil(node) <- safe_node(name) do
      :erlang.set_cookie(node, String.to_atom(cookie))
      :ok
    else
      _ -> :skip
    end
  end

  def apply_cookie(_), do: :skip

  defp safe_node(name) do
    if BeamDeck.Protocol.node_name?(name) do
      :global.trans({{__MODULE__, :admission}, self()}, fn ->
        known = :persistent_term.get({__MODULE__, :known}, %{})
        cond do
          Map.has_key?(known, name) -> known[name]
          map_size(known) >= 1_024 -> nil
          true ->
            atom = String.to_atom(name)
            :persistent_term.put({__MODULE__, :known}, Map.put(known, name, atom))
            atom
        end
      end, [node()])
    end
  end

  defp helper_node?(node), do: node |> Atom.to_string() |> String.starts_with?("beam_deck_")

  def local_short_host do
    {:ok, host} = :inet.gethostname()
    to_string(host)
  end
  def existing_node(name) do
    if BeamDeck.Protocol.node_name?(name), do: {:ok, String.to_existing_atom(name)}, else: {:error, :invalid_node}
  rescue
    ArgumentError -> {:error, :unknown_node}
  end

end
