defmodule BeamDeck.AlertsTest do
  use ExUnit.Case, async: true
  alias BeamDeck.{Alerts, Config}

  test "host scheduler density ignores remote peers" do
    snapshot = %{
      host: %{logical_cpus: 8},
      nodes: [
        node("api@ws", true, 8),
        node("worker@omen", false, 64)
      ]
    }

    assert Alerts.derive(snapshot, nil, Config.defaults()) == []
  end

  test "does not crash on discovered but unattached nodes" do
    snapshot = %{
      host: %{logical_cpus: 8},
      nodes: [%{name: "locked@ws", attached: false, local: true}]
    }

    assert Alerts.derive(snapshot, nil, Config.defaults()) == []
  end

  test "mailbox rate uses actual deep-sample timestamps" do
    config =
      Config.defaults() |> Map.put("mailbox_warn", 100_000) |> Map.put("mailbox_rate_warn", 1_000)

    old =
      node("api@ws", true, 4)
      |> Map.put(:hot_processes, [proc(100)])
      |> Map.put(:hot_processes_at_ms, 1_000)

    current =
      node("api@ws", true, 4)
      |> Map.put(:hot_processes, [proc(6_100)])
      |> Map.put(:hot_processes_at_ms, 6_000)

    previous = %{nodes: [old]}
    snapshot = %{host: %{logical_cpus: 8}, nodes: [current]}

    alerts = Alerts.derive(snapshot, previous, config)
    assert Enum.any?(alerts, &(&1.title == "Mailbox growth"))
  end

  test "required unattached configured node is critical" do
    snapshot = %{
      host: %{logical_cpus: 8},
      nodes: [
        %{name: "worker@omen", attached: false, local: false, configured: true, required: true}
      ]
    }

    assert [%{severity: "critical", title: "Required node unavailable"}] =
             Alerts.derive(snapshot, nil, Config.defaults())
             |> Enum.map(&Map.take(&1, [:severity, :title]))
  end

  test "mailbox growth never crosses a VM incarnation or an incomplete scan" do
    config = Config.defaults() |> Map.put("mailbox_warn", 100_000)

    old =
      node("api@ws", true, 4)
      |> Map.merge(%{
        creation: 1,
        uptime_ms: 10_000,
        hot_processes: [proc(0)],
        hot_processes_at_ms: 1000
      })

    current = %{
      old
      | creation: 2,
        uptime_ms: 100,
        hot_processes: [proc(9000)],
        hot_processes_at_ms: 2000
    }

    sample = %{host: %{logical_cpus: 8}, nodes: [current]}
    assert Alerts.derive(sample, %{nodes: [old]}, config) == []

    current =
      %{current | creation: 1, uptime_ms: 11_000} |> Map.put(:process_scan_error, "capped")

    assert Alerts.derive(%{sample | nodes: [current]}, %{nodes: [old]}, config) == []
  end

  test "only explicitly expected missing peer edges produce topology alerts" do
    configured =
      node("api@ws", true, 4)
      |> Map.put(:expected_peers, ["worker@omen"])
      |> Map.put(:peers, [])

    ordinary = node("events@ws", true, 4) |> Map.put(:peers, [])
    snapshot = %{host: %{logical_cpus: 8}, nodes: [configured, ordinary]}
    alerts = Alerts.derive(snapshot, nil, Config.defaults())

    assert Enum.count(alerts, &(&1.title == "Expected cluster link missing")) == 1
  end

  test "registered process churn alerts only after repeated replacements" do
    current =
      node("api@ws", true, 4) |> Map.put(:restart_churn, [%{name: "Orders.Server", count: 3}])

    snapshot = %{host: %{logical_cpus: 8}, nodes: [current]}
    alerts = Alerts.derive(snapshot, nil, Config.defaults())
    assert Enum.any?(alerts, &(&1.title == "Registered process churn"))
  end

  defp node(name, local, schedulers) do
    %{
      name: name,
      creation: 1,
      uptime_ms: 10_000,
      attached: true,
      local: local,
      schedulers_online: schedulers,
      run_queue: 0,
      processes: 100,
      process_limit: 1_000_000,
      atoms: 10_000,
      atom_limit: 1_000_000,
      peers: [],
      expected_peers: [],
      restart_churn: [],
      hot_processes: [],
      hot_processes_at_ms: nil
    }
  end

  defp proc(mailbox) do
    %{
      pid: "<0.1.0>",
      mailbox: mailbox,
      name: "Server",
      memory_bytes: 1_000,
      reductions: 100,
      current_function: "m:f/1"
    }
  end
end
