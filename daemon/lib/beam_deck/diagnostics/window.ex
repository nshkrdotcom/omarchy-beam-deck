defmodule BeamDeck.Diagnostics.Window do
  @moduledoc "Two deliberate capped metadata captures; no persistent sampling loop."
  alias BeamDeck.Diagnostics.{Ets, Interval}
  alias BeamDeck.{Redaction, Remote}

  def run(kind, node, duration, opts) do
    with {:ok, first} <- capture(kind, node, opts),
         :ok <- Process.sleep(duration),
         {:ok, last} <- capture(kind, node, opts) do
      Interval.compare(kind, first, last)
    end
  end

  def creation(node) do
    case Remote.call_raw(node, :erlang, :system_info, [:creation], 500) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      _ -> {:error, :node_unavailable}
    end
  end

  def capture(kind, node, opts) do
    with {:ok, before} <- creation(node),
         {:ok, sample} <- collect(kind, node, opts),
         {:ok, after_creation} <- creation(node),
         true <- before == after_creation do
      {:ok,
       Map.merge(sample, %{
         node: Atom.to_string(node),
         creation: before,
         mono_ms: System.monotonic_time(:millisecond),
         at_ms: System.system_time(:millisecond)
       })}
    else
      false -> {:error, :incomparable_identity}
      error -> error
    end
  end

  defp collect("process_window", node, opts) do
    limit = min(opts["window_max_processes"] || 10_000, 10_000)

    with {:ok, count} when is_integer(count) <-
           Remote.call_raw(node, :erlang, :system_info, [:process_count], 500),
         true <- count <= limit,
         {:ok, _} <- Remote.call_raw(node, :observer_backend, :procs_info, [self()], 3000) do
      {rows, seen} = receive_rows(node, [], 0, limit)

      if rows == [],
        do: {:error, :process_survey_unavailable},
        else: {:ok, %{rows: rows, scanned: length(rows), total: count, partial: seen > limit}}
    else
      false -> {:error, :process_survey_population_capped}
      _ -> {:error, :process_survey_unavailable}
    end
  end

  defp collect("ets_window", node, opts) do
    limit = min(opts["ets_max_tables"], 256)

    opts =
      Map.merge(opts, %{
        "ets_max_tables" => limit,
        "ets_top_rows" => limit,
        "ets_timeout_ms" => min(opts["ets_timeout_ms"], 5000)
      })

    with {:ok, report} <- Ets.inspect_tables(node, "memory", opts) do
      {:ok,
       %{
         rows: report.top,
         scanned: report.scanned_tables,
         total: report.total_tables,
         partial: report.partial
       }}
    end
  end

  defp receive_rows(target, acc, seen, limit) do
    receive do
      {:procs_info, pid, rows} when node(pid) == target and is_list(rows) ->
        selected = Enum.take(rows, max(0, limit - length(acc))) |> Enum.map(&process_row/1)
        receive_rows(target, selected ++ acc, seen + length(rows), limit)
    after
      0 -> {acc, seen}
    end
  end

  defp process_row(raw) do
    row = Remote.proc_row(raw)
    # Observer may render arbitrary process labels; keep only registered names or MFA names.
    name =
      if row[:identity_kind] in ["registered", "initial_call"],
        do: Redaction.text(row.name, 255),
        else: "unregistered"

    row
    |> Map.take([:pid, :memory_bytes, :reductions, :mailbox, :current_function])
    |> Map.put(:name, name)
    |> Redaction.sanitize()
  end
end
