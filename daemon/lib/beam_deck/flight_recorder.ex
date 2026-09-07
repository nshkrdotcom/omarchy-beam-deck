defmodule BeamDeck.FlightRecorder do
  @moduledoc "Compact bounded in-memory frames. No process state, arguments or recursive snapshots."
  @node_fields ~w(name attached local otp creation uptime_ms processes process_limit atoms atom_limit ports port_limit ets memory run_queue schedulers schedulers_online dirty_cpu_schedulers_online hot_processes_at_ms process_scan_error)a
  def new, do: %{sequence: 0, frames: [], seen_events: []}

  def push(recorder, snapshot, limit) do
    sequence = recorder.sequence + 1
    events = snapshot[:events] || []
    fresh = Enum.reject(events, &(event_id(&1) in recorder.seen_events)) |> Enum.take(30)

    frame = %{
      frame_id: "frame-#{sequence}",
      at_ms: snapshot.at_ms,
      sample_mono_ms: snapshot[:sample_mono_ms],
      collection: snapshot[:collection],
      summary:
        Map.take(
          snapshot[:summary] || %{},
          ~w(beam_rss_bytes process_count schedulers_online runtime_count attached_count warning_count critical_count)a
        ),
      host: %{
        logical_cpus: get_in(snapshot, [:host, :logical_cpus]),
        memory: get_in(snapshot, [:host, :memory]),
        runtimes:
          Enum.map(
            get_in(snapshot, [:host, :runtimes]) || [],
            &Map.take(&1, ~w(pid starttime rss_bytes cpu_percent os_only node_name)a)
          )
      },
      nodes: Enum.map(snapshot[:nodes] || [], &compact_node/1),
      new_events: fresh,
      alerts: Enum.take(snapshot[:alerts] || [], 100),
      forecasts: Enum.take(snapshot[:forecasts] || [], 100)
    }

    %{
      sequence: sequence,
      frames: Enum.take([frame | recorder.frames], min(limit, 2_000)),
      seen_events:
        (Enum.map(events, &event_id/1) ++ recorder.seen_events) |> Enum.uniq() |> Enum.take(200)
    }
  end

  defp compact_node(node) do
    node
    |> Map.take(@node_fields)
    |> Map.put(:hot_processes, Enum.take(node[:hot_processes] || [], 24))
    |> Map.put(:restart_churn, Enum.take(node[:restart_churn] || [], 32))
    |> Map.put(:scheduler_utilization, Enum.take(node[:scheduler_utilization] || [], 256))
  end

  defp event_id(event),
    do: event[:id] || {event[:at_ms], event[:node], event[:kind], event[:subject]}

  def present(recorder) do
    timeline =
      recorder.frames
      |> Enum.reverse()
      |> Enum.map(fn f ->
        %{
          frame_id: f.frame_id,
          at_ms: f.at_ms,
          sample_mono_ms: f[:sample_mono_ms],
          collection: f[:collection],
          nodes: f.nodes |> Enum.take(16) |> Enum.map(&BeamDeck.Evidence.timeline_node/1),
          omitted_nodes: max(length(f.nodes) - 16, 0),
          alert_count: length(f.alerts),
          event_count: length(f.new_events),
          warning_count: Enum.count(f.alerts, &(&1.severity == "warning")),
          critical_count: Enum.count(f.alerts, &(&1.severity == "critical")),
          beam_rss_bytes: f.summary[:beam_rss_bytes]
        }
      end)

    # Timeline metadata is small; render at most 150 equally spaced points.
    shown =
      if length(timeline) <= 150 do
        timeline
      else
        for i <- 0..149, do: Enum.at(timeline, round(i * (length(timeline) - 1) / 149))
      end

    %{
      frame_count: length(recorder.frames),
      timeline: shown,
      omitted_frames: length(timeline) - length(shown),
      oldest_frame_id: if(timeline == [], do: nil, else: hd(timeline).frame_id),
      newest_frame_id: if(timeline == [], do: nil, else: List.last(timeline).frame_id)
    }
  end

  def get(recorder, id) do
    case Enum.find(recorder.frames, &(&1.frame_id == id)) do
      nil -> {:error, :frame_expired}
      frame -> {:ok, frame}
    end
  end

  def range(recorder, nil, nil), do: {:ok, Enum.reverse(recorder.frames)}
  def range(%{frames: []}, _from, _to), do: {:error, :frame_expired}

  def range(recorder, from, to) do
    from = from || List.last(recorder.frames).frame_id
    to = to || hd(recorder.frames).frame_id

    with {:ok, _a} <- get(recorder, from), {:ok, _b} <- get(recorder, to) do
      # Sequence order, not wall time: NTP adjustments must not enlarge an export.
      a = Enum.find_index(recorder.frames, &(&1.frame_id == from))
      b = Enum.find_index(recorder.frames, &(&1.frame_id == to))
      {:ok, recorder.frames |> Enum.slice(min(a, b), abs(a - b) + 1) |> Enum.reverse()}
    end
  end

  def nearest_deep(recorder, name, at_ms, max_distance, creation \\ nil)

  def nearest_deep(nil, _name, _at_ms, _max_distance, _creation),
    do: {:error, :no_nearby_deep_frame}

  def nearest_deep(recorder, name, at_ms, max_distance, creation) do
    candidates =
      for frame <- recorder.frames,
          node <- frame.nodes,
          node.name == name and node[:attached] == true,
          is_integer(node[:hot_processes_at_ms]),
          is_nil(creation) or node[:creation] == creation,
          abs(node.hot_processes_at_ms - at_ms) <= max_distance do
        %{
          frame_id: frame.frame_id,
          at_ms: frame.at_ms,
          sampled_at_ms: node.hot_processes_at_ms,
          node: node
        }
      end

    case Enum.sort_by(candidates, &{abs(&1.sampled_at_ms - at_ms), -&1.at_ms}) do
      [first | _] -> {:ok, first}
      [] -> {:error, :no_nearby_deep_frame}
    end
  end

  def compare(recorder, from, to) do
    with {:ok, a} <- get(recorder, from), {:ok, b} <- get(recorder, to) do
      {:ok,
       %{
         from_frame_id: from,
         to_frame_id: to,
         from_at_ms: a.at_ms,
         to_at_ms: b.at_ms,
         summary_delta:
           delta(a.summary, b.summary, ~w(beam_rss_bytes process_count schedulers_online)a),
         nodes: node_diff(a.nodes, b.nodes),
         new_alerts: ids(b.alerts) -- ids(a.alerts),
         resolved_alerts: ids(a.alerts) -- ids(b.alerts)
       }}
    end
  end

  defp ids(rows), do: Enum.map(rows, & &1.id)

  defp delta(a, b, keys),
    do:
      Map.new(
        keys,
        &{&1, if(is_number(a[&1]) and is_number(b[&1]), do: b[&1] - a[&1], else: nil)}
      )

  defp node_diff(left, right) do
    before = Map.new(left, &{&1.name, &1})
    after_nodes = Map.new(right, &{&1.name, &1})

    (Map.keys(before) ++ Map.keys(after_nodes))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn name -> node_change(name, before[name], after_nodes[name]) end)
  end

  defp node_change(name, nil, _new), do: %{node: name, change: "added"}
  defp node_change(name, _old, nil), do: %{node: name, change: "removed"}

  defp node_change(name, old, new) do
    change = change_kind(old, new)
    comparable = comparable_nodes?(old, new, change)
    baseline = if comparable, do: old, else: %{}
    deep = deep_comparable?(old, new, change)

    Map.merge(%{node: name, change: change}, %{
      delta: delta(baseline, new, ~w(processes atoms ports ets run_queue schedulers_online)a),
      memory_delta:
        delta(baseline[:memory] || %{}, new[:memory] || %{}, ~w(total binary ets processes code)a),
      hot_set_comparable: deep,
      hot_entered: hot_delta(new, old, deep),
      hot_left: hot_delta(old, new, deep),
      restart_churn: new[:restart_churn] || [],
      restart_churn_delta:
        churn_delta(baseline[:restart_churn] || [], new[:restart_churn] || [], comparable)
    })
  end

  defp change_kind(old, new) do
    cond do
      old[:attached] != new[:attached] -> "attachment_changed"
      restarted?(old, new) -> "restarted"
      true -> "retained"
    end
  end

  defp restarted?(old, new) do
    (is_integer(old[:creation]) and old[:creation] != new[:creation]) or
      (is_integer(old[:uptime_ms]) and is_integer(new[:uptime_ms]) and
         new.uptime_ms < old.uptime_ms)
  end

  defp comparable_nodes?(old, new, change) do
    change == "retained" and old[:attached] == true and new[:attached] == true
  end

  defp deep_comparable?(old, new, change) do
    old[:attached] == true and new[:attached] == true and change != "restarted" and
      is_integer(old[:hot_processes_at_ms]) and is_integer(new[:hot_processes_at_ms])
  end

  defp hot_delta(left, right, true) do
    Enum.map(left[:hot_processes] || [], & &1.pid) --
      Enum.map(right[:hot_processes] || [], & &1.pid)
  end

  defp hot_delta(_left, _right, false), do: []

  defp churn_delta(old, new, comparable) do
    before = Map.new(old, &{&1.name, &1.count})
    after_counts = Map.new(new, &{&1.name, &1.count})

    (Map.keys(before) ++ Map.keys(after_counts))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn name ->
      %{
        name: name,
        delta: if(comparable, do: (after_counts[name] || 0) - (before[name] || 0), else: nil)
      }
    end)
  end
end
