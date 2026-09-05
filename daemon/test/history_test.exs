defmodule BeamDeck.HistoryTest do
  use ExUnit.Case, async: true
  alias BeamDeck.History

  test "keeps bounded newest-first storage and chronological presentation" do
    stored =
      []
      |> History.push(%{at_ms: 1}, 2)
      |> History.push(%{at_ms: 2}, 2)
      |> History.push(%{at_ms: 3}, 2)

    assert Enum.map(stored, & &1.at_ms) == [3, 2]
    assert Enum.map(History.chronological(stored), & &1.at_ms) == [2, 3]
  end

  test "presentation downsamples the full retained window while preserving endpoints" do
    stored = Enum.reduce(1..20, [], fn at, acc -> History.push(acc, %{at_ms: at}, 20) end)
    shown = History.present(stored, 5)

    assert length(shown) == 5
    assert hd(shown).at_ms == 1
    assert List.last(shown).at_ms == 20
    assert Enum.map(shown, & &1.at_ms) == Enum.sort(Enum.map(shown, & &1.at_ms))
  end
end
