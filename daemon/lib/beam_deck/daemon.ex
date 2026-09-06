defmodule BeamDeck.Daemon do
  @moduledoc "Protocol and evidence owner. Remote collection runs outside the input mailbox."
  use GenServer

  alias BeamDeck.{
    Alerts,
    Budget,
    BudgetTrial,
    Config,
    CrashDump,
    DeepEvents,
    Diagnostics,
    Discovery,
    FlightRecorder,
    Forecast,
    History,
    Incidents,
    Json,
    Output,
    Procfs,
    Redaction,
    Remote,
    RestartChurn,
    Watchlist
  }

  alias BeamDeck.Diagnostics.Bundle
  alias BeamDeck.Diagnostics.Ets, as: EtsDiagnostics
  alias BeamDeck.Diagnostics.Process, as: ProcessDiagnostics
  @node_monitor_opts %{node_type: :all, nodedown_reason: true}
  @async ~w(inspect_process inspect_ets recorder_frame compare_frames export_bundle budget_trial_begin)

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def command(command, args), do: GenServer.cast(__MODULE__, {:command, command, args})
  def protocol_error(reason), do: GenServer.cast(__MODULE__, {:protocol_error, reason})

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)

    {config, path, error} =
      case Config.load() do
        {:ok, c, p} -> {c, p, nil}
        {:error, _reason, c, p} -> {c, p, "Invalid configuration; bounded defaults are active."}
      end

    Redaction.configure(config)
    Enum.each(config["nodes"], &Discovery.apply_cookie/1)
    :net_kernel.monitor_nodes(true, @node_monitor_opts)
    {pins, pin_error} = Watchlist.load()

    state = %{
      config: config,
      config_path: path,
      config_error: error,
      procfs: nil,
      snapshot: nil,
      history: [],
      learned: [],
      panel_open: false,
      panel_epoch: 0,
      probes: %{},
      events: [],
      poll_timer: nil,
      poll_task: nil,
      poll_deadline: nil,
      refresh_requested: false,
      last_deep_ms: 0,
      restart_events: %{},
      recorder: FlightRecorder.new(),
      incidents: [],
      notification_times: %{},
      crash_triage: [],
      watchlist_entries: pins,
      watchlist_error: pin_error,
      budget_trial: nil,
      session_id:
        "session-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"
    }

    BudgetTrial.panel(false, 0, self())
    {:ok, schedule_poll(state, 0)}
  end

  @impl true
  def handle_info(:poll, %{poll_task: nil} = state) do
    task = Task.Supervisor.async_nolink(BeamDeck.CollectionTasks, fn -> collect(state) end)
    timer = Process.send_after(self(), {:poll_deadline, task.ref}, 15_000)
    {:noreply, %{state | poll_task: task, poll_deadline: timer, poll_timer: nil}}
  end

  def handle_info(:poll, state),
    do: {:noreply, %{state | poll_timer: nil, refresh_requested: true}}

  def handle_info({ref, telemetry}, %{poll_task: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(state.poll_deadline)
    state = %{state | poll_task: nil, poll_deadline: nil}
    next = incorporate(state, telemetry)
    delay = if state.refresh_requested, do: 0, else: next.config["poll_interval_ms"]
    {:noreply, schedule_poll(%{next | refresh_requested: false}, delay)}
  end

  def handle_info({:poll_deadline, ref}, %{poll_task: %{ref: ref} = task} = state) do
    Task.Supervisor.terminate_child(BeamDeck.CollectionTasks, task.pid)
    Process.demonitor(ref, [:flush])

    emit(%{
      type: "error",
      error: "collection_timeout",
      reason:
        "Last successful telemetry remains visible; remote collection exceeded its deadline."
    })

    {:noreply,
     schedule_poll(
       %{state | poll_task: nil, poll_deadline: nil},
       state.config["poll_interval_ms"]
     )}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{poll_task: %{ref: ref}} = state) do
    Process.cancel_timer(state.poll_deadline)
    emit(%{type: "error", error: "collection_failed"})

    {:noreply,
     schedule_poll(
       %{state | poll_task: nil, poll_deadline: nil},
       state.config["poll_interval_ms"]
     )}
  end

  def handle_info({:diagnostic, %{kind: "_crash", status: "complete", result: triage}}, state) do
    rows = Enum.map(state.crash_triage, fn c -> if c.id == triage.id, do: triage, else: c end)
    {:noreply, reschedule_now(%{state | crash_triage: rows})}
  end

  def handle_info({:diagnostic, %{kind: "_crash", status: "error", request_id: id}}, state) do
    rows =
      Enum.map(state.crash_triage, fn c ->
        if "crash:" <> c.id == id, do: Map.put(c, :status, "triage_unavailable"), else: c
      end)

    {:noreply, reschedule_now(%{state | crash_triage: rows})}
  end

  def handle_info(
        {:diagnostic, %{kind: "_probe_start", status: "complete", result: result}},
        state
      ) do
    next = %{state | probes: Map.put(state.probes, result.name, result.pid)}
    next = if next.panel_open, do: next, else: stop_probes(next)
    emit_action("deep_events", result.name, %{enabled: next.panel_open})
    {:noreply, reschedule_now(next)}
  end

  def handle_info(
        {:diagnostic, %{kind: "_probe_stop", status: "complete", result: %{name: name}}},
        state
      ) do
    {:noreply, reschedule_now(%{state | probes: Map.delete(state.probes, name)})}
  end

  def handle_info(
        {:diagnostic,
         %{kind: "_watchlist_resolve", status: "complete", result: %{entry: entry, pid: pid}}},
        state
      ) do
    observed =
      Enum.map(snapshot_nodes(state), fn row ->
        if row.name == entry["node"],
          do: Map.put(row, :registered_processes, [%{name: entry["name"], pid: pid}]),
          else: row
      end)

    update_watchlist(Watchlist.add(state.watchlist_entries, entry, observed, state.config), state)
  end

  def handle_info({:diagnostic, message}, state) do
    cond do
      String.starts_with?(message.kind, "_") and message.status == "error" ->
        emit(%{
          type: "error",
          error: message[:error] || "diagnostic_failed",
          reason: message.kind
        })

      String.starts_with?(message.kind, "_") ->
        :ok

      true ->
        emit(message)
    end

    {:noreply, state}
  end

  def handle_info({:budget_trial, trial}, state) do
    emit(%{type: "budget_trial", trial: trial})
    {:noreply, reschedule_now(%{state | budget_trial: trial})}
  end

  def handle_info({:beam_deck_event, node, kind, who, info, at}, state) do
    event = %{
      id: event_id(),
      node: to_string(node),
      kind: to_string(kind),
      subject: who,
      info: Redaction.sanitize(info),
      at_ms: System.system_time(:millisecond),
      target_at_ms: at
    }

    emit(%{type: "event", event: event})
    next = %{state | events: Enum.take([event | state.events], 200)}
    next = if kind == :probe_overloaded, do: stop_probe(next, to_string(node)), else: next
    {:noreply, next}
  end

  def handle_info({:beam_deck_probe, _node, _status, _detail}, state), do: {:noreply, state}

  def handle_info({kind, node, info}, state) when kind in [:nodeup, :nodedown] do
    event = %{
      id: event_id(),
      node: to_string(node),
      kind: to_string(kind),
      subject: to_string(node),
      info: Redaction.sanitize(info),
      at_ms: System.system_time(:millisecond)
    }

    emit(%{type: "event", event: event})
    {:noreply, reschedule_now(%{state | events: Enum.take([event | state.events], 200)})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_cast({:protocol_error, _reason}, state) do
    emit(%{
      type: "error",
      error: "invalid_command",
      reason: "Command was rejected before execution."
    })

    {:noreply, state}
  end

  def handle_cast(:input_closed, state) do
    System.stop(0)
    {:noreply, state}
  end

  def handle_cast({:command, "refresh", _args}, state), do: {:noreply, reschedule_now(state)}

  def handle_cast({:command, "panel", %{"open" => open}}, state) do
    epoch = state.panel_epoch + 1
    BudgetTrial.panel(open, epoch, self())
    if not open, do: Diagnostics.cancel_interactive(self())
    next = %{state | panel_open: open, panel_epoch: epoch, last_deep_ms: 0}
    {:noreply, reschedule_now(if(open, do: next, else: stop_probes(next)))}
  end

  def handle_cast({:command, command, args}, state) when command in @async do
    submit_job(command, args, state)
    {:noreply, state}
  end

  def handle_cast({:command, command, args}, state)
      when command in ["set_schedulers", "set_dirty_schedulers", "restore", "gc"] do
    run_mutation(command, args, state)
    {:noreply, state}
  end

  def handle_cast({:command, command, args}, state)
      when command in ["budget_trial_keep", "budget_trial_revert"] do
    action = if command == "budget_trial_keep", do: :keep, else: :revert
    BudgetTrial.request(self(), action_id(), {action, args["trial_id"]})
    {:noreply, state}
  end

  def handle_cast(
        {:command, "deep_events", %{"node" => name, "enabled" => enabled}},
        state
      ) do
    cond do
      enabled and state.panel_open and not Map.has_key?(state.probes, name) ->
        {:noreply, start_probe(state, name)}

      enabled ->
        {:noreply, state}

      true ->
        {:noreply, stop_probe(state, name)}
    end
  end

  def handle_cast({:command, "watchlist_add", %{"entry" => entry}}, state) do
    if process_pin?(entry) do
      case queue_process_pin(entry, state) do
        :ok -> {:noreply, state}
        {:error, reason} -> update_watchlist({:error, reason}, state)
      end
    else
      update_watchlist(
        Watchlist.add(state.watchlist_entries, entry, snapshot_nodes(state), state.config),
        state
      )
    end
  end

  def handle_cast({:command, "watchlist_remove", %{"id" => id}}, state) do
    update_watchlist(Watchlist.remove(state.watchlist_entries, id), state)
  end

  def handle_cast({:command, command, _args}, state) do
    emit(%{type: "error", error: "unknown_command", command: command})
    {:noreply, state}
  end

  defp run_mutation(command, args, state) do
    name = args["node"]

    case mutation_target(name, state) do
      {:ok, node, expected} ->
        action = fn -> execute_mutation(command, args, name, node, expected) end
        submit(action_id(), command, name, action, interactive: false, timeout: 10_000)

      :error ->
        emit_action(command, name, %{error: "fresh_attached_node_and_open_panel_required"})
    end
  end

  defp mutation_target(name, state) do
    with true <- state.panel_open,
         {:ok, node} <- authorized_node(name, state),
         observed when not is_nil(observed) <-
           Enum.find(snapshot_nodes(state), &(&1.name == name)) do
      {:ok, node, observed[:creation]}
    else
      _ -> :error
    end
  end

  defp execute_mutation(command, args, name, node, observed_creation) do
    expected = args["expected_creation"] || observed_creation

    with {:ok, %{creation: creation}} <- Remote.identity(node),
         true <- creation == expected do
      mutation_result(command, args, name, node, expected)
    else
      _ -> {:error, :target_restarted_or_unavailable}
    end
  end

  defp mutation_result("set_schedulers", args, name, _node, _expected),
    do: BudgetTrial.set(name, :schedulers_online, args["value"])

  defp mutation_result("set_dirty_schedulers", args, name, _node, _expected),
    do: BudgetTrial.set(name, :dirty_cpu_schedulers_online, args["value"])

  defp mutation_result("restore", _args, name, _node, _expected), do: BudgetTrial.restore(name)

  defp mutation_result("gc", args, _name, node, expected),
    do: Remote.trigger_gc(node, args["pid"], expected)

  defp process_pin?(entry) do
    entry["kind"] == "registered_process" and is_binary(entry["name"])
  end

  defp queue_process_pin(entry, state) do
    with {:ok, normalized} <- Watchlist.normalize(entry),
         {:ok, node} <- authorized_node(normalized["node"], state) do
      submit(
        action_id(),
        "_watchlist_resolve",
        normalized["node"],
        fn -> resolve_process_pin(node, normalized) end,
        interactive: false,
        timeout: 2_000
      )

      :ok
    else
      _ -> {:error, :pin_not_currently_observed}
    end
  end

  defp resolve_process_pin(node, normalized) do
    case Watchlist.resolve(node, normalized["name"]) do
      %{status: "present", pid: pid} -> {:ok, %{entry: normalized, pid: pid}}
      _ -> {:error, :pin_not_currently_observed}
    end
  end

  defp start_probe(state, name) do
    case authorized_node(name, state) do
      {:ok, node} -> queue_probe_start(node, name, state)
      _ -> emit_action("deep_events", name, %{error: "fresh_attached_node_required"})
    end

    state
  end

  defp queue_probe_start(node, name, state) do
    owner = self()

    submit(
      action_id(),
      "_probe_start",
      name,
      fn -> probe_start_result(node, name, owner, state.config["event_thresholds"]) end,
      interactive: false,
      timeout: 10_000
    )
  end

  defp probe_start_result(node, name, owner, thresholds) do
    case DeepEvents.start(node, thresholds, owner) do
      {:ok, pid} -> {:ok, %{name: name, pid: pid}}
      _ -> {:error, :probe_unavailable}
    end
  end

  @impl true
  def terminate(_reason, state) do
    BudgetTrial.panel(false, state.panel_epoch + 1, self())

    Enum.each(state.probes, fn {name, pid} ->
      with {:ok, node} <- Discovery.existing_node(name), do: DeepEvents.stop(node, pid)
    end)

    :net_kernel.monitor_nodes(false, @node_monitor_opts)
    :ok
  end

  defp submit_job("inspect_process" = command, args, state) do
    opts = state.config["diagnostics"]

    remote_job(
      args["request_id"],
      command,
      args["node"],
      state,
      fn node -> ProcessDiagnostics.inspect_process(node, args["pid"], opts) end,
      opts["process_timeout_ms"] + 1_000
    )
  end

  defp submit_job("inspect_ets" = command, args, state) do
    opts = state.config["diagnostics"]

    remote_job(
      args["request_id"],
      command,
      args["node"],
      state,
      fn node -> EtsDiagnostics.inspect_tables(node, args["sort"] || "memory", opts) end,
      opts["ets_timeout_ms"] + 1_000
    )
  end

  defp submit_job("recorder_frame" = command, args, state) do
    submit(args["request_id"], command, nil, fn ->
      FlightRecorder.get(state.recorder, args["frame_id"])
    end)
  end

  defp submit_job("compare_frames" = command, args, state) do
    submit(args["request_id"], command, nil, fn ->
      FlightRecorder.compare(state.recorder, args["from_frame_id"], args["to_frame_id"])
    end)
  end

  defp submit_job("export_bundle" = command, args, state) do
    submit(
      args["request_id"],
      command,
      nil,
      fn ->
        Bundle.export(
          state.snapshot || %{},
          state.recorder,
          args["from_frame_id"],
          args["to_frame_id"]
        )
      end,
      interactive: false,
      timeout: 30_000
    )
  end

  defp submit_job("budget_trial_begin" = command, args, state) do
    submit(
      args["request_id"],
      command,
      "_control",
      fn ->
        BudgetTrial.begin(
          args["rows"],
          (state.snapshot && state.snapshot.budget) || [],
          snapshot_nodes(state),
          state.panel_epoch,
          state.config["budget_trial_lease_ms"]
        )
      end,
      interactive: false,
      timeout: 30_000
    )
  end

  defp remote_job(id, kind, name, state, fun, timeout) do
    with true <- state.panel_open, {:ok, node} <- authorized_node(name, state) do
      submit(id, kind, name, fn -> fun.(node) end, timeout: timeout)
    else
      _ ->
        emit(%{
          type: "job",
          request_id: id,
          kind: kind,
          status: "error",
          error: "node_unavailable_or_panel_closed"
        })
    end
  end

  defp submit(id, kind, node, fun, opts \\ []) do
    case Diagnostics.submit(self(), id, kind, node, fun, opts) do
      :ok ->
        :ok

      {:error, reason} ->
        emit(%{type: "job", request_id: id, kind: kind, status: "error", error: reason})
        {:error, reason}
    end
  end

  defp authorized_node(name, state) do
    fresh =
      not is_nil(state.snapshot) and
        System.system_time(:millisecond) - state.snapshot.at_ms <= 30_000

    if fresh and Enum.any?(snapshot_nodes(state), &(&1.name == name and &1[:attached])),
      do: Discovery.existing_node(name),
      else: {:error, :unknown_or_stale_node}
  end

  defp snapshot_nodes(state), do: (state.snapshot && state.snapshot.nodes) || []

  defp update_watchlist({:ok, entries}, state) do
    emit_action("watchlist", nil, %{saved: true})
    {:noreply, reschedule_now(%{state | watchlist_entries: entries, watchlist_error: nil})}
  end

  defp update_watchlist({:error, reason}, state) do
    emit_action("watchlist", nil, %{error: reason})
    {:noreply, %{state | watchlist_error: Atom.to_string(reason)}}
  end

  defp stop_probes(state), do: Enum.reduce(Map.keys(state.probes), state, &stop_probe(&2, &1))

  defp stop_probe(state, name) do
    case state.probes[name] do
      nil -> :ok
      pid -> queue_probe_stop(name, pid)
    end

    state
  end

  defp queue_probe_stop(name, pid) do
    case Discovery.existing_node(name) do
      {:ok, node} ->
        submit(
          action_id(),
          "_probe_stop",
          name,
          fn -> probe_stop_result(node, pid, name) end,
          interactive: false,
          timeout: 8_000
        )

      _ ->
        :ok
    end
  end

  defp probe_stop_result(node, pid, name) do
    case DeepEvents.stop(node, pid) do
      :ok -> {:ok, %{name: name}}
      _ -> {:error, :probe_stop_unconfirmed}
    end
  end

  defp collect(state) do
    host = Procfs.snapshot("/proc", state.procfs)

    candidates =
      Discovery.candidates(
        state.config,
        state.learned ++ Enum.map(state.watchlist_entries, & &1["node"])
      )

    # Rotate admission so an unreachable prefix cannot starve every later node.
    offset =
      if candidates == [], do: 0, else: rem(state.recorder.sequence * 4, length(candidates))

    candidates = Enum.drop(candidates, offset) ++ Enum.take(candidates, offset)
    mono = System.monotonic_time(:millisecond)

    deep =
      state.panel_open and
        (state.last_deep_ms == 0 or mono - state.last_deep_ms >= state.config["deep_interval_ms"])

    previous = Map.new(snapshot_nodes(state), &{&1.name, &1})
    deadline = mono + 6_000

    nodes =
      candidates
      |> Task.async_stream(
        fn node ->
          Process.put(:beam_deck_rpc_deadline, deadline)
          inspect_candidate(node, state, previous, deep)
        end,
        max_concurrency: 4,
        timeout: 7_000,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(candidates)
      |> Enum.map(fn
        {{:ok, info}, _node} -> info
        {_, node} -> unattached(node, state.config, "collection_deadline")
      end)

    nodes = Procfs.verify_local_nodes(host, nodes) |> Enum.sort_by(& &1.name)
    host = correlate_runtimes(host, nodes)

    %{
      host: host,
      nodes: nodes,
      deep: deep,
      mono: mono,
      at_ms: System.system_time(:millisecond),
      watch_rows: Watchlist.poll(state.watchlist_entries, nodes)
    }
  end

  defp inspect_candidate(node, state, previous, deep) do
    case Remote.inspect_node(node,
           processes: deep,
           max_process_scan: state.config["max_process_scan"],
           scheduler_wall_time: false
         ) do
      {:ok, info} -> enrich_candidate(node, info, state, previous, deep)
      {:error, _} -> unattached(node, state.config, "authentication_or_unreachable")
    end
  end

  defp enrich_candidate(node, info, state, previous, deep) do
    previous_info = previous[info.name]
    info = carry_deep_sample(info, previous_info, deep)

    utilization =
      if deep, do: Remote.utilization_sample(node), else: info[:scheduler_utilization] || []

    info
    |> Map.merge(Discovery.metadata(state.config, node))
    |> Map.put(:scheduler_utilization, utilization)
  end

  defp carry_deep_sample(info, _previous, true), do: info
  defp carry_deep_sample(info, nil, false), do: info

  defp carry_deep_sample(info, previous, false) do
    if reusable_deep_sample?(info, previous) do
      Enum.reduce(deep_sample_keys(), info, &copy_if_present(previous, &1, &2))
    else
      info
    end
  end

  defp reusable_deep_sample?(info, previous) do
    is_integer(previous[:uptime_ms]) and info.uptime_ms >= previous.uptime_ms and
      info[:creation] == previous[:creation]
  end

  defp deep_sample_keys do
    [
      :hot_processes,
      :registered_processes,
      :hot_processes_at_ms,
      :process_scan_error,
      :scheduler_utilization
    ]
  end

  defp copy_if_present(previous, key, info) do
    if Map.has_key?(previous, key), do: Map.put(info, key, previous[key]), else: info
  end

  defp unattached(node, config, error) do
    %{
      name: Atom.to_string(node),
      attached: false,
      local: Discovery.local_node?(node),
      error: error,
      hot_processes: [],
      registered_processes: [],
      peers: [],
      deep_events_active: false,
      capabilities: %{}
    }
    |> Map.merge(Discovery.metadata(config, node))
  end

  defp queue_crash_triage(exit, state) do
    frame = List.first(state.recorder.frames)
    exit = Map.put(exit, :last_frame_id, if(frame, do: frame.frame_id, else: nil))

    case submit(
           "crash:#{exit.id}",
           "_crash",
           nil,
           fn -> {:ok, CrashDump.triage(exit, state.config["diagnostics"])} end,
           interactive: false,
           timeout: 8_000
         ) do
      :ok -> exit
      _ -> Map.put(exit, :status, "triage_unavailable")
    end
  end

  defp incorporate(state, telemetry) do
    at = telemetry.at_ms

    nodes =
      Enum.map(
        telemetry.nodes,
        &Map.put(&1, :deep_events_active, Map.has_key?(state.probes, &1.name))
      )

    {restart_events, nodes} =
      RestartChurn.update(state.restart_events, nodes, snapshot_nodes(state), at, telemetry.deep)

    exits = CrashDump.disappeared(state.procfs, telemetry.host, at)

    exits = Enum.map(exits, &queue_crash_triage(&1, state))

    retained =
      Enum.filter(state.crash_triage, &(at - &1.at_ms <= state.config["incident_retention_ms"]))

    triage =
      Enum.take(Enum.map(exits, &Map.drop(&1, [:cwd, :previous_fingerprint])) ++ retained, 256)

    host = %{
      telemetry.host
      | runtimes: Enum.map(telemetry.host.runtimes, &Map.delete(&1, :crash_dump_fingerprint))
    }

    current = %{
      type: "snapshot",
      protocol: 1,
      session_id: state.session_id,
      at_ms: at,
      onboarding: onboarding(host, nodes),
      host: Map.drop(host, [:host_ticks, :monotonic_ms]),
      nodes: nodes,
      topology: topology(nodes),
      events: Enum.take(state.events, 30),
      config_path: state.config_path,
      config_error: state.config_error,
      budget_trial: state.budget_trial,
      crash_triage: triage
    }

    alerts = Alerts.derive(current, state.snapshot, state.config)

    current =
      Map.merge(current, %{
        alerts: alerts,
        summary: summary(host, nodes, alerts),
        budget: Budget.recommend(nodes, host.logical_cpus)
      })

    history = History.push(state.history, history_sample(current), state.config["history_points"])

    current =
      Map.merge(current, %{
        history: History.present(history, 120),
        forecasts: Forecast.derive(history, state.config)
      })

    pin_ids = Enum.map(state.watchlist_entries, & &1["id"])
    watches = Enum.filter(telemetry.watch_rows, &(&1["id"] in pin_ids))
    current = Map.put(current, :watchlist, %{entries: watches, error: state.watchlist_error})

    recorder =
      FlightRecorder.push(state.recorder, current, state.config["flight_recorder_points"])

    incidents = Incidents.update(state.incidents, current, state.config, recorder)
    current = Map.put(current, :incidents, incidents)

    summary =
      Map.merge(current.summary, %{
        active_incident_count: Enum.count(incidents, &(&1.status == "active")),
        critical_incident_count:
          Enum.count(incidents, &(&1.status == "active" and &1.severity == "critical")),
        forecast_warning_count:
          Enum.count(current.forecasts, &(&1.severity in ["warning", "critical"])),
        watched_problem_count:
          Enum.count(
            watches,
            &(&1["status"] != "present" or (&1["mailbox"] || 0) >= state.config["mailbox_warn"])
          )
      })

    current = %{current | summary: summary}
    current = Map.put(current, :flight_recorder, FlightRecorder.present(recorder))

    {intents, sent} =
      Incidents.notifications(
        incidents,
        state.incidents,
        state.notification_times,
        at,
        state.config
      )

    Enum.each(intents, &emit/1)
    emit(current)

    %{
      state
      | snapshot: current,
        procfs: telemetry.host,
        history: history,
        incidents: incidents,
        notification_times: sent,
        recorder: recorder,
        crash_triage: triage,
        restart_events: restart_events,
        last_deep_ms: if(telemetry.deep, do: telemetry.mono, else: state.last_deep_ms),
        learned: nodes |> Enum.flat_map(&(&1[:peers] || [])) |> Enum.uniq() |> Enum.take(64)
    }
  end

  defp history_sample(snapshot) do
    %{
      at_ms: snapshot.at_ms,
      schedulers_online: snapshot.summary.schedulers_online,
      process_count: snapshot.summary.process_count,
      beam_rss_bytes: snapshot.summary.beam_rss_bytes,
      nodes:
        Enum.map(
          snapshot.nodes,
          &Map.take(
            &1,
            ~w(name attached creation uptime_ms processes process_limit atoms atom_limit ports port_limit ets memory run_queue schedulers_online)a
          )
        )
    }
  end

  defp onboarding(host, nodes) do
    cond do
      Enum.any?(nodes, & &1.attached) ->
        %{state: "ready"}

      host.runtimes == [] ->
        %{state: "no_runtimes", message: "BEAM is installed; no local workload VMs are running."}

      true ->
        %{
          state: "os_only",
          message: "OS visibility only; name a development VM to enable OTP inspection.",
          launch_example: "iex --sname my_app -S mix phx.server"
        }
    end
  end

  defp summary(host, nodes, alerts) do
    attached = Enum.filter(nodes, & &1.attached)
    local = Enum.filter(attached, & &1.local)

    %{
      runtime_count: length(host.runtimes),
      distributed_count: length(nodes),
      attached_count: length(attached),
      local_attached_count: length(local),
      logical_cpus: host.logical_cpus,
      schedulers_online: Enum.sum(Enum.map(local, &(&1[:schedulers_online] || 0))),
      beam_rss_bytes: Enum.sum(Enum.map(host.runtimes, & &1.rss_bytes)),
      process_count: Enum.sum(Enum.map(local, &(&1[:processes] || 0))),
      warning_count: Enum.count(alerts, &(&1.severity == "warning")),
      critical_count: Enum.count(alerts, &(&1.severity == "critical"))
    }
  end

  defp topology(nodes),
    do:
      Enum.map(nodes, fn n ->
        %{
          node: n.name,
          sees: n[:peers] || [],
          expected: n[:expected_peers] || [],
          missing: (n[:expected_peers] || []) -- (n[:peers] || []),
          attached: n.attached,
          local: n.local
        }
      end)

  defp correlate_runtimes(host, nodes) do
    local =
      nodes
      |> Enum.filter(&(&1.attached and &1.local and is_integer(&1[:os_pid])))
      |> Map.new(&{&1.os_pid, &1.name})

    runtimes =
      Enum.map(host.runtimes, fn r ->
        if local[r.pid], do: Map.merge(r, %{os_only: false, node_name: local[r.pid]}), else: r
      end)

    %{host | runtimes: runtimes}
  end

  defp reschedule_now(%{poll_task: task} = state) when not is_nil(task),
    do: %{state | refresh_requested: true}

  defp reschedule_now(state) do
    if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
    schedule_poll(%{state | poll_timer: nil}, 0)
  end

  defp schedule_poll(state, delay),
    do: %{state | poll_timer: Process.send_after(self(), :poll, delay)}

  defp action_id, do: "action:#{System.unique_integer([:positive, :monotonic])}"
  defp event_id, do: "event:#{System.unique_integer([:positive, :monotonic])}"

  defp emit_action(action, node, result),
    do: emit(%{type: "action", action: action, node: node, result: result})

  defp emit(map), do: map |> Redaction.sanitize() |> Json.encode() |> Output.puts()
end
