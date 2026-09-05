defmodule BeamDeck.RestartChurn do
  @moduledoc false

  @window_ms 30_000

  def update(events, nodes, previous_nodes, now_ms, deep_due, window_ms \\ @window_ms)

  def update(events, nodes, _previous_nodes, now_ms, false, window_ms) do
    events = prune(events, now_ms, window_ms)
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
    old_registered = previous |> Map.get(node.name) |> registered_map()

    Enum.reduce(node[:registered_processes] || [], events, fn process, acc ->
      record_process_restart(node.name, process, old_registered, acc, now_ms)
    end)
  end

  defp record_node_restarts(_node, events, _previous, _now_ms), do: events

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
