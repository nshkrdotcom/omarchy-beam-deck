defmodule BeamDeck.ConfigTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Config

  test "deep-merges user thresholds without discarding defaults" do
    path =
      Path.join(System.tmp_dir!(), "beam-deck-config-#{System.unique_integer([:positive])}.json")

    File.write!(path, ~s({"poll_interval_ms":1000,"event_thresholds":{"long_gc_ms":250}}))
    on_exit(fn -> File.rm(path) end)

    assert {:ok, config, ^path} = Config.load(path)
    assert config["poll_interval_ms"] == 1000
    assert config["event_thresholds"]["long_gc_ms"] == 250
    assert config["event_thresholds"]["mailbox_enable"] == 5_000
  end

  test "invalid JSON fails closed to defaults" do
    path =
      Path.join(
        System.tmp_dir!(),
        "beam-deck-config-bad-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, "{")
    on_exit(fn -> File.rm(path) end)

    assert {:error, {:invalid_json, _}, defaults, ^path} = Config.load(path)
    assert defaults == Config.defaults()
  end

  test "malformed value types are normalized instead of crashing the daemon" do
    path =
      Path.join(
        System.tmp_dir!(),
        "beam-deck-config-types-#{System.unique_integer([:positive])}.json"
      )

    File.write!(
      path,
      ~s({"poll_interval_ms":"fast","history_points":-3,"nodes":"oops","event_thresholds":"oops"})
    )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, config, ^path} = Config.load(path)
    assert config["poll_interval_ms"] == Config.defaults()["poll_interval_ms"]
    assert config["history_points"] == Config.defaults()["history_points"]
    assert config["nodes"] == []
    assert config["event_thresholds"] == Config.defaults()["event_thresholds"]
  end

  test "1.1 defaults, nested fallback, forecast ordering and hard caps" do
    path =
      Path.join(System.tmp_dir!(), "bd-config-bounds-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      BeamDeck.Json.encode(%{
        flight_recorder_points: 999_999,
        budget_trial_lease_ms: 999_999,
        forecast: %{min_r2: 2, min_stability: -1, critical_eta_ms: 8_000, warning_eta_ms: 2_000},
        diagnostics: %{
          max_concurrent_jobs: 999,
          per_node_remote_jobs: 8,
          crash_dump_read_bytes: 999_999_999
        },
        event_thresholds: %{mailbox_enable: 3, mailbox_disable: 10}
      })
    )

    assert {:ok, c, ^path} = Config.load(path)
    assert c["flight_recorder_points"] == 2_000
    assert c["budget_trial_lease_ms"] == 30_000
    assert c["forecast"]["min_r2"] == 0.80
    assert c["forecast"]["min_stability"] == 0.70
    assert c["forecast"]["critical_eta_ms"] == 600_000
    assert c["forecast"]["min_samples"] == 12
    assert c["diagnostics"]["max_concurrent_jobs"] == 4
    assert c["diagnostics"]["per_node_remote_jobs"] == 1
    assert c["diagnostics"]["crash_dump_read_bytes"] == 262_144
    assert c["diagnostics"]["process_stack_frames"] == 20
    assert c["event_thresholds"]["mailbox_disable"] == 2
  end

  test "oversized and symbolic-link configuration is rejected, not followed" do
    dir = Path.join(System.tmp_dir!(), "bd-config-paths-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    file = Path.join(dir, "large")
    File.write!(file, String.duplicate(" ", 262_145))
    assert {:error, :unsafe_or_oversized_config, _, _} = Config.load(file)
    link = Path.join(dir, "link")
    File.ln_s!(file, link)
    assert {:error, :unsafe_or_oversized_config, _, _} = Config.load(link)
  end
end
