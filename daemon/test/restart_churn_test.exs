defmodule BeamDeck.RestartChurnTest do
  use ExUnit.Case, async: true
  alias BeamDeck.RestartChurn

  test "records registered-name PID replacement and keeps it visible between deep scans" do
    old = node("api@ws", [%{name: "Orders.Server", pid: "<0.10.0>"}])
    current = node("api@ws", [%{name: "Orders.Server", pid: "<0.20.0>"}])

    {events, [sampled]} = RestartChurn.update(%{}, [current], [old], 10_000, true)

    assert [%{name: "Orders.Server", count: 1}] =
             Enum.map(sampled.restart_churn, &Map.take(&1, [:name, :count]))

    {^events, [light]} = RestartChurn.update(events, [current], [current], 11_000, false)

    assert [%{name: "Orders.Server", count: 1}] =
             Enum.map(light.restart_churn, &Map.take(&1, [:name, :count]))
  end

  test "expires churn outside the rolling window" do
    events = %{{"api@ws", "Orders.Server"} => [1_000, 2_000]}

    {events, [node]} =
      RestartChurn.update(events, [node("api@ws", [])], [], 40_000, false, 30_000)

    assert events == %{}
    assert node.restart_churn == []
  end

  defp node(name, registered) do
    %{name: name, attached: true, registered_processes: registered}
  end
end
