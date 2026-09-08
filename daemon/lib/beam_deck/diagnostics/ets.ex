defmodule BeamDeck.Diagnostics.Ets do
  @moduledoc "ETS metadata only. No lookup, match, select, fold or table-value transfer."
  alias BeamDeck.{Redaction, Remote}

  def inspect_tables(node, sort, opts) do
    deadline =
      System.monotonic_time(:millisecond) +
        opts["ets_timeout_ms"]

    with {:ok, tables} when is_list(tables) <-
           rpc(node, :ets, :all, [], deadline),
         {:ok, wordsize} when wordsize in [4, 8] <-
           rpc(
             node,
             :erlang,
             :system_info,
             [:wordsize],
             deadline
           ) do
      selected =
        tables
        |> Enum.sort()
        |> Enum.take(opts["ets_max_tables"])

      rows =
        inspect_rows(
          node,
          selected,
          wordsize,
          deadline,
          opts
        )

      {:ok,
       ets_report(
         node,
         sort,
         wordsize,
         tables,
         selected,
         rows,
         opts
       )}
    else
      _ -> {:error, :ets_unavailable}
    end
  end

  defp inspect_rows(
         node,
         selected,
         wordsize,
         deadline,
         opts
       ) do
    selected
    |> Task.async_stream(
      fn table ->
        inspect_table(
          node,
          table,
          wordsize,
          deadline
        )
      end,
      max_concurrency: opts["ets_concurrency"],
      ordered: false,
      timeout: opts["ets_timeout_ms"],
      on_timeout: :kill_task
    )
    |> Enum.flat_map(&table_result/1)
  end

  defp inspect_table(node, table, wordsize, deadline) do
    case rpc(node, :ets, :info, [table], deadline) do
      {:ok, info} when is_list(info) ->
        info
        |> normalize(table, wordsize)
        |> Map.put(
          :owner_name,
          owner_name(node, info, deadline)
        )

      _ ->
        nil
    end
  end

  defp owner_name(node, info, deadline) do
    owner = Keyword.get(info, :owner)

    case rpc(
           node,
           :erlang,
           :process_info,
           [owner, :registered_name],
           deadline
         ) do
      {:ok, {:registered_name, name}}
      when is_atom(name) ->
        Atom.to_string(name)

      _ ->
        nil
    end
  end

  defp table_result({:ok, row}) when is_map(row),
    do: [row]

  defp table_result(_), do: []

  defp ets_report(
         node,
         sort,
         wordsize,
         tables,
         selected,
         rows,
         opts
       ) do
    key =
      if sort == "size",
        do: :size,
        else: :memory_bytes

    top =
      rows
      |> Enum.sort_by(
        &{&1[key], &1.name},
        :desc
      )
      |> Enum.take(opts["ets_top_rows"])

    Redaction.sanitize(%{
      node: Atom.to_string(node),
      at_ms: System.system_time(:millisecond),
      sort: sort,
      wordsize: wordsize,
      total_tables: length(tables),
      attempted_tables: length(selected),
      scanned_tables: length(rows),
      partial: length(rows) < length(tables),
      top: top,
      sampled_memory_bytes: Enum.sum(Enum.map(rows, & &1.memory_bytes)),
      warning:
        "Metadata is a racing observation, not an atomic table snapshot; no ETS contents collected."
    })
  end

  def normalize(info, table, wordsize) do
    data = Map.new(info)

    %{
      id: if(is_atom(table), do: Atom.to_string(table), else: inspect(table, limit: 1)),
      identity:
        if(is_reference(data[:id]),
          do: Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(data[:id])))
        ),
      name: Redaction.text(data[:name], 255),
      owner: Remote.pid_text(data[:owner]),
      size: number(data[:size]),
      memory_words: number(data[:memory]),
      memory_bytes: number(data[:memory]) * wordsize,
      type: data[:type],
      protection: data[:protection],
      named_table: data[:named_table] == true,
      read_concurrency: data[:read_concurrency],
      write_concurrency: data[:write_concurrency]
    }
  end

  defp number(n) when is_integer(n) and n >= 0, do: n
  defp number(_), do: 0

  defp rpc(node, mod, fun, args, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0,
      do: Remote.call_raw(node, mod, fun, args, min(remaining, 1_000)),
      else: {:error, :timeout}
  end
end
