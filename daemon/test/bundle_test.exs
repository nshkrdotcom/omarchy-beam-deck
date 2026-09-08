defmodule BeamDeck.BundleTest do
  use ExUnit.Case, async: true
  import Bitwise
  alias BeamDeck.Diagnostics.Bundle
  alias BeamDeck.{FlightRecorder, Json}

  setup do
    dir = Path.join(System.tmp_dir!(), "bd-bundle-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "real ZIP has exact allowlisted files, redaction and private permissions", c do
    sample = %{
      at_ms: 1,
      protocol: 1,
      type: "snapshot",
      summary: %{},
      host: %{
        logical_cpus: 4,
        memory: %{},
        runtimes: [%{pid: 9, cwd: "/private/project", argv: ["secret-command"]}]
      },
      nodes: [],
      alerts: [],
      forecasts: [],
      events: [%{id: "e1", password: "must-not-ship"}],
      incidents: [%{api_key: "must-not-ship", title: "Observed condition"}],
      crash_triage: []
    }

    recorder = FlightRecorder.push(FlightRecorder.new(), sample, 150)
    assert {:ok, result} = Bundle.export(sample, recorder, nil, nil, c.dir)
    assert (File.stat!(result.path).mode &&& 0o777) == 0o600
    assert (File.stat!(c.dir).mode &&& 0o777) == 0o700
    assert {:ok, entries} = :zip.extract(String.to_charlist(result.path), [:memory])
    names = Enum.map(entries, fn {name, _} -> List.to_string(name) end)

    assert Enum.sort(names) ==
             Enum.sort([
               "BEAM-DECK-DIAGNOSTICS.txt",
               "metadata.json",
               "current-snapshot.json",
               "flight-recorder.json",
               "incidents.json",
               "recent-events.json",
               "crash-triage.json"
             ])

    bytes = Enum.map_join(entries, fn {_name, data} -> data end)
    refute bytes =~ "must-not-ship"
    refute bytes =~ "/private/project"
    refute bytes =~ "secret-command"
    refute "erl_crash.dump" in names

    {_name, frame_bytes} =
      Enum.find(entries, fn {name, _} -> name == ~c"flight-recorder.json" end)

    assert {:ok, [frame]} = Json.decode(frame_bytes)
    refute Map.has_key?(frame, "history")
  end

  test "missing frame and unwritable destination never return a success path", c do
    assert {:error, :frame_expired} =
             Bundle.export(%{}, FlightRecorder.new(), "expired", "expired", c.dir)

    File.mkdir_p!(c.dir)
    blocked = Path.join(c.dir, "not-a-directory")
    File.write!(blocked, "file")

    assert {:error, :export_failed_or_too_large} =
             Bundle.export(%{}, FlightRecorder.new(), nil, nil, blocked)

    assert Path.wildcard(Path.join(c.dir, "**/*.tmp-*")) == []
  end

  test "more than 256 retained frames are not silently truncated by generic redaction", c do
    sample = %{at_ms: 1, host: %{}, nodes: [], summary: %{}}

    recorder =
      Enum.reduce(1..300, FlightRecorder.new(), fn at, r ->
        FlightRecorder.push(r, %{sample | at_ms: at}, 300)
      end)

    assert {:ok, result} = Bundle.export(sample, recorder, nil, nil, c.dir)
    assert {:ok, entries} = :zip.extract(String.to_charlist(result.path), [:memory])
    {_name, bytes} = Enum.find(entries, fn {name, _} -> name == ~c"flight-recorder.json" end)
    assert {:ok, frames} = Json.decode(bytes)
    assert length(frames) == 300
  end

  test "operator report explains the exact historical range and rejects unrecognized payloads",
       c do
    s = %{
      at_ms: 1000,
      summary: %{beam_rss_bytes: 100},
      nodes: [],
      host: %{},
      incidents: [
        %{
          title: "Observed queue",
          status: "active",
          severity: "warning",
          summary: "12 runnable tasks",
          evidence_class: "observed",
          arbitrary: "REPORT_PRIVATE_CANARY"
        }
      ],
      watchlist: %{entries: []}
    }

    r =
      FlightRecorder.new()
      |> FlightRecorder.push(s, 10)
      |> FlightRecorder.push(%{s | at_ms: 2000, summary: %{beam_rss_bytes: 150}}, 10)

    assert {:ok, result} = Bundle.export(%{s | at_ms: 9000}, r, "frame-1", "frame-2", c.dir)
    {:ok, entries} = :zip.extract(String.to_charlist(result.path), [:memory])
    {_, report} = Enum.find(entries, fn {name, _} -> name == ~c"BEAM-DECK-DIAGNOSTICS.txt" end)
    assert report =~ "HISTORICAL RANGE"
    assert report =~ "frame-1"
    assert report =~ "frame-2"
    assert report =~ "+50 B"
    assert report =~ "Observed queue"
    refute report =~ "REPORT_PRIVATE_CANARY"
    refute Enum.map_join(entries, fn {_, bytes} -> bytes end) =~ "REPORT_PRIVATE_CANARY"
    assert byte_size(report) <= 65_536
  end
end
