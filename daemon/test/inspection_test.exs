defmodule BeamDeck.InspectionTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Diagnostics.{Ets, Process}

  test "stack normalization does not expose function arguments" do
    frame =
      Process.frame(
        {My.Module, :call, [%{secret: "not-output"}], [line: 42, file: ~c"private/path"]}
      )

    assert frame == %{module: "Elixir.My.Module", function: "call", arity: 1, line: 42}
  end

  test "binary metadata is capped and shared references are not double counted" do
    result = Process.binary_summary([{1, 100, 2}, {1, 100, 2}, {2, 400, 1}], 2)
    assert result.partial
    assert result.referenced_bytes == 100
    assert result.total_entries == 3
  end

  test "ETS accounting uses target rather than helper word size" do
    r = Ets.normalize([name: :table, size: 7, memory: 100, owner: self(), type: :set], :table, 4)
    assert r.memory_bytes == 400
    assert r.size == 7
    refute Map.has_key?(r, :contents)
  end

  test "binary address identifiers never leave normalization and unknown shape is explicit" do
    assert %{top: [%{bytes: 10, references: 2}]} =
             Process.binary_summary([{91_792_384, 10, 2}], 5000)

    assert %{status: "binary_summary_unavailable", partial: true, top: []} =
             Process.binary_summary([{:unexpected, "private"}], 5000)
  end
end
