defmodule BeamDeck.BundleTest do
  use ExUnit.Case, async: true
  import Bitwise
  alias BeamDeck.{FlightRecorder, Json}
  alias BeamDeck.Diagnostics.Bundle
  setup do
    dir = Path.join(System.tmp_dir!(), "bd-bundle-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end
  test "real ZIP has exact allowlisted files, redaction and private permissions", c do
    sample = %{at_ms: 1, protocol: 1, type: "snapshot", summary: %{},
      host: %{logical_cpus: 4, memory: %{}, runtimes: [%{pid: 9, cwd: "/private/project", argv: ["secret-command"]}]},
      nodes: [], alerts: [], forecasts: [], events: [%{id: "e1", password: "must-not-ship"}],
      incidents: [%{api_key: "must-not-ship", title: "Observed condition"}], crash_triage: []}
    recorder = FlightRecorder.push(FlightRecorder.new(), sample, 150)
    assert {:ok, result} = Bundle.export(sample, recorder, nil, nil, c.dir)
    assert (File.stat!(result.path).mode &&& 0o777) == 0o600
    assert (File.stat!(c.dir).mode &&& 0o777) == 0o700
    assert {:ok, entries} = :zip.extract(String.to_charlist(result.path), [:memory])
    names = Enum.map(entries, fn {name, _} -> List.to_string(name) end)
    assert Enum.sort(names) == Enum.sort(["BEAM-DECK-DIAGNOSTICS.txt", "metadata.json", "current-snapshot.json", "flight-recorder.json", "incidents.json", "recent-events.json", "crash-triage.json"])
    bytes = Enum.map_join(entries, fn {_name, data} -> data end)
    refute bytes =~ "must-not-ship"
    refute bytes =~ "/private/project"
    refute bytes =~ "secret-command"
    refute "erl_crash.dump" in names
    {_name, frame_bytes} = Enum.find(entries, fn {name, _} -> name == ~c"flight-recorder.json" end)
    assert {:ok, [frame]} = Json.decode(frame_bytes)
    refute Map.has_key?(frame, "history")
  end
  test "missing frame and unwritable destination never return a success path", c do
    assert {:error, :frame_expired} = Bundle.export(%{}, FlightRecorder.new(), "expired", "expired", c.dir)
    File.mkdir_p!(c.dir)
    blocked = Path.join(c.dir, "not-a-directory")
    File.write!(blocked, "file")
    assert {:error, :export_failed_or_too_large} = Bundle.export(%{}, FlightRecorder.new(), nil, nil, blocked)
    assert Path.wildcard(Path.join(c.dir, "**/*.tmp-*")) == []
  end
  test "more than 256 retained frames are not silently truncated by generic redaction", c do
    sample = %{at_ms: 1, host: %{}, nodes: [], summary: %{}}
    recorder = Enum.reduce(1..300, FlightRecorder.new(), fn at, r -> FlightRecorder.push(r, %{sample | at_ms: at}, 300) end)
    assert {:ok, result} = Bundle.export(sample, recorder, nil, nil, c.dir)
    assert {:ok, entries} = :zip.extract(String.to_charlist(result.path), [:memory])
    {_name, bytes} = Enum.find(entries, fn {name, _} -> name == ~c"flight-recorder.json" end)
    assert {:ok, frames} = Json.decode(bytes)
    assert length(frames) == 300
  end
end
