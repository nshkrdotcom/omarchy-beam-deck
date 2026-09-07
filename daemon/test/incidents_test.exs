defmodule BeamDeck.IncidentsTest do
  use ExUnit.Case, async: true
  alias BeamDeck.{Config, Incidents}

  defp snapshot(at, alerts),
    do: %{at_ms: at, alerts: alerts, nodes: [], forecasts: [], events: [], crash_triage: []}

  test "persistent conditions retain identity and resolve after two quiet polls" do
    a = %{
      id: "n.process_limit",
      node: "n",
      title: "Process table pressure",
      severity: "warning",
      message: "90%"
    }

    [one] = Incidents.update([], snapshot(1, [a]), Config.defaults())
    [two] = Incidents.update([one], snapshot(2, [a]), Config.defaults())
    assert one.id == two.id
    assert two.first_seen_ms == 1
    [quiet] = Incidents.update([two], snapshot(3, []), Config.defaults())
    assert quiet.status == "active"
    [resolved] = Incidents.update([quiet], snapshot(4, []), Config.defaults())
    assert resolved.status == "resolved"
  end

  test "critical notifications are transitions, not repeated poll output" do
    i = %{id: "x", status: "active", severity: "critical", title: "Resource pressure"}
    {[_], times} = Incidents.notifications([i], [], %{}, 10, Config.defaults())
    assert {[], ^times} = Incidents.notifications([i], [i], times, 20, Config.defaults())
    assert {[], ^times} = Incidents.notifications([i], [], times, 30, Config.defaults())
  end

  test "provider loss makes an unresolved symptom unknown, never healthy or resolved" do
    alert = %{
      id: "api@host.run_queue",
      node: "api@host",
      title: "Queue",
      severity: "warning",
      message: "12 runnable tasks"
    }

    live = Map.put(snapshot(1000, [alert]), :nodes, [%{name: "api@host", attached: true}])
    [incident] = Incidents.update([], live, Config.defaults())
    lost = %{live | at_ms: 2000, alerts: [], nodes: [%{name: "api@host", attached: false}]}
    [unknown] = Incidents.update([incident], lost, Config.defaults())
    assert unknown.status == "unknown"
    assert unknown.last_seen_ms == 1000
    assert is_nil(unknown.resolved_at_ms)
    [still_unknown] = Incidents.update([unknown], %{lost | at_ms: 3000}, Config.defaults())
    assert still_unknown.status == "unknown"
    recovered = %{live | at_ms: 4000, alerts: []}
    [quiet] = Incidents.update([still_unknown], recovered, Config.defaults())
    [resolved] = Incidents.update([quiet], %{recovered | at_ms: 5000}, Config.defaults())
    assert resolved.status == "resolved"
  end

  test "mailbox evidence matches PID and time window, including a hot process beyond first three" do
    alert = %{
      id: "api@host.<0.7.0>.mailbox",
      node: "api@host",
      process: "<0.7.0>",
      title: "Mailbox",
      severity: "warning",
      message: "Backlog"
    }

    node = %{
      name: "api@host",
      hot_processes_at_ms: 19_500,
      hot_processes: for(i <- 1..7, do: %{pid: "<0.#{i}.0>", reductions: i, name: "worker"})
    }

    events = [
      %{id: "yes", node: "api@host", subject: "<0.7.0>", at_ms: 13_000, kind: "long_gc"},
      %{id: "old", node: "api@host", subject: "<0.7.0>", at_ms: 1000, kind: "long_schedule"},
      %{
        id: "other",
        node: "api@host",
        subject: "<0.8.0>",
        at_ms: 13_000,
        kind: "long_message_queue"
      }
    ]

    s = snapshot(20_000, [alert]) |> Map.merge(%{nodes: [node], events: events})
    [i] = Incidents.update([], s, Config.defaults())
    assert Enum.any?(i.evidence, &String.contains?(&1.text || "", "Nearby long_gc"))
    refute Enum.any?(i.evidence, &String.contains?(&1.text || "", "Nearby long_schedule"))
    refute Enum.any?(i.evidence, &String.contains?(&1.text || "", "Nearby long_message_queue"))

    assert Enum.any?(
             i.evidence,
             &(&1[:processes] == [%{pid: "<0.7.0>", reductions: 7, name: "worker"}])
           )
  end

  test "forecast and threshold share an incident without upgrading heuristics to observations" do
    a = %{
      id: "api@host.atom_limit",
      node: "api@host",
      title: "Atoms",
      severity: "warning",
      message: "80%"
    }

    f = %{
      node: "api@host",
      metric: "atoms",
      kind: "capacity",
      summary: "Trend",
      severity: "critical",
      eta_ms: 1000,
      confidence: 0.9,
      rate_per_second: 10,
      current: 80,
      limit: 100,
      span_ms: 60_000,
      sample_count: 20
    }

    [i] = Incidents.update([], Map.put(snapshot(1, [a]), :forecasts, [f]), Config.defaults())
    assert i.severity == "critical"
    assert Enum.sort(Enum.map(i.evidence, & &1.class)) == ["heuristic", "observed"]
  end

  test "resolved incidents expire and watchlist missing is not a crash claim" do
    s =
      Map.put(snapshot(1, []), :watchlist, %{
        entries: [
          %{"id" => "p", "status" => "missing", "label" => "Orders", "node" => "api@host"}
        ]
      })

    [i] = Incidents.update([], s, Config.defaults())
    assert i.family == "watch" and i.severity == "warning"
    one = Incidents.update([i], snapshot(2, []), Config.defaults())
    two = Incidents.update(one, snapshot(3, []), Config.defaults())
    assert Incidents.update(two, snapshot(300_004, []), Config.defaults()) == []
  end
end
