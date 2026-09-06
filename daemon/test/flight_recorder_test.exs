defmodule BeamDeck.FlightRecorderTest do
  use ExUnit.Case, async: true
  alias BeamDeck.FlightRecorder, as: FR

  defp snapshot(at, rss) do
    %{
      at_ms: at,
      summary: %{beam_rss_bytes: rss},
      host: %{runtimes: []},
      nodes: [],
      events: [],
      alerts: [],
      forecasts: [],
      history: ["NOT RETAINED"]
    }
  end

  test "bounded compact frames have stable identities and explicit expiry" do
    recorder = Enum.reduce(1..4, FR.new(), fn at, acc -> FR.push(acc, snapshot(at, at), 2) end)
    assert FR.present(recorder).frame_count == 2
    assert {:error, :frame_expired} = FR.get(recorder, "frame-1")
    assert {:ok, frame} = FR.get(recorder, "frame-3")
    refute Map.has_key?(frame, :history)
    assert {:ok, diff} = FR.compare(recorder, "frame-3", "frame-4")
    assert diff.summary_delta.beam_rss_bytes == 1
  end

  test "duplicate events are not copied into every frame" do
    s = Map.put(snapshot(1, 1), :events, [%{id: "e1", kind: "nodeup", at_ms: 1}])
    r = FR.new() |> FR.push(s, 5) |> FR.push(%{s | at_ms: 2}, 5)
    assert {:ok, %{new_events: []}} = FR.get(r, "frame-2")
  end

  test "nearest deep frame is distance and incarnation constrained" do
    n = %{
      name: "api@host",
      attached: true,
      creation: 1,
      hot_processes_at_ms: 1000,
      hot_processes: [%{pid: "<0.1.0>"}]
    }

    s = Map.put(snapshot(1100, 1), :nodes, [n])
    r = FR.push(FR.new(), s, 10)

    assert {:ok, %{frame_id: "frame-1", sampled_at_ms: 1000}} =
             FR.nearest_deep(r, "api@host", 2000, 1000, 1)

    assert {:error, :no_nearby_deep_frame} = FR.nearest_deep(r, "api@host", 2000, 999, 1)
    assert {:error, :no_nearby_deep_frame} = FR.nearest_deep(r, "api@host", 2000, 1000, 2)
  end

  test "frame diff does not subtract counters across incarnations" do
    a = %{name: "api@host", attached: true, creation: 1, processes: 100, memory: %{total: 1000}}
    b = %{a | creation: 2, processes: 10, memory: %{total: 100}}

    r =
      FR.new()
      |> FR.push(Map.put(snapshot(1000, 1), :nodes, [a]), 10)
      |> FR.push(Map.put(snapshot(2000, 1), :nodes, [b]), 10)

    assert {:ok, %{nodes: [n]}} = FR.compare(r, "frame-1", "frame-2")
    assert n.change == "restarted"
    assert is_nil(n.delta.processes) and is_nil(n.memory_delta.total)
    refute n.hot_set_comparable
  end

  test "export ranges follow sequence even when the wall clock moves backward" do
    r =
      FR.new()
      |> FR.push(snapshot(3000, 1), 10)
      |> FR.push(snapshot(1000, 2), 10)
      |> FR.push(snapshot(2000, 3), 10)

    assert {:ok, frames} = FR.range(r, "frame-1", "frame-2")
    assert Enum.map(frames, & &1.frame_id) == ["frame-1", "frame-2"]
    assert {:ok, reverse} = FR.range(r, "frame-2", "frame-1")
    assert reverse == frames
  end
end
