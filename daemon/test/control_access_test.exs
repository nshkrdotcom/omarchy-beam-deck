defmodule BeamDeck.ControlAccessTest do
  use ExUnit.Case, async: true
  alias BeamDeck.ControlAccess

  defp state do
    %{
      panel_open: true,
      historical_mode: false,
      panel_epoch: 7,
      snapshot: %{at_ms: 1000, nodes: [%{name: "fixture@host", attached: true, creation: 4}]}
    }
  end

  test "queued mutations require the same live view, fresh evidence and exact incarnation" do
    s = state()
    assert :ok = ControlAccess.authorize(s, 7, "fixture@host", 4, 2000)

    for altered <- [%{s | panel_open: false}, %{s | historical_mode: true}, %{s | panel_epoch: 8}] do
      assert {:error, :live_view_changed} =
               ControlAccess.authorize(altered, 7, "fixture@host", 4, 2000)
    end

    assert {:error, :target_stale_or_changed} =
             ControlAccess.authorize(s, 7, "fixture@host", 5, 2000)

    assert {:error, :target_stale_or_changed} =
             ControlAccess.authorize(s, 7, "fixture@host", nil, 2000)

    assert {:error, :target_stale_or_changed} =
             ControlAccess.authorize(s, 7, "fixture@host", 4, 12_000)

    assert {:error, :target_stale_or_changed} =
             ControlAccess.authorize(s, 7, "fixture@host", 4, -10_000)
  end
end
