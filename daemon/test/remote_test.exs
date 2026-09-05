defmodule BeamDeck.RemoteTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Remote

  test "selects a bounded union of mailbox, memory, and reduction hot processes" do
    rows =
      for i <- 1..20 do
        %{
          pid: "<0.#{i}.0>",
          mailbox: i,
          memory_bytes: 21 - i,
          reductions: rem(i * 7, 23),
          name: "p#{i}",
          current_function: "m:f/1"
        }
      end

    hot = Remote.hot_union(rows, 3)
    assert length(hot) <= 6
    assert Enum.any?(hot, &(&1.mailbox == 20))
    assert Enum.any?(hot, &(&1.memory_bytes == 20))
  end

  test "computes scheduler utilization from wall-time deltas" do
    previous = [%{id: 1, active: 100, total: 200}, %{id: 2, active: 50, total: 200}]
    current = [%{id: 1, active: 150, total: 300}, %{id: 2, active: 75, total: 300}]

    assert [%{id: 1, utilization: 0.5}, %{id: 2, utilization: 0.25}] =
             Remote.scheduler_utilization(current, previous)
  end

  test "process summary keeps bounded registered-name fingerprints for restart churn" do
    rows = [
      %{
        pid: "<0.1.0>",
        mailbox: 1,
        memory_bytes: 10,
        reductions: 20,
        name: "Orders.Server",
        identity_kind: "registered",
        current_function: "m:f/1"
      },
      %{
        pid: "<0.2.0>",
        mailbox: 2,
        memory_bytes: 20,
        reductions: 10,
        name: "m:f/1",
        identity_kind: "initial_call",
        current_function: "m:f/1"
      }
    ]

    summary = Remote.process_summary(rows)
    assert summary.registered_processes == [%{name: "Orders.Server", pid: "<0.1.0>"}]
    assert Enum.any?(summary.hot_processes, &(&1.pid == "<0.2.0>"))
  end
end
