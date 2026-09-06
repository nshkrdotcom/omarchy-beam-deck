defmodule BeamDeck.Remote do
  @moduledoc false

  @timeout 1_500

  def connect(node) when is_atom(node) do
    case call_raw(node, :erlang, :node, [], 1_500) do
      {:ok, ^node} -> :ok
      _ -> {:error, :unreachable}
    end
  end

  def inspect_node(node, opts \\ %{}) do
    with :ok <- connect(node), {:ok, sys, observer_backend?} <- sys_info(node) do
      apps = call(node, :application, :which_applications, [], []) |> normalize_apps()

      peers =
        node
        |> all_peers()
        |> Enum.map(&to_string/1)
        |> Enum.reject(&String.starts_with?(&1, "beam_deck_"))

      runqs = call(node, :erlang, :statistics, [:run_queue_lengths], nil)
      total_runqs = call(node, :erlang, :statistics, [:total_run_queue_lengths], nil)
      elixir = call(node, Elixir.System, :version, [], nil)

      node_map = %{
        name: Atom.to_string(node),
        attached: true,
        local: BeamDeck.Discovery.local_node?(node),
        otp: text(sys[:otp_release]),
        erts: text(sys[:version]),
        elixir: text(elixir),
        os_pid: call(node, :os, :getpid, [], "") |> text() |> int_text(),
        creation: call(node, :erlang, :system_info, [:creation], nil),
        uptime_ms: num(sys[:uptime]),
        processes: num(sys[:process_count]),
        process_limit: num(sys[:process_limit]),
        atoms: num(sys[:atom_count]),
        atom_limit: num(sys[:atom_limit]),
        ports: num(sys[:port_count]),
        port_limit: num(sys[:port_limit]),
        ets: num(sys[:ets_count]),
        ets_limit: num(sys[:ets_limit]),
        schedulers: num(sys[:schedulers]),
        schedulers_online: num(sys[:schedulers_online]),
        dirty_cpu_schedulers: num(call(node, :erlang, :system_info, [:dirty_cpu_schedulers], 0)),
        dirty_cpu_schedulers_online:
          num(call(node, :erlang, :system_info, [:dirty_cpu_schedulers_online], 0)),
        run_queue: num(sys[:run_queue]),
        run_queue_lengths: numeric_list(runqs),
        total_run_queue_lengths: numeric_list(total_runqs),
        memory: memory_map(sys),
        applications: apps,
        peers: peers,
        observer_backend: observer_backend?,
        deep_events_capable: otp_int(sys[:otp_release]) >= 28,
        capabilities: %{process_inspect: true, process_binary_info: true, supervisor_focus: true, ets_inspect: true, scheduler_wall_time: true, deep_events: otp_int(sys[:otp_release]) >= 28}
      }

      node_map =
        if opts[:scheduler_wall_time] do
          Map.put(node_map, :scheduler_wall_time_sample, scheduler_wall_time(node))
        else
          node_map
        end

      processes =
        if opts[:processes],
          do: processes(node, node_map.processes, opts[:max_process_scan] || 100_000),
          else: {:ok, %{hot_processes: [], registered_processes: []}}

      case processes do
        {:ok, summary} ->
          {:ok,
           node_map
           |> Map.put(:hot_processes, summary.hot_processes)
           |> Map.put(:registered_processes, summary.registered_processes)
           |> Map.put(
             :hot_processes_at_ms,
             if(opts[:processes], do: System.system_time(:millisecond), else: nil)
           )}

        {:error, reason} ->
          {:ok,
           node_map
           |> Map.put(:hot_processes, [])
           |> Map.put(:registered_processes, [])
           |> Map.put(:hot_processes_at_ms, System.system_time(:millisecond))
           |> Map.put(:process_scan_error, inspect(reason))}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def sys_info(node) do
    case call_raw(node, :observer_backend, :sys_info, []) do
      {:ok, list} when is_list(list) -> {:ok, Map.new(list), true}
      {:error, _} -> fallback_sys_info(node)
      other -> {:error, {:bad_sys_info, other}}
    end
  end

  defp fallback_sys_info(node) do
    keys = [
      :process_count,
      :process_limit,
      :atom_count,
      :atom_limit,
      :port_count,
      :port_limit,
      :ets_count,
      :ets_limit,
      :schedulers,
      :schedulers_online,
      :otp_release,
      :version
    ]

    vals = Enum.map(keys, &{&1, call(node, :erlang, :system_info, [&1], nil)})
    mem = call(node, :erlang, :memory, [], []) |> List.wrap()
    runq = call(node, :erlang, :statistics, [:run_queue], 0)

    uptime =
      case call(node, :erlang, :statistics, [:wall_clock], {0, 0}) do
        {ms, _} -> ms
        _ -> 0
      end

    if Enum.all?(vals, fn {_key, value} -> is_nil(value) end) do
      {:error, :unavailable}
    else
      {:ok, Map.new(vals ++ mem ++ [run_queue: runq, uptime: uptime]), false}
    end
  end

  def processes(_node, count, max) when count > max,
    do: {:error, {:too_many_processes, count, max}}

  def processes(node, _count, _max) do
    parent = self()
    flush_proc_chunks()

    case call_raw(node, :observer_backend, :procs_info, [parent], 5_000) do
      {:ok, _} -> {:ok, drain_proc_chunks([])}
      {:error, reason} -> {:error, reason}
    end
  end

  defp flush_proc_chunks do
    receive do
      {:procs_info, _pid, _infos} -> flush_proc_chunks()
    after
      0 -> :ok
    end
  end

  defp drain_proc_chunks(acc) do
    receive do
      {:procs_info, _pid, infos} -> drain_proc_chunks(infos ++ acc)
    after
      100 ->
        acc
        |> Enum.map(&proc_row/1)
        |> process_summary()
    end
  end

  def proc_row({:etop_proc_info, pid, mem, reds, name, _runtime, current_function, mailbox}) do
    %{
      pid: pid_text(pid),
      memory_bytes: mem,
      reductions: reds,
      name: term(name),
      identity_kind: identity_kind(name),
      current_function: mfa(current_function),
      mailbox: mailbox
    }
  end

  def proc_row(other) do
    %{
      pid: "?",
      memory_bytes: 0,
      reductions: 0,
      name: term(other),
      identity_kind: "other",
      current_function: "",
      mailbox: 0
    }
  end

  def process_summary(rows) do
    registered =
      rows
      |> Enum.filter(&(&1.identity_kind == "registered"))
      |> Enum.map(&%{name: &1.name, pid: &1.pid})
      |> Enum.sort_by(& &1.name)
      |> Enum.take(2_000)

    %{hot_processes: hot_union(rows, 12), registered_processes: registered}
  end

  def hot_union(rows, n) do
    picks =
      Enum.take(Enum.sort_by(rows, & &1.mailbox, :desc), n) ++
        Enum.take(Enum.sort_by(rows, & &1.memory_bytes, :desc), n) ++
        Enum.take(Enum.sort_by(rows, & &1.reductions, :desc), n)

    picks |> Enum.uniq_by(& &1.pid) |> Enum.take(n * 2)
  end

  def set_flag(node, flag, value)
      when flag in [:schedulers_online, :dirty_cpu_schedulers_online] and is_integer(value) and
             value > 0 do
    case call_raw(node, :erlang, :system_flag, [flag, value]) do
      {:ok, old} -> {:ok, old}
      {:error, reason} -> {:error, reason}
    end
  end

  def set_scheduler_wall_time(node, enabled) when is_boolean(enabled) do
    case call_raw(node, :erlang, :system_flag, [:scheduler_wall_time, enabled]) do
      {:ok, old} -> {:ok, old}
      {:error, reason} -> {:error, reason}
    end
  end

  def scheduler_wall_time(node) do
    call(node, :erlang, :statistics, [:scheduler_wall_time], [], @timeout)
    |> normalize_scheduler_wall_time()
  end

  def scheduler_utilization(current, previous) when is_list(current) and is_list(previous) do
    prior = Map.new(previous, fn %{id: id} = row -> {id, row} end)

    current
    |> Enum.reduce([], fn row, acc -> prepend_utilization(row, prior, acc) end)
    |> Enum.reverse()
  end

  def scheduler_utilization(_, _), do: []

  defp prepend_utilization(row, prior, acc) do
    case scheduler_utilization_row(row, prior) do
      nil -> acc
      utilization -> [utilization | acc]
    end
  end

  defp scheduler_utilization_row(%{id: id, active: active, total: total}, prior) do
    case Map.get(prior, id) do
      %{active: old_active, total: old_total} ->
        utilization_from_delta(id, active - old_active, total - old_total)

      _ ->
        nil
    end
  end

  defp utilization_from_delta(_id, _delta_active, delta_total) when delta_total <= 0, do: nil

  defp utilization_from_delta(id, delta_active, delta_total) do
    utilization = (delta_active / delta_total) |> min(1.0) |> max(0.0)
    %{id: id, utilization: utilization}
  end

  def trigger_gc(node, pid_string, expected_creation \\ nil) do
    with {:ok, creation} <- call_raw(node, :erlang, :system_info, [:creation]),
         true <- is_nil(expected_creation) or creation == expected_creation,
         {:ok, pid} <- parse_pid(node, pid_string) do
      case call_raw(node, :erlang, :garbage_collect, [pid]) do
        {:ok, true} -> {:ok, true}
        {:ok, false} -> {:error, :process_exited}
        _ -> {:error, :gc_unconfirmed}
      end
    else
      false -> {:error, :target_restarted}
      _ -> {:error, :process_unavailable}
    end
  end

  def peers(node), do: all_peers(node)

  defp all_peers(node) do
    case call_raw(node, :erlang, :nodes, [[:visible, :hidden]]) do
      {:ok, peers} when is_list(peers) -> peers
      _ -> call(node, :erlang, :nodes, [], []) |> List.wrap()
    end
  end

  def call(node, mod, fun, args, default, timeout \\ @timeout) do
    case call_raw(node, mod, fun, args, timeout) do
      {:ok, value} -> value
      _ -> default
    end
  end

  def call_raw(node, mod, fun, args, timeout \\ @timeout) do
    deadline = Process.get(:beam_deck_rpc_deadline)
    timeout = if is_integer(deadline), do: min(timeout, deadline - System.monotonic_time(:millisecond)), else: timeout
    if timeout > 0, do: {:ok, :erpc.call(node, mod, fun, args, timeout)}, else: {:error, :deadline}
  catch
    :error, reason -> {:error, reason}
    :exit, reason -> {:error, reason}
  end

  def parse_pid(node, text) when is_binary(text) do
    # list_to_pid is node-local; invoke it remotely rather than constructing a
    # foreign pid in the helper node.
    case if(BeamDeck.Protocol.pid?(text), do: call_raw(node, :erlang, :list_to_pid, [String.to_charlist(text)]), else: {:error, :invalid_pid}) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      error -> error
    end
  end

  defp normalize_scheduler_wall_time(list) when is_list(list) do
    Enum.flat_map(list, fn
      {id, active, total} when is_integer(id) and is_integer(active) and is_integer(total) ->
        [%{id: id, active: active, total: total}]

      _ ->
        []
    end)
  end

  defp normalize_scheduler_wall_time(_), do: []

  defp normalize_apps(list) when is_list(list) do
    Enum.map(list, fn
      {name, _desc, vsn} -> %{name: to_string(name), version: to_string(vsn)}
      other -> %{name: term(other), version: ""}
    end)
  end

  defp normalize_apps(_), do: []

  defp memory_map(sys) do
    for key <- [
          :total,
          :processes,
          :processes_used,
          :system,
          :atom,
          :atom_used,
          :binary,
          :code,
          :ets
        ],
        into: %{} do
      {key, num(sys[key])}
    end
  end

  defp numeric_list(list) when is_list(list), do: Enum.map(list, &num/1)
  defp numeric_list(_), do: []
  defp num(value) when is_integer(value), do: value
  defp num(value) when is_float(value), do: value
  defp num(_), do: 0
  defp text(value) when is_binary(value), do: value
  defp text(value) when is_list(value), do: to_string(value)
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(_), do: ""

  defp otp_int(value) do
    case Integer.parse(text(value)) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp int_text(value) do
    case Integer.parse(text(value)) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp identity_kind(value) when is_atom(value), do: "registered"
  defp identity_kind(value) when is_binary(value) or is_list(value), do: "label"
  defp identity_kind(value) when is_tuple(value), do: "initial_call"
  defp identity_kind(_), do: "other"
  defp term(value) when is_binary(value), do: value
  defp term(value) when is_atom(value), do: Atom.to_string(value)
  defp term(value), do: inspect(value)
  defp mfa({mod, fun, arity}) when is_atom(mod) and is_atom(fun), do: "#{mod}.#{fun}/#{arity}"
  defp mfa(value), do: term(value)
  def pid_text(pid) when is_pid(pid) do
    # The first printed component is the observer's node index, not target PID identity.
    pid |> :erlang.pid_to_list() |> List.to_string() |> String.replace(~r/^<\d+\./, "<0.")
  end
  def pid_text(_), do: ""

  def utilization_sample(node) do
    # OTP owns the enable/disable pair in ONE RPC process, including its exit path.
    case call_raw(node, :scheduler, :utilization, [1], 2_500) do
      {:ok, rows} when is_list(rows) ->
        for {kind, id, utilization, _percent} <- rows,
            kind in [:normal, :cpu], is_integer(id), is_number(utilization),
            do: %{id: id, kind: Atom.to_string(kind), utilization: min(max(utilization, 0.0), 1.0)}
      _ -> []
    end
  end

  def identity(node) do
    with {:ok, creation} when is_integer(creation) <- call_raw(node, :erlang, :system_info, [:creation]),
         {:ok, pid} when is_list(pid) <- call_raw(node, :os, :getpid, []) do
      {:ok, %{creation: creation, os_pid: List.to_string(pid)}}
    else
      _ -> {:error, :identity_unavailable}
    end
  end

end
