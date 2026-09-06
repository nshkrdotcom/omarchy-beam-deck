defmodule BeamDeck.V11IntegrationTest do
  use ExUnit.Case
  @moduletag :integration
  alias BeamDeck.{BudgetTrial, Config, Json, Remote, TestPeer, Watchlist}

  alias BeamDeck.Diagnostics.Ets, as: EtsDiagnostics
  alias BeamDeck.Diagnostics.Process, as: ProcessDiagnostics

  setup do
    {peer, node} = TestPeer.start()
    on_exit(fn -> TestPeer.stop(peer) end)
    %{peer: peer, node: node, name: Atom.to_string(node), opts: Config.defaults()["diagnostics"]}
  end

  test "focused diagnostics use real OTP ancestry and exclude dictionary, state, binary IDs and contents",
       c do
    pid = Remote.call(c.node, :erlang, :whereis, [:bd_test_worker], nil)
    assert is_pid(pid)
    text = Remote.pid_text(pid)
    assert {:ok, ^pid} = Remote.parse_pid(c.node, text)
    assert {:ok, report} = ProcessDiagnostics.inspect_process(c.node, text, c.opts)
    assert report.registered_name == "bd_test_worker"
    assert report.stack != []
    assert Enum.any?(report.ancestry, &(&1[:name] == "bd_test_sup"))
    assert report.binaries.referenced_bytes > 0
    refute Enum.any?(report.binaries.top, &Map.has_key?(&1, :id))
    wire = Json.encode(report)
    refute wire =~ "BD_FIXTURE_DICTIONARY"
    refute wire =~ "BD_FIXTURE_ETS"
    refute wire =~ "BD_FIXTURE_BINARY"
    refute wire =~ "private_fixture_data"
  end

  test "registered pin follows a supervised replacement without persisting PID", c do
    assert %{status: "present", pid: old} = Watchlist.resolve(c.node, "bd_test_worker")
    pid = Remote.call(c.node, :erlang, :whereis, [:bd_test_worker], nil)
    assert {:ok, true} = Remote.call_raw(c.node, :erlang, :exit, [pid, :kill])

    TestPeer.eventually(fn ->
      case Watchlist.resolve(c.node, "bd_test_worker") do
        %{status: "present", pid: current} -> current != old
        _ -> false
      end
    end)

    assert {:ok, pin} =
             Watchlist.normalize(%{
               "kind" => "registered_process",
               "node" => c.name,
               "name" => "bd_test_worker"
             })

    refute Map.has_key?(pin, "pid")

    assert %{status: "missing"} =
             Watchlist.resolve(c.node, "name_that_has_never_been_an_atom_928349823")
  end

  test "metadata-only ETS inspection and cap run against actual named and private tables", c do
    assert {:ok, report} = EtsDiagnostics.inspect_tables(c.node, "memory", c.opts)
    row = Enum.find(report.top, &(&1.name == "bd_test_table"))
    assert row && row.size == 1
    assert row.memory_bytes == row.memory_words * report.wordsize
    refute Json.encode(report) =~ "BD_FIXTURE_ETS"
    assert {:ok, 12} = Remote.call_raw(c.node, :bd_test_worker, :make_tables, [12])
    bounded = Map.put(c.opts, "ets_max_tables", 4)
    assert {:ok, partial} = EtsDiagnostics.inspect_tables(c.node, "size", bounded)
    assert partial.partial
    assert partial.attempted_tables == 4
    assert partial.scanned_tables <= 4
  end

  test "scheduler measurement owns its lifetime and does not disable another owner", c do
    assert {:ok, owner} = Remote.call_raw(c.node, :bd_test_worker, :walltime_owner, [])
    on_exit(fn -> Remote.call_raw(c.node, :erlang, :exit, [owner, :kill]) end)
    sample = Remote.utilization_sample(c.node)
    assert sample != []
    assert Enum.all?(sample, &(&1.utilization >= 0 and &1.utilization <= 1))
    assert is_list(Remote.call(c.node, :erlang, :statistics, [:scheduler_wall_time], nil))
    assert {:ok, true} = Remote.call_raw(c.node, :erlang, :exit, [owner, :kill])

    TestPeer.eventually(fn ->
      Remote.call(c.node, :erlang, :statistics, [:scheduler_wall_time], nil) == :undefined
    end)
  end

  test "panel close rolls back an actual scheduler trial", c do
    start_supervised!(BudgetTrial)
    {rows, budget, nodes} = proposal(c)
    BudgetTrial.panel(true, 1, self())
    assert {:ok, trial} = BudgetTrial.begin(rows, budget, nodes, 1, 30_000)
    assert schedulers(c.node) == 1
    BudgetTrial.panel(false, 2, self())
    TestPeer.eventually(fn -> BudgetTrial.status().status == "reverted" end)
    assert schedulers(c.node) == 3
    assert BudgetTrial.status().trial_id == trial.trial_id
  end

  test "Keep retains first-original restoration even after earlier manual adjustment", c do
    start_supervised!(BudgetTrial)
    BudgetTrial.panel(true, 1, self())
    assert {:ok, _} = BudgetTrial.set(c.name, :schedulers_online, 2)
    {rows, budget, nodes} = proposal(c, 2)
    assert {:ok, trial} = BudgetTrial.begin(rows, budget, nodes, 1, 30_000)
    assert {:ok, %{status: "kept"}} = BudgetTrial.keep(trial.trial_id)
    assert schedulers(c.node) == 1
    assert {:ok, %{restored: true}} = BudgetTrial.restore(c.name)
    assert schedulers(c.node) == 3
  end

  @tag timeout: 20_000
  test "lease expiry and owner loss restore the actual target", c do
    start_supervised!(BudgetTrial)
    {rows, budget, nodes} = proposal(c)

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Elixir.Process.exit(owner, :kill) end)
    BudgetTrial.panel(true, 1, owner)
    assert {:ok, _} = BudgetTrial.begin(rows, budget, nodes, 1, 5_000)
    TestPeer.eventually(fn -> BudgetTrial.status().status == "reverted" end, 350)
    assert schedulers(c.node) == 3
    BudgetTrial.panel(true, 2, owner)
    assert {:ok, _} = BudgetTrial.begin(rows, budget, nodes, 2, 30_000)
    Elixir.Process.exit(owner, :kill)
    TestPeer.eventually(fn -> BudgetTrial.status().status == "reverted" end)
    assert schedulers(c.node) == 3
  end

  test "failure on a later node rolls back the earlier node", c do
    start_supervised!(BudgetTrial)
    {rows, budget, nodes} = proposal(c)
    host = c.name |> String.split("@") |> List.last()
    missing = "bd_missing_#{System.unique_integer([:positive])}@#{host}"
    # Test-only controlled node name admission, not application input conversion.
    _ = String.to_atom(missing)
    rows = rows ++ [%{"node" => missing, "current" => 3, "suggested" => 1}]
    budget = budget ++ [%{node: missing, current: 3, suggested: 1}]
    nodes = nodes ++ [%{name: missing, attached: true, local: true, schedulers_online: 3}]
    BudgetTrial.panel(true, 1, self())
    assert {:error, :trial_not_applied} = BudgetTrial.begin(rows, budget, nodes, 1, 30_000)
    TestPeer.eventually(fn -> BudgetTrial.status().status == "reverted" end)
    assert schedulers(c.node) == 3
  end

  test "rollback never overwrites an external concurrent change and retains recovery", c do
    start_supervised!(BudgetTrial)
    {rows, budget, nodes} = proposal(c)
    BudgetTrial.panel(true, 1, self())
    assert {:ok, trial} = BudgetTrial.begin(rows, budget, nodes, 1, 30_000)
    assert {:ok, 1} = Remote.set_flag(c.node, :schedulers_online, 2)
    assert {:ok, _} = BudgetTrial.revert(trial.trial_id)
    TestPeer.eventually(fn -> BudgetTrial.status().status == "rollback_failed" end)
    assert schedulers(c.node) == 2
    assert [%{error: :externally_changed}] = BudgetTrial.status().failures
    assert {:ok, 2} = Remote.set_flag(c.node, :schedulers_online, 1)
    assert {:ok, _} = BudgetTrial.revert(trial.trial_id)
    TestPeer.eventually(fn -> BudgetTrial.status().status == "reverted" end)
    assert schedulers(c.node) == 3
  end

  @tag timeout: 40_000
  test "normal scheduler mutations restore OTP-coupled dirty CPU scheduler state" do
    start_supervised!(BudgetTrial)
    {:ok, peer, node} = scheduler_coupling_peer()

    on_exit(fn ->
      if Process.alive?(peer), do: :peer.stop(peer)
    end)

    c = %{node: node, name: Atom.to_string(node)}
    assert_scheduler_pair(node, 8, 4)

    {rows, budget, nodes} = proposal(c, 8)

    # Explicit Revert.
    BudgetTrial.panel(true, 10, self())
    assert {:ok, trial} = BudgetTrial.begin(rows, budget, nodes, 10, 30_000)
    assert_scheduler_pair(node, 1, 1)
    assert {:ok, _} = BudgetTrial.revert(trial.trial_id)
    TestPeer.eventually(fn -> BudgetTrial.status().status == "reverted" end)
    assert_scheduler_pair(node, 8, 4)

    # Panel-close rollback.
    BudgetTrial.panel(true, 11, self())
    assert {:ok, _} = BudgetTrial.begin(rows, budget, nodes, 11, 30_000)
    assert_scheduler_pair(node, 1, 1)
    BudgetTrial.panel(false, 12, self())
    TestPeer.eventually(fn -> BudgetTrial.status().status == "reverted" end)
    assert_scheduler_pair(node, 8, 4)

    # Lease expiry.
    BudgetTrial.panel(true, 13, self())
    assert {:ok, _} = BudgetTrial.begin(rows, budget, nodes, 13, 5_000)
    assert_scheduler_pair(node, 1, 1)
    TestPeer.eventually(fn -> BudgetTrial.status().status == "reverted" end, 350)
    assert BudgetTrial.status().reason == :lease_expired
    assert_scheduler_pair(node, 8, 4)

    # Keep followed by first-original Restore.
    BudgetTrial.panel(true, 14, self())
    assert {:ok, kept_trial} = BudgetTrial.begin(rows, budget, nodes, 14, 30_000)
    assert_scheduler_pair(node, 1, 1)
    assert {:ok, %{status: "kept"}} = BudgetTrial.keep(kept_trial.trial_id)
    assert_scheduler_pair(node, 1, 1)
    assert {:ok, %{restored: true}} = BudgetTrial.restore(c.name)
    assert_scheduler_pair(node, 8, 4)

    # Legacy/manual normal-scheduler control has the same coupled guarantee.
    BudgetTrial.panel(true, 15, self())

    assert {:ok, %{previous: 8, applied: 1}} =
             BudgetTrial.set(c.name, :schedulers_online, 1)

    assert_scheduler_pair(node, 1, 1)
    assert {:ok, %{restored: true}} = BudgetTrial.restore(c.name)
    assert_scheduler_pair(node, 8, 4)
  end

  defp scheduler_coupling_peer do
    name =
      String.to_atom("bd_scheduler_coupling_#{System.unique_integer([:positive])}")

    :peer.start(%{
      name: name,
      wait_boot: 15_000,
      args: [
        ~c"+S",
        ~c"8:8",
        ~c"+SDcpu",
        ~c"4:4",
        ~c"+SDio",
        ~c"1",
        ~c"-setcookie",
        ~c"beam_deck_test_cookie"
      ]
    })
  end

  defp assert_scheduler_pair(node, normal, dirty) do
    assert Remote.call(
             node,
             :erlang,
             :system_info,
             [:schedulers_online],
             nil
           ) == normal

    assert Remote.call(
             node,
             :erlang,
             :system_info,
             [:dirty_cpu_schedulers_online],
             nil
           ) == dirty
  end

  defp proposal(c, current \\ 3) do
    {[%{"node" => c.name, "current" => current, "suggested" => 1}],
     [%{node: c.name, current: current, suggested: 1}],
     [
       %{
         name: c.name,
         attached: true,
         local: true,
         schedulers_online: current,
         creation: Remote.call(c.node, :erlang, :system_info, [:creation], nil),
         os_pid:
           Remote.call(c.node, :os, :getpid, [], ~c"0") |> to_string() |> String.to_integer()
       }
     ]}
  end

  defp schedulers(node), do: Remote.call(node, :erlang, :system_info, [:schedulers_online], nil)

  test "GC rejects a report from another VM incarnation without collecting", c do
    {:ok, identity} = Remote.identity(c.node)
    pid = Remote.call(c.node, :erlang, :whereis, [:bd_test_worker], nil)

    assert {:error, :target_restarted} =
             Remote.trigger_gc(c.node, Remote.pid_text(pid), identity.creation + 1)

    assert {:ok, true} = Remote.trigger_gc(c.node, Remote.pid_text(pid), identity.creation)
  end

  test "OTP 28 trace session exits with its actual parent without replacing system_monitor", c do
    otp =
      Remote.call(c.node, :erlang, :system_info, [:otp_release], ~c"0")
      |> to_string()
      |> String.to_integer()

    if otp >= 28 do
      parent =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      on_exit(fn -> Process.exit(parent, :kill) end)
      before = Remote.call(c.node, :erlang, :system_monitor, [], nil)

      assert {:ok, probe} =
               BeamDeck.DeepEvents.start(c.node, Config.defaults()["event_thresholds"], parent)

      Process.exit(parent, :kill)

      TestPeer.eventually(fn ->
        Remote.call(c.node, :erlang, :is_process_alive, [probe], true) == false
      end)

      assert Remote.call(c.node, :erlang, :system_monitor, [], nil) == before
      assert :ok = BeamDeck.DeepEvents.stop(c.node, probe)
      assert Remote.call(c.node, :code, :is_loaded, [:nshkr_beam_deck_probe], :unknown) == false
    else
      assert {:ok, info} = Remote.inspect_node(c.node)
      refute info.deep_events_capable
    end
  end

  @tag timeout: 20_000
  test "a disposable real VM crash yields bounded metadata, never its application payload", c do
    dir = Path.join(System.tmp_dir!(), "bd-real-crash-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, "erl_crash.dump")
    assert {:ok, :ok} = Remote.call_raw(c.node, :file, :set_cwd, [String.to_charlist(dir)])

    assert {:ok, true} =
             Remote.call_raw(c.node, :os, :putenv, [~c"ERL_CRASH_DUMP", String.to_charlist(path)])

    assert {:ok, true} =
             Remote.call_raw(c.node, :os, :putenv, [~c"ERL_CRASH_DUMP_SECONDS", ~c"2"])

    {:ok, identity} = Remote.identity(c.node)
    pid = String.to_integer(identity.os_pid)
    runtime = Enum.find(BeamDeck.Procfs.snapshot().runtimes, &(&1.pid == pid))
    assert runtime && runtime.cwd == dir
    before = %{runtimes: [Map.put(runtime, :node_name, c.name)]}
    Remote.call_raw(c.node, :erlang, :halt, [~c"BEAM_DECK_CONTROLLED_TEST_CRASH"], 4000)
    TestPeer.eventually(fn -> not File.exists?("/proc/#{pid}") end)

    [exit] =
      BeamDeck.CrashDump.disappeared(before, %{runtimes: []}, System.system_time(:millisecond))

    report = BeamDeck.CrashDump.triage(exit, c.opts)
    assert report.status == "matched"
    assert report.bytes_read <= c.opts["crash_dump_read_bytes"]
    assert report.slogan =~ "BEAM_DECK_CONTROLLED_TEST_CRASH"
    refute Json.encode(report) =~ "BD_FIXTURE_DICTIONARY"
    refute Json.encode(report) =~ "BD_FIXTURE_BINARY"
    refute Json.encode(report) =~ "BD_FIXTURE_ETS"
  end
end
