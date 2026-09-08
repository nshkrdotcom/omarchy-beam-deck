defmodule BeamDeck.Protocol do
  @moduledoc "Additive protocol v1 command validation, without creating atoms from input."
  alias BeamDeck.Json

  @windows ~w(process_window ets_window sample_process)
  @jobs ~w(process_window ets_window sample_process inspect_process inspect_ets recorder_frame compare_frames export_bundle budget_trial_begin)
  def request_id?(id),
    do: is_binary(id) and byte_size(id) in 1..64 and Regex.match?(~r/^[A-Za-z0-9._:-]+$/, id)

  def node_name?(name),
    do:
      is_binary(name) and byte_size(name) in 3..255 and
        Regex.match?(~r/^[A-Za-z0-9_.-]+@[A-Za-z0-9_.:-]+$/, name)

  def pid?(pid),
    do: is_binary(pid) and byte_size(pid) <= 64 and Regex.match?(~r/^<0\.\d+\.\d+>$/, pid)

  def parse(line) when is_binary(line) and byte_size(line) <= 16_384 do
    case Json.decode(String.trim(line)) do
      {:ok, %{"cmd" => cmd} = map} when is_binary(cmd) -> validate(cmd, map)
      {:ok, _} -> {:error, :missing_cmd}
      error -> error
    end
  end

  def parse(_), do: {:error, :command_too_large}

  defp validate(cmd, map) do
    checks = [
      &valid_request/2,
      &valid_window/2,
      &valid_node/2,
      &valid_pid/2,
      &valid_ets_sort/2,
      &valid_frame/2,
      &valid_comparison/2,
      &valid_budget/2,
      &valid_trial/2,
      &valid_watchlist_add/2,
      &valid_watchlist_remove/2,
      &valid_scheduler_value/2,
      &valid_gc_creation/2,
      &valid_panel/2,
      &valid_view/2,
      &valid_deep_events/2
    ]

    if Enum.all?(checks, fn check -> check.(cmd, map) end),
      do: {:ok, cmd, map},
      else: {:error, :invalid_arguments}
  end

  defp valid_request(cmd, map) when cmd in @jobs or cmd == "cancel_job",
    do: request_id?(map["request_id"])

  defp valid_request(_cmd, _map), do: true

  defp valid_node(cmd, map)
       when cmd in ~w(process_window ets_window sample_process inspect_process inspect_ets set_schedulers set_dirty_schedulers gc restore deep_events),
       do: node_name?(map["node"])

  defp valid_node(_cmd, _map), do: true

  defp valid_pid(cmd, map) when cmd in ~w(inspect_process sample_process gc), do: pid?(map["pid"])
  defp valid_pid(_cmd, _map), do: true

  defp valid_ets_sort("inspect_ets", map),
    do: Map.get(map, "sort", "memory") in ["memory", "size"]

  defp valid_ets_sort(_cmd, _map), do: true

  defp valid_window(cmd, map) when cmd in @windows do
    is_integer(map["expected_creation"]) and map["expected_creation"] >= 0 and
      map["duration_ms"] in [1000, 5000]
  end

  defp valid_window(_cmd, _map), do: true

  defp valid_frame("recorder_frame", map), do: request_id?(map["frame_id"])
  defp valid_frame(_cmd, _map), do: true

  defp valid_comparison("compare_frames", map),
    do: request_id?(map["from_frame_id"]) and request_id?(map["to_frame_id"])

  defp valid_comparison(_cmd, _map), do: true

  defp valid_budget("budget_trial_begin", map), do: valid_rows?(map["rows"])
  defp valid_budget(_cmd, _map), do: true

  defp valid_trial(cmd, map) when cmd in ~w(budget_trial_keep budget_trial_revert),
    do: request_id?(map["trial_id"])

  defp valid_trial(_cmd, _map), do: true

  defp valid_watchlist_add("watchlist_add", map), do: is_map(map["entry"])
  defp valid_watchlist_add(_cmd, _map), do: true

  defp valid_watchlist_remove("watchlist_remove", map), do: request_id?(map["id"])
  defp valid_watchlist_remove(_cmd, _map), do: true

  defp valid_scheduler_value(cmd, map) when cmd in ~w(set_schedulers set_dirty_schedulers),
    do: is_integer(map["value"]) and map["value"] in 1..1024

  defp valid_scheduler_value(_cmd, _map), do: true

  defp valid_gc_creation(cmd, map)
       when cmd in ~w(gc inspect_process inspect_ets set_schedulers set_dirty_schedulers restore deep_events) do
    not Map.has_key?(map, "expected_creation") or
      (is_integer(map["expected_creation"]) and map["expected_creation"] >= 0)
  end

  defp valid_gc_creation(_cmd, _map), do: true

  defp valid_view("view", map), do: is_boolean(map["historical"])
  defp valid_view(_cmd, _map), do: true

  defp valid_panel("panel", map), do: is_boolean(map["open"])
  defp valid_panel(_cmd, _map), do: true

  defp valid_deep_events("deep_events", map), do: is_boolean(map["enabled"])
  defp valid_deep_events(_cmd, _map), do: true

  defp valid_rows?(rows) when is_list(rows) and length(rows) in 1..16 do
    Enum.all?(rows, fn row ->
      is_map(row) and node_name?(row["node"]) and is_integer(row["current"]) and
        is_integer(row["suggested"]) and row["suggested"] >= 1 and
        row["suggested"] <= row["current"]
    end)
  end

  defp valid_rows?(_), do: false
end
