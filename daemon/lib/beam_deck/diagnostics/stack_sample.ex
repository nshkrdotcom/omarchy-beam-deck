defmodule BeamDeck.Diagnostics.StackSample do
  @moduledoc "Explicit argument-free stack observations; not a CPU or allocation profiler."
  alias BeamDeck.Diagnostics.Interval
  alias BeamDeck.Diagnostics.Process, as: ProcessDiagnostics

  alias BeamDeck.Diagnostics.Window
  alias BeamDeck.{Redaction, Remote}

  def run(node, text, duration) do
    count = min(div(duration, 250), 20)
    deadline = System.monotonic_time(:millisecond) + duration + 2000

    with {:ok, creation} <- Window.creation(node),
         {:ok, pid} <- Remote.parse_pid(node, text),
         {entries, reason} <- collect(node, pid, count, deadline, []),
         {:ok, current} <- Window.creation(node),
         true <- creation == current do
      finish(entries, reason, count, node, text, creation)
    else
      false -> {:error, :incomparable_identity}
      error -> error
    end
  end

  defp collect(_node, _pid, 0, _deadline, acc), do: {Enum.reverse(acc), "complete"}

  defp collect(node, pid, remaining, deadline, acc) do
    left = deadline - System.monotonic_time(:millisecond)

    if left <= 0 do
      {Enum.reverse(acc), "deadline"}
    else
      collect_next(node, pid, remaining, deadline, acc, left)
    end
  end

  defp collect_next(node, pid, remaining, deadline, acc, left) do
    fields = [:status, :current_stacktrace, :memory, :message_queue_len, :reductions]

    case Remote.call_raw(node, :erlang, :process_info, [pid, fields], min(left, 500)) do
      {:ok, info} when is_list(info) ->
        data = Map.new(info)

        sample = %{
          mono_ms: System.monotonic_time(:millisecond),
          at_ms: System.system_time(:millisecond),
          stack: data[:current_stacktrace],
          status: data[:status],
          memory_bytes: data[:memory],
          mailbox: data[:message_queue_len],
          reductions: data[:reductions]
        }

        if remaining > 1, do: Process.sleep(250)
        collect(node, pid, remaining - 1, deadline, [sample | acc])

      {:ok, :undefined} ->
        {Enum.reverse(acc), "process_exited"}

      _ ->
        {Enum.reverse(acc), "sample_unavailable"}
    end
  end

  defp finish([], "process_exited", _count, _node, _text, _creation),
    do: {:error, :process_exited}

  defp finish([], _reason, _count, _node, _text, _creation), do: {:error, :sample_unavailable}

  defp finish(entries, reason, count, node, text, creation) do
    result =
      summarize(entries, count)
      |> Map.merge(%{
        kind: "sample_process",
        node: Atom.to_string(node),
        creation: creation,
        pid: text,
        from_at_ms: hd(entries).at_ms,
        at_ms: List.last(entries).at_ms,
        outcome: reason,
        partial: reason != "complete",
        warning:
          "Stack frequencies are observations, not CPU time, call counts or allocation attribution. Waiting and short-lived work can dominate or be missed. No trace or target flag was enabled."
      })

    {:ok, Redaction.sanitize(result)}
  end

  def summarize(entries, requested) do
    entries = Enum.take(entries, 20)

    stacks =
      entries
      |> Enum.map(fn e ->
        Enum.take(e[:stack] || [], 20)
        |> Enum.map(&ProcessDiagnostics.frame/1)
        |> Enum.reject(&is_nil/1)
      end)
      |> Enum.reject(&(&1 == []))
      |> Enum.frequencies()
      |> Enum.map(fn {frames, count} ->
        %{
          key: Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(frames))),
          frames: frames,
          count: count
        }
      end)
      |> Enum.sort_by(&{-&1.count, &1.key})
      |> Enum.take(40)

    statuses =
      entries
      |> Enum.frequencies_by(&status(&1[:status]))
      |> Enum.map(fn {s, count} -> %{status: s, count: count} end)
      |> Enum.sort_by(& &1.status)

    first = List.first(entries) || %{}
    last = List.last(entries) || %{}
    span = if entries == [], do: 0, else: last.mono_ms - first.mono_ms

    Interval.deltas(first, last, span)
    |> Map.merge(%{
      samples: length(entries),
      requested_samples: requested,
      missed_samples: max(0, requested - length(entries)),
      span_ms: span,
      stacks: stacks,
      statuses: statuses,
      stack_samples: Enum.sum(Enum.map(stacks, & &1.count)),
      partial: length(entries) < requested
    })
  end

  defp status(value)
       when value in [:waiting, :running, :runnable, :suspended, :garbage_collecting, :exiting],
       do: Atom.to_string(value)

  defp status(_), do: "unknown"
end
