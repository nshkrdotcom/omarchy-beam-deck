defmodule BeamDeck.DiagnosticsTest do
  use ExUnit.Case
  alias BeamDeck.Diagnostics

  setup do
    start_supervised!({Task.Supervisor, name: BeamDeck.DiagnosticTasks})
    start_supervised!({Diagnostics, BeamDeck.Config.defaults()["diagnostics"]})
    :ok
  end

  test "results are structured and duplicate active IDs are rejected" do
    assert :ok =
             Diagnostics.submit(self(), "one", "test", "n", fn ->
               Process.sleep(50)
               {:ok, %{v: 1}}
             end)

    assert {:error, :duplicate_request} =
             Diagnostics.submit(self(), "one", "test", "n", fn -> :ok end)

    assert_receive {:diagnostic, %{request_id: "one", status: "started"}}
    assert_receive {:diagnostic, %{request_id: "one", status: "complete", result: %{v: 1}}}, 1_000
  end

  test "deadline cancels the worker and the next job still completes" do
    :ok =
      Diagnostics.submit(self(), "slow", "test", "n", fn -> Process.sleep(5_000) end, timeout: 20)

    :ok = Diagnostics.submit(self(), "fast", "test", "n", fn -> {:ok, %{ok: true}} end)
    assert_receive {:diagnostic, %{request_id: "slow", status: "error", error: "timeout"}}, 1_000
    assert_receive {:diagnostic, %{request_id: "fast", status: "complete"}}, 1_000
  end

  test "panel cancellation does not cancel an explicit export" do
    Diagnostics.submit(self(), "interactive", "test", "n", fn -> Process.sleep(500) end)

    Diagnostics.submit(
      self(),
      "export",
      "export_bundle",
      nil,
      fn ->
        Process.sleep(50)
        {:ok, %{path: "private"}}
      end,
      interactive: false
    )

    Diagnostics.cancel_interactive(self())
    assert_receive {:diagnostic, %{request_id: "interactive", status: "canceled"}}, 1_000
    assert_receive {:diagnostic, %{request_id: "export", status: "complete"}}, 1_000
  end

  test "worker exceptions are bounded, and do not expose exception text" do
    Diagnostics.submit(self(), "raises", "test", nil, fn -> raise "PRIVATE_EXCEPTION" end)

    assert_receive {:diagnostic,
                    %{request_id: "raises", status: "error", error: "diagnostic_failed"}},
                   1000

    assert Process.alive?(Process.whereis(Diagnostics))
  end

  test "global and per-node concurrency leave a bounded explicit queue" do
    parent = self()

    hold = fn ->
      send(parent, {:held_worker, self()})

      receive do
        :release -> {:ok, %{}}
      end
    end

    assert :ok = Diagnostics.submit(self(), "held-1", "test", "one", hold)
    assert :ok = Diagnostics.submit(self(), "held-2", "test", "two", hold)
    assert_receive {:held_worker, first}, 1000
    assert_receive {:held_worker, second}, 1000

    for i <- 1..16 do
      assert :ok = Diagnostics.submit(self(), "queued-#{i}", "test", "one", hold)
    end

    assert %{active: 2, queued: 16, max_active: 2, max_queued: 16, oldest_queued_ms: age} =
             Diagnostics.status()

    assert age >= 0
    assert {:error, :queue_full} = Diagnostics.submit(self(), "overflow", "test", "three", hold)
    refute_receive {:held_worker, _}, 50
    first_ref = Process.monitor(first)
    second_ref = Process.monitor(second)
    Diagnostics.cancel_interactive(self())
    assert_receive {:DOWN, ^first_ref, :process, ^first, _}, 1000
    assert_receive {:DOWN, ^second_ref, :process, ^second, _}, 1000
  end

  test "owner death cancels its workers without stopping the coordinator" do
    parent = self()

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    Diagnostics.submit(owner, "owner-job", "test", nil, fn ->
      send(parent, {:owner_worker, self()})

      receive do
        :finish -> {:ok, %{}}
      end
    end)

    assert_receive {:owner_worker, worker}, 1000
    ref = Process.monitor(worker)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    assert Process.alive?(Process.whereis(Diagnostics))
  end
end
