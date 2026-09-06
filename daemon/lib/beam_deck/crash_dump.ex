defmodule BeamDeck.CrashDump do
  @moduledoc "Local disappearance evidence and bounded, matched crash-header triage."
  alias BeamDeck.Redaction
  def fingerprint(cwd) when is_binary(cwd) and cwd != "" do
    case File.lstat(Path.join(cwd, "erl_crash.dump"), time: :posix) do
      {:ok, %{type: :regular} = stat} -> Map.take(stat, [:inode, :size, :mtime, :ctime, :major_device])
      _ -> nil
    end
  end
  def fingerprint(_), do: nil
  def disappeared(nil, _current, _at), do: []
  def disappeared(previous, current, at) do
    identities = MapSet.new(current.runtimes, &{&1.pid, &1[:starttime]})
    previous.runtimes |> Enum.reject(&MapSet.member?(identities, {&1.pid, &1[:starttime]}))
    |> Enum.take(16) |> Enum.map(fn runtime ->
      %{id: "#{runtime.pid}-#{runtime[:starttime] || 0}-#{at}", pid: runtime.pid, at_ms: at,
        node: runtime[:node_name], cwd: runtime[:cwd], previous_fingerprint: runtime[:crash_dump_fingerprint],
        status: "checking"}
    end)
  end
  def triage(exit, opts) do
    first = read_match(exit, opts)
    result = if first.status in ["missing", "unchanged", "unmatched"] do
      Process.sleep(opts["crash_dump_retry_ms"])
      read_match(exit, opts)
    else
      first
    end
    Map.merge(Map.drop(exit, [:cwd, :previous_fingerprint]), result)
  end
  defp read_match(exit, opts) do
    fp = fingerprint(exit.cwd)
    cond do
      is_nil(fp) -> %{status: "missing"}
      fp == exit.previous_fingerprint -> %{status: "unchanged"}
      abs(fp.mtime * 1_000 - exit.at_ms) > opts["crash_dump_match_window_ms"] -> %{status: "unmatched"}
      true -> bounded_header(Path.join(exit.cwd, "erl_crash.dump"), fp, opts["crash_dump_read_bytes"])
    end
  end
  defp bounded_header(path, expected, cap) do
    case :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      {:ok, io} ->
        try do
          with {:ok, record} <- :file.read_file_info(io, time: :posix),
               stat <- File.Stat.from_record(record),
               true <- stat.type == :regular and stat.inode == expected.inode and stat.major_device == expected.major_device,
               {:ok, bytes} <- :file.read(io, cap),
               true <- String.starts_with?(bytes, "=erl_crash_dump:") do
            parse_header(bytes) |> Map.merge(%{status: "matched", bytes_read: byte_size(bytes),
              prefix_only: stat.size > byte_size(bytes), size_bytes: stat.size})
          else
            _ -> %{status: "unreadable_or_changed"}
          end
        after
          :file.close(io)
        end
      _ -> %{status: "unreadable"}
    end
  end
  def parse_header(bytes) do
    lines = String.split(bytes, "\n")
    header = lines |> Enum.drop(1) |> Enum.take_while(&(not String.starts_with?(&1, "="))) |> Enum.take(80)
    get = fn prefix ->
      case Enum.find(header, &String.starts_with?(&1, prefix)) do
        nil -> nil
        line -> line |> String.replace_prefix(prefix, "") |> String.trim() |> Redaction.text(512)
      end
    end
    base = %{dump_header: Enum.at(lines, 0), dump_timestamp: Redaction.text(Enum.at(header, 0, ""), 120),
      slogan: get.("Slogan:"), system_version: get.("System version:"), compiled: get.("Compiled:")}
    {extra, _section} = Enum.reduce(Enum.take(lines, 2_000), {%{}, :none}, fn line, {acc, section} ->
      cond do
        String.starts_with?(line, "=scheduler:") -> {acc, :scheduler}
        line == "=memory" -> {acc, :memory}
        String.starts_with?(line, "=") -> {acc, :none}
        section == :scheduler and String.starts_with?(line, "Current Process:") ->
          {Map.put_new(acc, :current_process, line |> String.replace_prefix("Current Process:", "") |> String.trim() |> Redaction.text(120)), section}
        section == :scheduler and String.starts_with?(line, "Current Function:") ->
          {Map.put_new(acc, :current_function, line |> String.replace_prefix("Current Function:", "") |> String.trim() |> Redaction.text(255)), section}
        section == :memory and Regex.match?(~r/^(total|processes|binary|ets): [0-9]+$/, line) ->
          [key, value] = String.split(line, ": ", parts: 2)
          memory = Map.put(acc[:memory] || %{}, key, String.to_integer(value))
          {Map.put(acc, :memory, memory), section}
        true -> {acc, section}
      end
    end)
    base |> Map.merge(extra) |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new() |> Redaction.sanitize()
  end
end
