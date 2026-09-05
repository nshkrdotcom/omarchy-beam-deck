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
end
