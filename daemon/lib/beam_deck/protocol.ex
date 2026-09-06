defmodule BeamDeck.Protocol do
  @moduledoc "Additive protocol v1 command validation, without creating atoms from input."
  alias BeamDeck.Json
  @jobs ~w(inspect_process inspect_ets recorder_frame compare_frames export_bundle budget_trial_begin)
  def request_id?(id), do: is_binary(id) and byte_size(id) in 1..64 and Regex.match?(~r/^[A-Za-z0-9._:-]+$/, id)
  def node_name?(name), do: is_binary(name) and byte_size(name) in 3..255 and Regex.match?(~r/^[A-Za-z0-9_.-]+@[A-Za-z0-9_.:-]+$/, name)
  def pid?(pid), do: is_binary(pid) and byte_size(pid) <= 64 and Regex.match?(~r/^<0\.\d+\.\d+>$/, pid)
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
      cmd not in @jobs or request_id?(map["request_id"]),
      cmd not in ~w(inspect_process inspect_ets set_schedulers set_dirty_schedulers gc restore deep_events) or node_name?(map["node"]),
      cmd not in ~w(inspect_process gc) or pid?(map["pid"]),
      cmd != "inspect_ets" or Map.get(map, "sort", "memory") in ["memory", "size"],
      cmd != "recorder_frame" or request_id?(map["frame_id"]),
      cmd != "compare_frames" or (request_id?(map["from_frame_id"]) and request_id?(map["to_frame_id"])),
      cmd != "budget_trial_begin" or valid_rows?(map["rows"]),
      cmd not in ~w(budget_trial_keep budget_trial_revert) or request_id?(map["trial_id"]),
      cmd != "watchlist_add" or is_map(map["entry"]),
      cmd != "watchlist_remove" or request_id?(map["id"]),
      cmd not in ~w(set_schedulers set_dirty_schedulers) or (is_integer(map["value"]) and map["value"] in 1..1024),
      cmd != "gc" or not Map.has_key?(map, "expected_creation") or (is_integer(map["expected_creation"]) and map["expected_creation"] >= 0),
      cmd != "panel" or is_boolean(map["open"]),
      cmd != "deep_events" or is_boolean(map["enabled"])
    ]
    if Enum.all?(checks), do: {:ok, cmd, map}, else: {:error, :invalid_arguments}
  end
  defp valid_rows?(rows) when is_list(rows) and length(rows) in 1..16 do
    Enum.all?(rows, fn row ->
      is_map(row) and node_name?(row["node"]) and is_integer(row["current"]) and
        is_integer(row["suggested"]) and row["suggested"] >= 1 and row["suggested"] <= row["current"]
    end)
  end
  defp valid_rows?(_), do: false
end
