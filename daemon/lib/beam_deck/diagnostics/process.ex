defmodule BeamDeck.Diagnostics.Process do
  @moduledoc "Focused OTP metadata, never sys:get_state, messages or a complete dictionary."
  alias BeamDeck.{Redaction, Remote}

  @fields [
    :registered_name,
    :status,
    :current_function,
    :initial_call,
    :current_stacktrace,
    :message_queue_len,
    :memory,
    :reductions,
    :heap_size,
    :total_heap_size,
    :stack_size
  ]

  def inspect_process(node, text, opts) do
    deadline = System.monotonic_time(:millisecond) + opts["process_timeout_ms"]

    with {:ok, creation} when is_integer(creation) <-
           rpc(node, :erlang, :system_info, [:creation], deadline),
         {:ok, pid} <- Remote.parse_pid(node, text),
         {:ok, info} when is_list(info) <-
           rpc(node, :erlang, :process_info, [pid, @fields], deadline) do
      data = Map.new(info)
      binaries = binaries(node, pid, opts, deadline)
      {ancestry, warnings} = ancestry(node, pid, opts, deadline)

      result = %{
        node: Atom.to_string(node),
        creation: creation,
        pid: text,
        at_ms: System.system_time(:millisecond),
        registered_name:
          if(is_atom(data[:registered_name]) and data[:registered_name] not in [nil, :undefined],
            do: Atom.to_string(data[:registered_name]),
            else: nil
          ),
        status: data[:status],
        current_function: frame(data[:current_function]),
        initial_call: frame(data[:initial_call]),
        stack:
          Enum.map(
            Enum.take(data[:current_stacktrace] || [], opts["process_stack_frames"]),
            &frame/1
          ),
        mailbox: data[:message_queue_len],
        memory_bytes: data[:memory],
        reductions: data[:reductions],
        heap_words: data[:heap_size],
        total_heap_words: data[:total_heap_size],
        stack_words: data[:stack_size],
        ancestry: ancestry,
        binaries: binaries,
        warnings: warnings ++ binary_warning(binaries),
        exclusions:
          "No state, message contents, dictionary dump, binary contents or arbitrary evaluation."
      }

      {:ok, Redaction.sanitize(result)}
    else
      {:ok, :undefined} -> {:error, :process_exited}
      _ -> {:error, :process_unavailable}
    end
  end

  def frame({mod, fun, arity}) when is_atom(mod) and is_atom(fun) and is_integer(arity),
    do: %{module: Atom.to_string(mod), function: Atom.to_string(fun), arity: arity}

  def frame({mod, fun, args, location}) when is_atom(mod) and is_atom(fun) do
    arity =
      if is_integer(args),
        do: args,
        else: if(is_list(args), do: length(Enum.take(args, 256)), else: nil)

    line = if is_list(location), do: Keyword.get(location, :line), else: nil
    %{module: Atom.to_string(mod), function: Atom.to_string(fun), arity: arity, line: line}
  end

  def frame(_), do: nil

  def binary_summary(rows, cap) when is_list(rows) do
    selected = Enum.take(rows, cap)

    valid =
      for {id, size, refs} <- selected,
          is_integer(id),
          is_integer(size),
          is_integer(refs),
          do: %{id: id, bytes: size, references: refs}

    unique = Enum.uniq_by(valid, & &1.id)
    malformed = length(valid) != length(selected)

    %{
      status: if(malformed, do: "binary_summary_unavailable", else: "available"),
      sampled_entries: length(selected),
      total_entries: length(rows),
      partial: malformed or length(rows) > cap,
      referenced_bytes: if(malformed, do: nil, else: Enum.sum(Enum.map(unique, & &1.bytes))),
      top:
        if(malformed,
          do: [],
          else:
            unique
            |> Enum.sort_by(& &1.bytes, :desc)
            |> Enum.take(10)
            |> Enum.map(&Map.drop(&1, [:id]))
        ),
      accounting:
        "Observed off-heap references; shared bytes are not exclusive process ownership."
    }
  end

  def binary_summary(_, _), do: %{status: "unsupported", partial: true, top: []}

  defp binaries(node, pid, opts, deadline) do
    case rpc(node, :erlang, :process_info, [pid, :binary], deadline) do
      {:ok, {:binary, rows}} -> binary_summary(rows, opts["process_binary_entries"])
      _ -> %{status: "unavailable", partial: true, top: []}
    end
  end

  defp binary_warning(%{partial: true}),
    do: ["Binary reference metadata is incomplete or unavailable."]

  defp binary_warning(_), do: []

  defp ancestry(node, pid, opts, deadline) do
    # OTP 27+ supports this single-key form. Never fall back to a full dictionary.
    case rpc(node, :erlang, :process_info, [pid, {:dictionary, :"$ancestors"}], deadline) do
      {:ok, {{:dictionary, :"$ancestors"}, ancestors}} when is_list(ancestors) ->
        ancestry_rows(node, pid, ancestors, opts, deadline)

      {:ok, {{:dictionary, :"$ancestors"}, :undefined}} ->
        {[], []}

      _ ->
        {[], ["Focused ancestry is unavailable; no dictionary fallback was attempted."]}
    end
  end

  defp ancestry_rows(node, pid, ancestors, opts, deadline) do
    selected = Enum.take(ancestors, opts["process_ancestry_depth"])

    {rows, _child} =
      Enum.map_reduce(selected, pid, fn ancestor, child ->
        ancestry_row(node, ancestor, child, deadline)
      end)

    warnings =
      if length(ancestors) > length(selected), do: ["Ancestry depth capped."], else: []

    {rows, warnings}
  end

  defp ancestry_row(node, ancestor, child, deadline) do
    case ancestor_pid(node, ancestor, deadline) do
      {:ok, parent} ->
        # An ancestor is not necessarily a supervisor. A live process that does
        # not implement supervisor calls must not consume the whole report.
        child_deadline = min(deadline, System.monotonic_time(:millisecond) + 200)
        focused = child_info(node, parent, child, child_deadline)
        {%{pid: Remote.pid_text(parent), name: ancestor_name(ancestor), child: focused}, parent}

      _ ->
        {%{name: ancestor_name(ancestor), status: "unavailable"}, child}
    end
  end

  defp ancestor_pid(node, pid, _deadline) when is_pid(pid) do
    if node(pid) == node, do: {:ok, pid}, else: {:error, :foreign_parent}
  end

  defp ancestor_pid(node, name, deadline) when is_atom(name) do
    case rpc(node, :erlang, :whereis, [name], deadline) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      _ -> {:error, :missing}
    end
  end

  defp ancestor_pid(_node, _other, _deadline), do: {:error, :unsupported}
  defp ancestor_name(name) when is_atom(name), do: Redaction.text(name, 255)
  defp ancestor_name(_), do: nil

  defp child_info(node, parent, child, deadline) do
    case rpc(node, :supervisor, :which_child, [parent, child], deadline) do
      {:ok, {:ok, row}} -> child_row(row)
      _ -> small_supervisor_child(node, parent, child, deadline)
    end
  end

  defp small_supervisor_child(node, parent, child, deadline) do
    with {:ok, counts} when is_list(counts) <-
           rpc(node, :supervisor, :count_children, [parent], deadline),
         specs when is_integer(specs) and specs <= 100 <- Keyword.get(counts, :specs),
         active when is_integer(active) and active <= 100 <- Keyword.get(counts, :active),
         {:ok, rows} when is_list(rows) <-
           rpc(node, :supervisor, :which_children, [parent], deadline),
         row when not is_nil(row) <-
           Enum.find(Enum.take(rows, 100), fn {_id, pid, _type, _modules} -> pid == child end) do
      child_row(row)
    else
      _ -> %{status: "unavailable_or_capped"}
    end
  end

  defp child_row({id, pid, type, modules}) do
    # Child IDs may be arbitrary application terms: only primitive identifiers are exposed.
    %{
      id: Redaction.text(id, 120),
      pid: Remote.pid_text(pid),
      type: type,
      modules:
        if(is_list(modules),
          do: Enum.take(modules, 8) |> Enum.map(&Redaction.text(&1, 120)),
          else: []
        )
    }
  end

  defp rpc(node, mod, fun, args, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0,
      do: Remote.call_raw(node, mod, fun, args, remaining),
      else: {:error, :timeout}
  end
end
