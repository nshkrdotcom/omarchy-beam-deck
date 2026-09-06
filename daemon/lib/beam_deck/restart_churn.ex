defmodule BeamDeck.RestartChurn do
  @moduledoc false

  @window_ms 30_000

  def update(events, nodes, previous_nodes, now_ms, deep_due, window_ms \\ @window_ms)

  def update(events, nodes, previous_nodes, now_ms, false, window_ms) do
    previous = Map.new(previous_nodes || [], &{&1.name, &1})

    events =
      Enum.reduce(nodes, events, fn node, acc ->
        if restarted?(previous[node.name], node), do: drop_node(acc, node.name), else: acc
      end)
      |> prune(now_ms, window_ms)

    {events, decorate(nodes, events)}
  end

  def update(events, nodes, previous_nodes, now_ms, true, window_ms) do
    previous = Map.new(previous_nodes || [], &{&1.name, &1})

    events =
      nodes
      |> Enum.reduce(prune(events, now_ms, window_ms), fn node, acc ->
        record_node_restarts(node, acc, previous, now_ms)
      end)
      |> prune(now_ms, window_ms)

    {events, decorate(nodes, events)}
  end

  defp record_node_restarts(%{attached: true} = node, events, previous, now_ms) do
    old = Map.get(previous, node.name)

    if restarted?(old, node) do
      drop_node(events, node.name)
    else
      old_registered = registered_map(old)

      Enum.reduce(node[:registered_processes] || [], events, fn process, acc ->
        record_process_restart(node.name, process, old_registered, acc, now_ms)
      end)
    end
  end

  defp record_node_restarts(_node, events, _previous, _now_ms), do: events

  defp restarted?(nil, _node), do: false

  defp restarted?(old, node) do
    node[:attached] == true and
      ((is_integer(old[:creation]) and is_integer(node[:creation]) and
          old.creation != node.creation) or
         (is_integer(old[:uptime_ms]) and is_integer(node[:uptime_ms]) and
            node.uptime_ms < old.uptime_ms))
  end

  defp drop_node(events, node) do
    events |> Enum.reject(fn {{name, _process}, _times} -> name == node end) |> Map.new()
  end

  defp record_process_restart(node_name, process, old_registered, events, now_ms) do
    case old_registered[process.name] do
      %{pid: old_pid} when old_pid != process.pid ->
        Map.update(events, key(node_name, process.name), [now_ms], &[now_ms | &1])

      _ ->
        events
    end
  end

  defp registered_map(nil), do: %{}

  defp registered_map(node) do
    Map.new(node[:registered_processes] || [], &{&1.name, &1})
  end

  defp prune(events, now_ms, window_ms) do
    cutoff = now_ms - window_ms

    Enum.reduce(events, %{}, fn {key, timestamps}, acc ->
      put_kept_events(acc, key, Enum.filter(timestamps, &(&1 >= cutoff)))
    end)
  end

  defp put_kept_events(acc, _key, []), do: acc
  defp put_kept_events(acc, key, kept), do: Map.put(acc, key, kept)

  defp decorate(nodes, events) do
    Enum.map(nodes, fn node ->
      Map.put(node, :restart_churn, churn_for(events, node.name))
    end)
  end

  defp churn_for(events, node_name) do
    events
    |> Enum.reduce([], fn entry, acc -> collect_churn(entry, node_name, acc) end)
    |> Enum.sort_by(&{-&1.count, &1.name})
  end

  defp collect_churn({{node_name, process_name}, timestamps}, node_name, acc) do
    [%{name: process_name, count: length(timestamps), latest_ms: Enum.max(timestamps)} | acc]
  end

  defp collect_churn(_entry, _node_name, acc), do: acc

  defp key(node, process), do: {node, process}
end
