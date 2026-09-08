defmodule BeamDeck.Watchlist do
  @moduledoc "User-owned persistent pins, resolved by registered name rather than transient PID."
  alias BeamDeck.{Json, PrivateFile, Remote}
  def path, do: Path.join(Path.dirname(BeamDeck.Config.default_path()), "watchlist.json")

  def load(file \\ path()) do
    with {:ok, %{type: :regular, size: size}}
         when size <= 262_144 <- File.lstat(file),
         {:ok, bytes} <- File.read(file),
         {:ok, %{"schema" => 1, "entries" => entries}} <-
           Json.decode(bytes),
         true <-
           is_list(entries) and length(entries) <= 256 do
      validate_loaded_entries(entries)
    else
      {:error, :enoent} -> {[], nil}
      _ -> {[], "invalid_watchlist"}
    end
  end

  defp validate_loaded_entries(entries) do
    normalized = Enum.map(entries, &normalize/1)

    if Enum.all?(normalized, &match?({:ok, _}, &1)) do
      normalized
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq_by(& &1["id"])
      |> validate_loaded_limits()
    else
      {[], "invalid_watchlist"}
    end
  end

  defp validate_loaded_limits(entries) do
    counts =
      entries
      |> Enum.filter(&(&1["kind"] == "registered_process"))
      |> Enum.frequencies_by(& &1["node"])

    if Enum.all?(
         counts,
         fn {_node, count} -> count <= 64 end
       ),
       do: {entries, nil},
       else: {[], "watchlist_limit"}
  end

  def save(entries, file \\ path()),
    do: PrivateFile.write(file, Json.encode(%{schema: 1, entries: entries}))

  def add(entries, proposed, observed, config, file \\ path()) do
    with {:ok, entry} <- normalize(proposed),
         true <- observed?(entry, observed),
         true <-
           Enum.any?(entries, &(&1["id"] == entry["id"])) or
             length(entries) < config["watchlist_max_entries"],
         true <-
           Enum.any?(entries, &(&1["id"] == entry["id"])) or
             per_node_count(entries, entry) < config["watchlist_max_processes_per_node"] do
      updated = (entries ++ [entry]) |> Enum.uniq_by(& &1["id"])

      case save(updated, file) do
        :ok -> {:ok, updated}
        _ -> {:error, :watchlist_write_failed}
      end
    else
      false -> {:error, :pin_not_observed_or_limit}
      {:error, _} = error -> error
    end
  end

  def remove(entries, id, file \\ path()) do
    updated = Enum.reject(entries, &(&1["id"] == id))

    case save(updated, file) do
      :ok -> {:ok, updated}
      _ -> {:error, :watchlist_write_failed}
    end
  end

  def normalize(entry) when is_map(entry) do
    kind = entry["kind"]
    node = entry["node"]
    name = normalized_name(kind, entry["name"])
    label = entry["label"] || default_label(kind, node, name)

    if valid_pin?(kind, node, name, label) do
      {:ok, normalized_pin(kind, node, name, label)}
    else
      {:error, :invalid_pin}
    end
  end

  def normalize(_), do: {:error, :invalid_pin}

  defp normalized_name("node", _name), do: ""
  defp normalized_name(_kind, name), do: name || ""

  defp default_label("node", node, _name), do: node
  defp default_label(_kind, _node, name), do: name

  defp valid_pin?(kind, node, name, label) do
    kind in ["node", "registered_process"] and BeamDeck.Protocol.node_name?(node) and
      valid_label?(label) and valid_pin_name?(kind, name)
  end

  defp valid_label?(label) do
    is_binary(label) and String.valid?(label) and String.printable?(label) and
      byte_size(label) <= 80
  end

  defp valid_pin_name?("node", _name), do: true

  defp valid_pin_name?("registered_process", name) do
    is_binary(name) and byte_size(name) in 1..255 and String.valid?(name) and
      String.printable?(name)
  end

  defp valid_pin_name?(_kind, _name), do: false

  defp normalized_pin(kind, node, name, label) do
    identity = Enum.join([kind, node, name], "\0")

    id =
      "pin-" <>
        (:crypto.hash(:sha256, identity) |> Base.encode16(case: :lower) |> binary_part(0, 20))

    %{"id" => id, "kind" => kind, "node" => node, "name" => name, "label" => label}
  end

  defp observed?(entry, nodes) do
    case Enum.find(nodes, &(&1.name == entry["node"])) do
      nil ->
        false

      node ->
        entry["kind"] == "node" or
          Enum.any?(node[:registered_processes] || [], &(&1.name == entry["name"]))
    end
  end

  defp per_node_count(_entries, %{"kind" => "node"}), do: 0

  defp per_node_count(entries, entry),
    do: Enum.count(entries, &(&1["node"] == entry["node"] and &1["kind"] == "registered_process"))

  def poll(entries, nodes) do
    deadline =
      System.monotonic_time(:millisecond) + 3_000

    offset =
      if entries == [],
        do: 0,
        else:
          rem(
            System.unique_integer([:positive]),
            length(entries)
          )

    rotated =
      Enum.drop(entries, offset) ++ Enum.take(entries, offset)

    rows =
      Enum.map(
        rotated,
        &poll_entry(&1, nodes, deadline)
      )

    by_id = Map.new(rows, &{&1["id"], &1})
    Enum.map(entries, &by_id[&1["id"]])
  end

  defp poll_entry(entry, nodes, deadline) do
    node =
      Enum.find(
        nodes,
        &(&1.name == entry["node"])
      )

    data = poll_data(entry, node, deadline)

    data =
      if data.status in ["present", "missing"],
        do:
          Map.merge(data, %{
            observed_at_ms: System.system_time(:millisecond),
            creation: node && node[:creation]
          }),
        else: data

    Map.merge(
      entry,
      Map.new(
        data,
        fn {key, value} ->
          {Atom.to_string(key), value}
        end
      )
    )
  end

  defp poll_data(_entry, nil, _deadline),
    do: %{status: "node_unavailable"}

  defp poll_data(entry, node, deadline) do
    cond do
      not node[:attached] ->
        %{status: "node_unavailable"}

      System.monotonic_time(:millisecond) >=
          deadline ->
        %{status: "deferred"}

      entry["kind"] == "node" ->
        %{status: "present"}

      true ->
        poll_registered(entry)
    end
  end

  defp poll_registered(entry) do
    case BeamDeck.Discovery.existing_node(entry["node"]) do
      {:ok, atom} ->
        resolve(atom, entry["name"])

      _ ->
        %{status: "node_unavailable"}
    end
  end

  def retain_observations(rows, previous) do
    old = Map.new(previous, &{&1["id"], &1})

    Enum.map(rows, fn row ->
      if row["status"] in ["deferred", "unavailable", "node_unavailable"] and old[row["id"]] do
        old[row["id"]]
        |> Map.take(~w(pid mailbox memory_bytes reductions observed_at_ms creation))
        |> Map.merge(row)
        |> Map.put("stale", true)
      else
        Map.put(row, "stale", false)
      end
    end)
  end

  def resolve(node, name) do
    with {:ok, atom} when is_atom(atom) <-
           Remote.call_raw(node, :erlang, :list_to_existing_atom, [String.to_charlist(name)], 500),
         {:ok, pid} when is_pid(pid) <- Remote.call_raw(node, :erlang, :whereis, [atom], 500),
         {:ok, info} when is_list(info) <-
           Remote.call_raw(
             node,
             :erlang,
             :process_info,
             [
               pid,
               [
                 :message_queue_len,
                 :memory,
                 :reductions,
                 :registered_name,
                 :status,
                 :current_function
               ]
             ],
             500
           ),
         true <- Keyword.get(info, :registered_name) == atom do
      %{
        status: "present",
        pid: Remote.pid_text(pid),
        mailbox: info[:message_queue_len],
        memory_bytes: info[:memory],
        reductions: info[:reductions],
        process_status: info[:status],
        current_function: BeamDeck.Diagnostics.Process.frame(info[:current_function])
      }
    else
      {:ok, :undefined} -> %{status: "missing"}
      {:error, {:exception, :badarg, _}} -> %{status: "missing"}
      {:error, :badarg} -> %{status: "missing"}
      false -> %{status: "missing"}
      _ -> %{status: "unavailable"}
    end
  end
end
