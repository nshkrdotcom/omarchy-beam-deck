defmodule BeamDeck.Evidence do
  @moduledoc "Shared comparability rules for measured runtime evidence."

  def same_incarnation?(a, b) when is_map(a) and is_map(b) do
    is_integer(a[:creation]) and a[:creation] == b[:creation] and
      not (is_number(a[:uptime_ms]) and is_number(b[:uptime_ms]) and
             b.uptime_ms < a.uptime_ms)
  end

  def same_incarnation?(_, _), do: false

  def fresh_deep_pair?(a, b) when is_map(a) and is_map(b) do
    same_incarnation?(a, b) and is_nil(a[:process_scan_error]) and is_nil(b[:process_scan_error]) and
      is_integer(a[:hot_processes_at_ms]) and is_integer(b[:hot_processes_at_ms]) and
      b.hot_processes_at_ms > a.hot_processes_at_ms
  end

  def fresh_deep_pair?(_, _), do: false

  def utilization(node) do
    rows = Enum.filter(node[:scheduler_utilization] || [], &normal_sample?/1)
    if rows != [], do: Enum.sum(Enum.map(rows, & &1.utilization)) / length(rows)
  end

  defp normal_sample?(row) do
    row[:kind] in [nil, "normal"] and is_number(row[:utilization]) and
      row.utilization >= 0 and row.utilization <= 1
  end

  def timeline_node(node) do
    node
    |> Map.take(
      ~w(name attached creation uptime_ms processes process_limit atoms atom_limit ports port_limit run_queue hot_processes_at_ms process_scan_error)a
    )
    |> Map.put(:memory, Map.take(node[:memory] || %{}, ~w(total processes binary ets code atom)a))
    |> Map.put(:scheduler_utilization, utilization(node))
  end
end
