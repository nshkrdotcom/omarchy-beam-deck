defmodule BeamDeck.SchedulerChangeTest do
  use ExUnit.Case, async: true
  alias BeamDeck.SchedulerChange

  test "OTP integer percentage coupling preserves rounding order" do
    assert SchedulerChange.coupled_count(8, 4, 4, 8, 1) == 1
    assert SchedulerChange.coupled_count(8, 4, 1, 1, 8) == 4
    assert SchedulerChange.coupled_count(12, 6, 6, 12, 6) == 1
    assert SchedulerChange.coupled_count(3, 1, 1, 3, 1) == 1
  end
end
