defmodule BeamDeck.Procfs do
  @moduledoc false

  def snapshot(root \\ "/proc", previous \\ nil) do
    now = System.monotonic_time(:millisecond)
    host_ticks = host_ticks(root)
    cpus = cpu_count(root)
    helper_pid = System.pid()

    runtimes =
      root
      |> beam_pids()
      |> Enum.reject(&(&1 == helper_pid))
      |> Enum.flat_map(fn pid ->
        case runtime(root, pid) do
          {:ok, runtime} -> [runtime]
          _ -> []
        end
      end)
      |> add_cpu(previous, host_ticks, cpus)

    %{
      at_ms: System.system_time(:millisecond),
      monotonic_ms: now,
      logical_cpus: cpus,
      memory: memory(root),
      host_ticks: host_ticks,
      runtimes: runtimes
    }
  end

  def verify_local_nodes(host, nodes) do
    pids = MapSet.new(host.runtimes, & &1.pid)

    Enum.map(nodes, fn node ->
      verified =
        node[:local] == true and node[:attached] == true and MapSet.member?(pids, node[:os_pid])

      Map.put(node, :local, verified)
    end)
  end

  defp beam_pids(root) do
    root
    |> Path.join("[0-9]*")
    |> Path.wildcard()
    |> Enum.filter(fn dir ->
      comm = read(Path.join(dir, "comm")) |> String.trim()
      comm in ["beam.smp", "beam"] or String.starts_with?(comm, "beam")
    end)
    |> Enum.map(&Path.basename/1)
  end

  defp runtime(root, pid) do
    dir = Path.join(root, pid)

    with {:ok, stat} <- File.read(Path.join(dir, "stat")),
         {:ok, status} <- File.read(Path.join(dir, "status")),
         {:ok, cmdline} <- File.read(Path.join(dir, "cmdline")),
         false <- internal_client?(String.split(cmdline, <<0>>, trim: true)) do
      fields = parse_stat(stat)
      status_map = parse_status(status)

      cwd =
        case File.read_link(Path.join(dir, "cwd")) do
          {:ok, path} -> path
          _ -> ""
        end

      {:ok,
       %{
         pid: String.to_integer(pid),
         cwd: cwd,
         rss_bytes: kib(status_map["VmRSS"]),
         vm_bytes: kib(status_map["VmSize"]),
         threads: int(status_map["Threads"]),
         cpu_ticks: fields.utime + fields.stime,
         state: fields.state,
         starttime: fields.starttime,
         crash_dump_fingerprint: BeamDeck.CrashDump.fingerprint(cwd),
         os_only: true
       }}
    else
      _ -> :skip
    end
  end

  defp internal_client?(argv) do
    argv
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [flag, name] ->
      flag in ["-sname", "-name"] and BeamDeck.Discovery.helper_node_name?(name)
    end)
  end

  def parse_stat(text) do
    # /proc/<pid>/stat's comm field can contain spaces and parentheses. The
    # stable fields begin after the final ") ".
    case :binary.matches(text, ") ") do
      [] ->
        %{state: "?", utime: 0, stime: 0, starttime: 0}

      matches ->
        {idx, _len} = List.last(matches)
        rest = binary_part(text, idx + 2, byte_size(text) - idx - 2)
        fields = String.split(rest)

        %{
          state: Enum.at(fields, 0, "?"),
          utime: to_i(Enum.at(fields, 11)),
          stime: to_i(Enum.at(fields, 12)),
          starttime: to_i(Enum.at(fields, 19))
        }
    end
  end

  def parse_status(text) do
    for line <- String.split(text, "\n"), String.contains?(line, ":"), into: %{} do
      [key, value] = String.split(line, ":", parts: 2)
      {key, String.trim(value)}
    end
  end

  def redact_argv(argv) when is_list(argv), do: do_redact(argv, []) |> Enum.reverse()

  defp do_redact([], acc), do: acc

  defp do_redact(["-setcookie", node, secret | rest], acc) when is_binary(node) do
    if String.contains?(node, "@") do
      do_redact(rest, ["[REDACTED]", node, "-setcookie" | acc])
    else
      do_redact([secret | rest], ["[REDACTED]", "-setcookie" | acc])
    end
  end

  defp do_redact([flag, _secret | rest], acc) when flag in ["-setcookie", "--cookie"] do
    do_redact(rest, ["[REDACTED]", flag | acc])
  end

  defp do_redact([arg | rest], acc) do
    redacted =
      cond do
        String.starts_with?(arg, "-setcookie=") -> "-setcookie=[REDACTED]"
        String.starts_with?(arg, "--cookie=") -> "--cookie=[REDACTED]"
        true -> arg
      end

    do_redact(rest, [redacted | acc])
  end

  defp add_cpu(runtimes, nil, _ticks, _cpus),
    do: Enum.map(runtimes, &Map.put(&1, :cpu_percent, nil))

  defp add_cpu(runtimes, prev, ticks, cpus) do
    delta_host = max(ticks - (prev.host_ticks || ticks), 1)
    prior = Map.new(prev.runtimes || [], &{&1.pid, &1})

    Enum.map(runtimes, fn runtime ->
      old = prior[runtime.pid]

      pct =
        if old && old[:starttime] == runtime[:starttime],
          do: max(runtime.cpu_ticks - old.cpu_ticks, 0) / delta_host * cpus * 100.0,
          else: nil

      Map.put(runtime, :cpu_percent, pct)
    end)
  end

  defp host_ticks(root) do
    case File.read(Path.join(root, "stat")) do
      {:ok, text} ->
        line = Enum.find(String.split(text, "\n"), "", &String.starts_with?(&1, "cpu "))

        case String.split(line) do
          [_cpu | ticks] -> ticks |> Enum.map(&to_i/1) |> Enum.sum()
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp cpu_count(root) do
    case File.read(Path.join(root, "stat")) do
      {:ok, text} ->
        count = text |> String.split("\n") |> Enum.count(&Regex.match?(~r/^cpu\d+\s/, &1))
        max(count, 1)

      _ ->
        1
    end
  end

  defp memory(root) do
    map =
      case File.read(Path.join(root, "meminfo")) do
        {:ok, text} -> parse_status(text)
        _ -> %{}
      end

    total = kib(map["MemTotal"])
    available = kib(map["MemAvailable"])
    %{total_bytes: total, available_bytes: available, used_bytes: max(total - available, 0)}
  end

  defp read(path) do
    case File.read(path) do
      {:ok, value} -> value
      _ -> ""
    end
  end

  defp to_i(nil), do: 0
  defp to_i(value) when is_integer(value), do: value

  defp to_i(value) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp int(value), do: to_i(value)
  defp kib(nil), do: 0
  defp kib(value), do: to_i(value) * 1024
end
