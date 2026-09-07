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

  test "timeline retains measured node metrics and missing RSS without inventing a zero" do
    n = %{
      name: "api@host",
      attached: true,
      creation: 9,
      uptime_ms: 4000,
      run_queue: 12,
      memory: %{total: 2048, binary: 512},
      processes: 50,
      process_limit: 100,
      scheduler_utilization: [%{id: 1, kind: "normal", utilization: 0.25}],
      hot_processes_at_ms: 1000
    }

    s = Map.merge(snapshot(1100, nil), %{nodes: [n], sample_mono_ms: 7000})
    r = FR.push(FR.new(), s, 10)
    [point] = FR.present(r).timeline
    assert point.beam_rss_bytes == nil
    assert point.sample_mono_ms == 7000
    assert [%{name: "api@host", run_queue: 12, scheduler_utilization: 0.25}] = point.nodes
  end

  test "reappearing old events are not assigned to a new frame after a quiet sample" do
    s = Map.put(snapshot(1000, 1), :events, [%{id: "e1", at_ms: 900, kind: "nodeup"}])

    r =
      FR.new()
      |> FR.push(s, 10)
      |> FR.push(snapshot(2000, 1), 10)
      |> FR.push(%{s | at_ms: 3000}, 10)

    assert {:ok, %{new_events: []}} = FR.get(r, "frame-3")
  end

  test "comparison requires known incarnation and distinct usable deep samples" do
    n = %{
      name: "api@host",
      attached: true,
      processes: 5,
      hot_processes_at_ms: 1000,
      hot_processes: [%{pid: "<0.1.0>"}]
    }

    r =
      FR.new()
      |> FR.push(Map.put(snapshot(1000, 1), :nodes, [n]), 10)
      |> FR.push(Map.put(snapshot(2000, 1), :nodes, [%{n | processes: 9}]), 10)

    {:ok, %{nodes: [diff]}} = FR.compare(r, "frame-1", "frame-2")
    assert is_nil(diff.delta.processes)
    refute diff.hot_set_comparable
  end

  test "comparison exposes utilization and capacity in percentage points and reset-safe hot rates" do
    a = %{
      name: "api@host",
      attached: true,
      creation: 7,
      uptime_ms: 1000,
      processes: 20,
      process_limit: 100,
      hot_processes_at_ms: 1000,
      scheduler_utilization: [%{kind: "normal", utilization: 0.25}],
      hot_processes: [%{pid: "<0.1.0>", reductions: 100, mailbox: 2, memory_bytes: 50}]
    }

    b = %{
      a
      | uptime_ms: 3000,
        processes: 30,
        hot_processes_at_ms: 3000,
        scheduler_utilization: [%{kind: "normal", utilization: 0.5}],
        hot_processes: [%{pid: "<0.1.0>", reductions: 300, mailbox: 6, memory_bytes: 70}]
    }

    r =
      FR.new()
      |> FR.push(Map.put(snapshot(1000, 1), :nodes, [a]), 10)
      |> FR.push(Map.put(snapshot(3000, 1), :nodes, [b]), 10)

    {:ok, %{nodes: [diff]}} = FR.compare(r, "frame-1", "frame-2")
    assert_in_delta diff.utilization_delta_pp, 25, 0.001
    assert_in_delta diff.occupancy_delta_pp.processes, 10, 0.001

    assert [
             %{
               pid: "<0.1.0>",
               reductions_per_second: 100.0,
               mailbox_delta: 4,
               memory_delta_bytes: 20
             }
           ] = diff.hot_changes
  end

  test "activity follows exact recorder frames and sampled replacements without claiming process exits" do
    a = %{
      name: "api@host",
      attached: true,
      creation: 7,
      uptime_ms: 1000,
      schedulers_online: 3,
      hot_processes_at_ms: 1000,
      registered_processes: [%{name: "worker", pid: "<0.1.0>"}]
    }

    b = %{
      a
      | uptime_ms: 2000,
        schedulers_online: 2,
        hot_processes_at_ms: 2000,
        registered_processes: [%{name: "worker", pid: "<0.2.0>"}]
    }

    r =
      FR.new()
      |> FR.push(Map.put(snapshot(1000, 1), :nodes, [a]), 10)
      |> FR.push(Map.put(snapshot(2000, 1), :nodes, [b]), 10)

    activity = FR.present(r).activity
    replacement = Enum.find(activity, &(&1.kind == "registered_replaced"))
    assert replacement.frame_id == "frame-2"
    assert replacement.subject == "<0.2.0>"
    assert replacement.changed_fields == ["pid"]
    {:ok, frozen} = FR.get(r, "frame-1")
    refute Enum.any?(frozen.activity, &(&1.kind == "registered_replaced"))

    c =
      %{b | hot_processes_at_ms: 3000, registered_processes: []}
      |> Map.put(:process_scan_error, "capped")

    r = FR.push(r, Map.put(snapshot(3000, 1), :nodes, [c]), 10)
    refute Enum.any?(FR.present(r).activity, &(&1.kind == "process_exited"))
  end
end
