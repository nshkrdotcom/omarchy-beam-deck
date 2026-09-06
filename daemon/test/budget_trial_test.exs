defmodule BeamDeck.BudgetTrialTest do
  use ExUnit.Case, async: true
  alias BeamDeck.BudgetTrial

  test "only the complete current local recommendation can be applied" do
    rows = [%{"node" => "a@host", "current" => 8, "suggested" => 4}]
    budget = [%{node: "a@host", current: 8, suggested: 4}]
    node = %{name: "a@host", attached: true, local: true, schedulers_online: 8}
    assert {:ok, [%{node: "a@host"}]} = BudgetTrial.validate(rows, budget, [node])

    assert {:error, :stale_or_unsafe_budget} =
             BudgetTrial.validate(rows, budget, [%{node | local: false}])

    assert {:error, :stale_or_unsafe_budget} = BudgetTrial.validate(rows ++ rows, budget, [node])

    assert {:error, :stale_or_unsafe_budget} =
             BudgetTrial.validate(rows, [%{hd(budget) | suggested: 3}], [node])
  end
end
