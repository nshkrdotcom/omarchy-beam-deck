defmodule BeamDeck.Config do
  @moduledoc false
  alias BeamDeck.Json

  @defaults %{
    "poll_interval_ms" => 2_000,
    "deep_interval_ms" => 5_000,
    "history_points" => 450,
    "max_process_scan" => 100_000,
    "mailbox_warn" => 5_000,
    "mailbox_critical" => 50_000,
    "mailbox_rate_warn" => 1_000,
    "process_usage_warn" => 0.80,
    "atom_usage_warn" => 0.80,
    "run_queue_per_scheduler_warn" => 1.0,
    "nodes" => [],
    "event_thresholds" => %{
      "long_gc_ms" => 100,
      "long_schedule_ms" => 100,
      "mailbox_enable" => 5_000,
      "mailbox_disable" => 1_000,
      "large_heap_words" => 8_000_000
    }
  }

  def defaults, do: @defaults

  def load(path \\ default_path()) do
    case File.read(path) do
      {:ok, text} ->
        case Json.decode(text) do
          {:ok, map} when is_map(map) ->
            {:ok, map |> deep_merge_into_defaults() |> normalize(), path}

          {:ok, _} ->
            {:error, :config_not_object, @defaults, path}

          {:error, reason} ->
            {:error, {:invalid_json, reason}, @defaults, path}
        end

      {:error, :enoent} ->
        {:ok, @defaults, path}

      {:error, reason} ->
        {:error, reason, @defaults, path}
    end
  end

  def default_path do
    Path.join(
      System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config"),
      "beam-deck/config.json"
    )
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _k, a, b ->
      if is_map(a) and is_map(b), do: deep_merge(a, b), else: b
    end)
  end

  defp deep_merge_into_defaults(map), do: deep_merge(@defaults, map)

  defp normalize(config) do
    config
    |> positive_int("poll_interval_ms")
    |> positive_int("deep_interval_ms")
    |> positive_int("history_points")
    |> positive_int("max_process_scan")
    |> positive_number("mailbox_warn")
    |> positive_number("mailbox_critical")
    |> positive_number("mailbox_rate_warn")
    |> non_negative_number("process_usage_warn")
    |> non_negative_number("atom_usage_warn")
    |> non_negative_number("run_queue_per_scheduler_warn")
    |> Map.update!("nodes", fn nodes ->
      if is_list(nodes), do: Enum.filter(nodes, &is_map/1), else: @defaults["nodes"]
    end)
    |> Map.update!("event_thresholds", &normalize_thresholds/1)
  end

  defp normalize_thresholds(value) when is_map(value) do
    @defaults["event_thresholds"]
    |> deep_merge(value)
    |> threshold_int("long_gc_ms")
    |> threshold_int("long_schedule_ms")
    |> threshold_int("mailbox_enable")
    |> threshold_int("mailbox_disable")
    |> threshold_int("large_heap_words")
  end

  defp normalize_thresholds(_), do: @defaults["event_thresholds"]

  defp positive_int(config, key) do
    Map.update!(config, key, fn value ->
      if is_integer(value) and value > 0, do: value, else: @defaults[key]
    end)
  end

  defp positive_number(config, key) do
    Map.update!(config, key, fn value ->
      if is_number(value) and value > 0, do: value, else: @defaults[key]
    end)
  end

  defp non_negative_number(config, key) do
    Map.update!(config, key, fn value ->
      if is_number(value) and value >= 0, do: value, else: @defaults[key]
    end)
  end

  defp threshold_int(map, key) do
    Map.update!(map, key, fn value ->
      if is_integer(value) and value > 0, do: value, else: @defaults["event_thresholds"][key]
    end)
  end
end
