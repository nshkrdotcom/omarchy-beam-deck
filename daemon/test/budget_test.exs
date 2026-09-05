defmodule BeamDeck.BudgetTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Budget

  test "budgets only attached local nodes" do
    nodes = [
      %{name: "api@ws", attached: true, local: true, schedulers_online: 16, run_queue: 7},
      %{name: "idle@ws", attached: true, local: true, schedulers_online: 16, run_queue: 0},
      %{name: "worker@omen", attached: true, local: false, schedulers_online: 32, run_queue: 50},
      %{name: "locked@ws", attached: false, local: true}
    ]

    result = Budget.recommend(nodes, 16)
    assert Enum.map(result, & &1.node) |> Enum.sort() == ["api@ws", "idle@ws"]

    assert Enum.find(result, &(&1.node == "api@ws")).suggested >
             Enum.find(result, &(&1.node == "idle@ws")).suggested

    assert Enum.sum(Enum.map(result, & &1.suggested)) <= 16
  end

  test "does not recommend scheduler reductions when the host is not oversubscribed" do
    nodes = [
      %{name: "api@ws", attached: true, local: true, schedulers_online: 4, run_queue: 10},
      %{name: "idle@ws", attached: true, local: true, schedulers_online: 2, run_queue: 0}
    ]

    assert Budget.recommend(nodes, 8) == [
             %{node: "api@ws", current: 4, suggested: 4},
             %{node: "idle@ws", current: 2, suggested: 2}
           ]
  end
end
