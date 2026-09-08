defmodule BeamDeck.EvidenceTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Evidence

  test "failed node acquisition retains a dated allowlist without pretending attachment" do
    prior = [
      %{name: "fixture", attached: true, creation: 4, memory: %{total: 100}, raw: "NO_RETAIN"}
    ]

    [node] = Evidence.retain_last([%{name: "fixture", attached: false}], prior, 1000)
    refute node.attached
    assert node.last_valid.at_ms == 1000
    assert node.last_valid.memory.total == 100
    refute Map.has_key?(node.last_valid, :raw)
  end
end
