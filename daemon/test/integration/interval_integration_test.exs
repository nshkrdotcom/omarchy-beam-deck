defmodule BeamDeck.IntervalIntegrationTest do
  use ExUnit.Case
  @moduletag :integration
  alias BeamDeck.{Config, Json, Remote, TestPeer}
  alias BeamDeck.Diagnostics.{Interval, StackSample, Window}

  setup do
    {peer, node} = TestPeer.start()
    on_exit(fn -> TestPeer.stop(peer) end)
    %{node: node, opts: Config.defaults()["diagnostics"]}
  end

  test "real admitted census yields exact PID interval evidence and obeys admission", c do
    assert {:ok, first} = Window.capture("process_window", c.node, c.opts)
    assert Enum.any?(first.rows, &(&1.name == "bd_test_worker"))
    assert first.scanned > 10

    assert {:error, :process_survey_population_capped} =
             Window.capture("process_window", c.node, Map.put(c.opts, "window_max_processes", 1))

    assert {:ok, report} = Window.run("process_window", c.node, 1000, c.opts)
    assert report.span_ms >= 1000 && report.matched > 10
    assert length(report.rows) <= 60
    refute Json.encode(report) =~ "BD_FIXTURE_DICTIONARY"
  end

  test "real table growth is measured and a recreated named table has a new identity", c do
    assert {:ok, first} = Window.capture("ets_window", c.node, c.opts)
    original = Enum.find(first.rows, &(&1.name == "bd_test_table"))
    assert original && is_binary(original.identity)

    assert {:ok, :ok} =
             Remote.call_raw(c.node, :gen_server, :call, [:bd_test_worker, :grow_table])

    assert {:ok, second} = Window.capture("ets_window", c.node, c.opts)
    assert {:ok, diff} = Interval.compare("ets_window", first, second)
    row = Enum.find(diff.rows, &(&1.name == "bd_test_table"))
    assert row.size_delta == 1
    assert row.memory_delta_bytes > 0
    refute Json.encode(diff) =~ "ETS_WINDOW_CANARY"
    assert {:ok, old} = Remote.call_raw(c.node, :erlang, :whereis, [:bd_test_worker])
    assert {:ok, true} = Remote.call_raw(c.node, :erlang, :exit, [old, :kill])

    TestPeer.eventually(fn ->
      Remote.call(c.node, :erlang, :whereis, [:bd_test_worker], nil) != old
    end)

    assert {:ok, third} = Window.capture("ets_window", c.node, c.opts)
    replacement = Enum.find(third.rows, &(&1.name == "bd_test_table"))
    refute original.identity == replacement.identity
  end

  test "exact-PID sampling observes waiting stacks and stops when the process exits", c do
    pid = Remote.call(c.node, :erlang, :whereis, [:bd_test_worker], nil)
    assert {:ok, report} = StackSample.run(c.node, Remote.pid_text(pid), 1000)
    assert report.samples == 4
    assert report.span_ms >= 750
    assert Enum.any?(report.statuses, &(&1.status == "waiting"))
    assert report.stacks != []
    refute Json.encode(report) =~ "BD_FIXTURE_DICTIONARY"
    assert {:ok, true} = Remote.call_raw(c.node, :erlang, :exit, [pid, :kill])
    assert {:error, :process_exited} = StackSample.run(c.node, Remote.pid_text(pid), 1000)
  end

  test "collectors preserve the requested incarnation at their own entry point", c do
    {:ok, creation} = Window.creation(c.node)
    opts = Map.put(c.opts, "expected_creation", creation + 1)
    assert {:error, :incomparable_identity} = Window.capture("process_window", c.node, opts)
    pid = Remote.call(c.node, :erlang, :whereis, [:bd_test_worker], nil)

    assert {:error, :incomparable_identity} =
             StackSample.run(c.node, Remote.pid_text(pid), 1000, creation + 1)
  end
end
