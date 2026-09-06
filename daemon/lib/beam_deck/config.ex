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
    "flight_recorder_points" => 150,
    "incident_retention_ms" => 300_000,
    "critical_notification_cooldown_ms" => 300_000,
    "budget_trial_lease_ms" => 30_000,
    "watchlist_max_entries" => 64,
    "watchlist_max_processes_per_node" => 16,
    "forecast" => %{
      "enabled" => true,
      "min_samples" => 12,
      "min_span_ms" => 60_000,
      "half_life_ms" => 90_000,
      "min_r2" => 0.80,
      "min_stability" => 0.70,
      "info_eta_ms" => 21_600_000,
      "warning_eta_ms" => 3_600_000,
      "critical_eta_ms" => 600_000,
      "binary_growth_min_bytes" => 33_554_432,
      "binary_growth_min_fraction" => 0.20,
      "ets_memory_growth_min_bytes" => 33_554_432,
      "ets_memory_growth_min_fraction" => 0.20,
      "ets_count_growth_min" => 32,
      "ets_count_growth_min_fraction" => 0.20
    },
    "diagnostics" => %{
      "max_concurrent_jobs" => 2,
      "max_queued_jobs" => 16,
      "per_node_remote_jobs" => 1,
      "process_timeout_ms" => 1_500,
      "process_stack_frames" => 20,
      "process_ancestry_depth" => 16,
      "process_binary_entries" => 5_000,
      "ets_timeout_ms" => 5_000,
      "ets_max_tables" => 256,
      "ets_concurrency" => 8,
      "ets_top_rows" => 50,
      "crash_dump_read_bytes" => 262_144,
      "crash_dump_match_window_ms" => 30_000,
      "crash_dump_retry_ms" => 2_000
    },
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
    case read_bounded(path) do
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
      normalize_nodes(nodes)
    end)
    |> Map.update!("event_thresholds", &normalize_thresholds/1)
    |> bounded()
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

  defp bounded(config) do
    config =
      cap(
        config,
        %{
          "poll_interval_ms" => {500, 60_000},
          "deep_interval_ms" => {1_000, 120_000},
          "history_points" => {12, 2_000},
          "max_process_scan" => {1, 100_000},
          "flight_recorder_points" => {2, 2_000},
          "incident_retention_ms" => {1_000, 3_600_000},
          "critical_notification_cooldown_ms" => {1_000, 86_400_000},
          "budget_trial_lease_ms" => {5_000, 30_000},
          "watchlist_max_entries" => {1, 256},
          "watchlist_max_processes_per_node" => {1, 64}
        },
        @defaults
      )

    forecast =
      cap(
        section(config, "forecast"),
        %{
          "min_samples" => {3, 450},
          "min_span_ms" => {1_000, 3_600_000},
          "half_life_ms" => {1_000, 3_600_000},
          "info_eta_ms" => {1_000, 86_400_000},
          "warning_eta_ms" => {1_000, 86_400_000},
          "critical_eta_ms" => {1_000, 86_400_000},
          "binary_growth_min_bytes" => {1, 1_099_511_627_776},
          "ets_memory_growth_min_bytes" => {1, 1_099_511_627_776},
          "ets_count_growth_min" => {1, 1_000_000}
        },
        @defaults["forecast"]
      )

    forecast =
      Enum.reduce(
        ~w(min_r2 min_stability binary_growth_min_fraction ets_memory_growth_min_fraction ets_count_growth_min_fraction),
        forecast,
        fn key, acc ->
          v = acc[key]

          Map.put(
            acc,
            key,
            if(is_number(v) and v >= 0 and v <= 1, do: v, else: @defaults["forecast"][key])
          )
        end
      )

    forecast = Map.put(forecast, "enabled", forecast["enabled"] != false)

    forecast =
      if forecast["critical_eta_ms"] <= forecast["warning_eta_ms"] and
           forecast["warning_eta_ms"] <= forecast["info_eta_ms"],
         do: forecast,
         else:
           Map.merge(
             forecast,
             Map.take(@defaults["forecast"], ~w(critical_eta_ms warning_eta_ms info_eta_ms))
           )

    diagnostics =
      cap(
        section(config, "diagnostics"),
        %{
          "max_concurrent_jobs" => {1, 4},
          "max_queued_jobs" => {1, 28},
          "per_node_remote_jobs" => {1, 1},
          "process_timeout_ms" => {100, 5_000},
          "process_stack_frames" => {1, 64},
          "process_ancestry_depth" => {1, 16},
          "process_binary_entries" => {1, 5_000},
          "ets_timeout_ms" => {100, 10_000},
          "ets_max_tables" => {1, 1_024},
          "ets_concurrency" => {1, 16},
          "ets_top_rows" => {1, 100},
          "crash_dump_read_bytes" => {1_024, 262_144},
          "crash_dump_match_window_ms" => {1_000, 30_000},
          "crash_dump_retry_ms" => {100, 5_000}
        },
        @defaults["diagnostics"]
      )

    events =
      cap(
        config["event_thresholds"],
        %{
          "long_gc_ms" => {1, 60_000},
          "long_schedule_ms" => {1, 60_000},
          "mailbox_enable" => {2, 1_000_000},
          "mailbox_disable" => {1, 999_999},
          "large_heap_words" => {1, 1_000_000_000}
        },
        @defaults["event_thresholds"]
      )

    events =
      Map.put(
        events,
        "mailbox_disable",
        min(events["mailbox_disable"], events["mailbox_enable"] - 1)
      )

    config
    |> Map.put("forecast", forecast)
    |> Map.put("diagnostics", diagnostics)
    |> Map.put("event_thresholds", events)
  end

  defp section(config, key) do
    if is_map(config[key]), do: Map.merge(@defaults[key], config[key]), else: @defaults[key]
  end

  defp cap(map, bounds, defaults) do
    Enum.reduce(bounds, map, fn {key, {low, high}}, acc ->
      value = acc[key]

      Map.put(
        acc,
        key,
        if(is_integer(value), do: min(max(value, low), high), else: defaults[key])
      )
    end)
  end

  defp read_bounded(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size <= 262_144 -> File.read(path)
      {:error, :enoent} -> {:error, :enoent}
      _ -> {:error, :unsafe_or_oversized_config}
    end
  end

  defp normalize_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.filter(&(is_map(&1) and BeamDeck.Protocol.node_name?(&1["name"])))
    |> Enum.take(64)
    |> Enum.map(fn entry ->
      env = entry["cookie_env"]

      env =
        if is_binary(env) and byte_size(env) <= 128 and
             Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, env), do: env, else: nil

      %{
        "name" => entry["name"],
        "cookie_env" => env,
        "required" => entry["required"] == true,
        "expected_peers" =>
          entry["expected_peers"]
          |> List.wrap()
          |> Enum.filter(&BeamDeck.Protocol.node_name?/1)
          |> Enum.uniq()
          |> Enum.take(64)
      }
    end)
    |> Enum.uniq_by(& &1["name"])
  end

  defp normalize_nodes(_), do: []
end
