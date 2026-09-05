defmodule BeamDeck.Daemon do
  @moduledoc false
  use GenServer

  alias BeamDeck.{
    Alerts,
    Budget,
    Config,
    DeepEvents,
    Discovery,
    History,
    Json,
    Output,
    Procfs,
    Remote,
    RestartChurn
  }

  @node_monitor_opts %{node_type: :all, nodedown_reason: true}

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def command(command, args), do: GenServer.cast(__MODULE__, {:command, command, args})
  def protocol_error(reason), do: GenServer.cast(__MODULE__, {:protocol_error, reason})

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)

    {config, config_path, config_error} =
      case Config.load() do
        {:ok, loaded, path} -> {loaded, path, nil}
        {:error, error, defaults, path} -> {defaults, path, inspect(error)}
      end

    Enum.each(config["nodes"], &Discovery.apply_cookie/1)
    _ = :net_kernel.monitor_nodes(true, @node_monitor_opts)

    state = %{
      config: config,
      config_path: config_path,
      config_error: config_error,
      procfs: nil,
      snapshot: nil,
      history: [],
      learned: [],
      panel_open: false,
      originals: %{},
      probes: %{},
      events: [],
      poll_timer: nil,
      last_deep_ms: 0,
      scheduler_samples: %{},
      walltime_originals: %{},
      restart_events: %{}
    }

    {:ok, schedule_poll(state, 0)}
  end

  @impl true
  def handle_info(:poll, state) do
    state = %{state | poll_timer: nil}
    {snapshot, next} = collect(state)
    emit(snapshot)
    {:noreply, schedule_poll(next, next.config["poll_interval_ms"])}
  end

  def handle_info({:beam_deck_event, node, kind, who, info, at}, state) do
    event = %{node: to_string(node), kind: to_string(kind), subject: who, info: info, at_ms: at}
    emit(%{type: "event", event: event})
    {:noreply, %{state | events: Enum.take([event | state.events], 200)}}
  end

  def handle_info({:beam_deck_probe, node, status, detail}, state) do
    emit(%{
      type: "probe",
      node: to_string(node),
      status: to_string(status),
      detail: inspect(detail)
    })

    {:noreply, state}
  end

  def handle_info({:nodeup, node, info}, state) do
    next = push_runtime_event(state, node, "nodeup", info)
    {:noreply, reschedule_now(next)}
  end

  def handle_info({:nodedown, node, info}, state) do
    next = push_runtime_event(state, node, "nodedown", info)
    {:noreply, reschedule_now(next)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_cast({:protocol_error, reason}, state) do
    emit(%{type: "error", error: "protocol", reason: inspect(reason)})
    {:noreply, state}
  end

  def handle_cast({:command, "refresh", _args}, state) do
    {:noreply, reschedule_now(state)}
  end

  def handle_cast({:command, "panel", %{"open" => true}}, state) do
    {:noreply,
     state |> Map.put(:panel_open, true) |> Map.put(:last_deep_ms, 0) |> reschedule_now()}
  end

  def handle_cast({:command, "panel", %{"open" => false}}, state) do
    next =
      state
      |> stop_all_probes()
      |> restore_walltime()
      |> Map.put(:panel_open, false)
      |> Map.put(:scheduler_samples, %{})
      |> reschedule_now()

    {:noreply, next}
  end

  def handle_cast({:command, "set_schedulers", %{"node" => name, "value" => value}}, state),
    do: mutate_scheduler(state, name, :schedulers_online, value)

  def handle_cast({:command, "set_dirty_schedulers", %{"node" => name, "value" => value}}, state),
    do: mutate_scheduler(state, name, :dirty_cpu_schedulers_online, value)

  def handle_cast({:command, "restore", %{"node" => name}}, state), do: restore(state, name)

  def handle_cast({:command, "deep_events", %{"node" => name, "enabled" => enabled}}, state),
    do: deep_events(state, name, enabled)

  def handle_cast({:command, "gc", %{"node" => name, "pid" => pid}}, state) do
    result = with {:ok, node} <- node_atom(name), do: Remote.trigger_gc(node, pid)
    emit_action("gc", name, result)
    {:noreply, state}
  end

  def handle_cast({:command, other, _args}, state) do
    emit(%{type: "error", error: "unknown_command", command: other})
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    restore_runtime_mutations(state)
    stop_all_probes(state)
    restore_walltime(state)
    _ = :net_kernel.monitor_nodes(false, @node_monitor_opts)
    :ok
  end

  defp collect(state) do
    host = Procfs.snapshot("/proc", state.procfs)
    candidates = Discovery.candidates(state.config, state.learned)
    state = ensure_walltime(state, candidates)
    now_mono = System.monotonic_time(:millisecond)
    deep_due = deep_due?(state, now_mono)
    previous_nodes = previous_nodes(state)

    {nodes, scheduler_samples} =
      inspect_candidates(candidates, state, previous_nodes, deep_due)

    learned = nodes |> Enum.flat_map(&(&1[:peers] || [])) |> Enum.uniq()
    at_ms = System.system_time(:millisecond)

    {restart_events, nodes} =
      RestartChurn.update(
        state.restart_events,
        nodes,
        Map.values(previous_nodes),
        at_ms,
        deep_due
      )

    host = correlate_runtimes(host, nodes)
    current = build_snapshot(state, host, nodes, at_ms)
    current = add_derived_snapshot_fields(current, state, host, nodes)
    history = History.push(state.history, history_sample(current), state.config["history_points"])
    current = Map.put(current, :history, History.present(history, 120))

    next_state =
      next_collection_state(state, %{
        host: host,
        current: current,
        history: history,
        learned: learned,
        scheduler_samples: scheduler_samples,
        restart_events: restart_events,
        last_deep_ms: next_deep_ms(deep_due, now_mono, state.last_deep_ms)
      })

    {current, next_state}
  end

  defp deep_due?(%{panel_open: false}, _now_mono), do: false

  defp deep_due?(state, now_mono) do
    state.last_deep_ms == 0 or now_mono - state.last_deep_ms >= state.config["deep_interval_ms"]
  end

  defp previous_nodes(state) do
    Map.new((state.snapshot && state.snapshot.nodes) || [], &{&1.name, &1})
  end

  defp inspect_candidates(candidates, state, previous_nodes, deep_due) do
    Enum.map_reduce(candidates, state.scheduler_samples, fn node, samples ->
      inspect_candidate(node, samples, state, previous_nodes, deep_due)
    end)
  end

  defp inspect_candidate(node, samples, state, previous_nodes, deep_due) do
    options = [
      processes: deep_due,
      max_process_scan: state.config["max_process_scan"],
      scheduler_wall_time: state.panel_open
    ]

    case Remote.inspect_node(node, options) do
      {:ok, info} ->
        prepare_attached_info(node, info, samples, state, previous_nodes, deep_due)

      {:error, reason} ->
        {unattached_info(node, reason, state.config), samples}
    end
  end

  defp prepare_attached_info(node, info, samples, state, previous_nodes, deep_due) do
    node_name = to_string(node)
    previous = previous_nodes[node_name]
    current_sample = info[:scheduler_wall_time_sample] || []
    prior_sample = samples[node_name] || []
    utilization = Remote.scheduler_utilization(current_sample, prior_sample)

    info =
      info
      |> Map.merge(Discovery.metadata(state.config, node))
      |> Map.delete(:scheduler_wall_time_sample)
      |> Map.put(:scheduler_utilization, utilization)
      |> Map.put(:deep_events_active, Map.has_key?(state.probes, node_name))
      |> preserve_process_sample(previous, deep_due)

    {info, remember_scheduler_sample(samples, node_name, current_sample)}
  end

  defp remember_scheduler_sample(samples, _node_name, []), do: samples

  defp remember_scheduler_sample(samples, node_name, sample),
    do: Map.put(samples, node_name, sample)

  defp unattached_info(node, reason, config) do
    %{
      name: to_string(node),
      attached: false,
      local: Discovery.local_node?(node),
      error: inspect(reason),
      hot_processes: [],
      peers: [],
      deep_events_active: false
    }
    |> Map.merge(Discovery.metadata(config, node))
  end

  defp build_snapshot(state, host, nodes, at_ms) do
    %{
      type: "snapshot",
      protocol: 1,
      at_ms: at_ms,
      onboarding: onboarding(host, nodes),
      host: Map.drop(host, [:host_ticks, :monotonic_ms]),
      nodes: nodes,
      topology: topology(nodes),
      events: Enum.take(state.events, 30),
      config_path: state.config_path,
      config_error: state.config_error
    }
  end

  defp add_derived_snapshot_fields(current, state, host, nodes) do
    alerts = Alerts.derive(current, state.snapshot, state.config)

    current
    |> Map.put(:alerts, alerts)
    |> Map.put(:summary, summary(host, nodes, alerts))
    |> Map.put(:budget, Budget.recommend(nodes, host.logical_cpus))
  end

  defp next_collection_state(state, collection) do
    %{
      state
      | procfs: collection.host,
        snapshot: collection.current,
        history: collection.history,
        learned: collection.learned,
        scheduler_samples: collection.scheduler_samples,
        restart_events: collection.restart_events,
        last_deep_ms: collection.last_deep_ms
    }
  end

  defp next_deep_ms(true, now_mono, _previous), do: now_mono
  defp next_deep_ms(false, _now_mono, previous), do: previous

  defp preserve_process_sample(info, _previous, true), do: info
  defp preserve_process_sample(info, nil, false), do: info

  defp preserve_process_sample(info, previous, false) do
    info
    |> Map.put(:hot_processes, previous[:hot_processes] || [])
    |> Map.put(:registered_processes, previous[:registered_processes] || [])
    |> Map.put(:hot_processes_at_ms, previous[:hot_processes_at_ms])
    |> copy_if_present(previous, :process_scan_error)
  end

  defp copy_if_present(map, source, key) do
    if Map.has_key?(source, key), do: Map.put(map, key, source[key]), else: map
  end

  defp onboarding(host, nodes) do
    attached = Enum.count(nodes, & &1[:attached])

    cond do
      host.runtimes == [] ->
        %{state: "no_runtimes", message: "BEAM is installed, but no workload VMs are running."}

      attached == 0 ->
        %{
          state: "os_only",
          message: "BEAM VMs are running, but none are attachable distributed nodes yet.",
          launch_example: "iex --sname my_app -S mix phx.server"
        }

      true ->
        %{state: "ready"}
    end
  end

  defp summary(host, nodes, alerts) do
    attached = Enum.filter(nodes, & &1[:attached])
    local = Enum.filter(attached, & &1[:local])
    schedulers = Enum.reduce(local, 0, &((&1[:schedulers_online] || 0) + &2))

    %{
      runtime_count: length(host.runtimes),
      distributed_count: length(nodes),
      attached_count: length(attached),
      local_attached_count: length(local),
      warning_count: Enum.count(alerts, &(&1.severity == "warning")),
      critical_count: Enum.count(alerts, &(&1.severity == "critical")),
      schedulers_online: schedulers,
      logical_cpus: host.logical_cpus,
      beam_rss_bytes: Enum.sum(Enum.map(host.runtimes, & &1.rss_bytes)),
      process_count: Enum.sum(Enum.map(local, &(&1[:processes] || 0)))
    }
  end

  defp topology(nodes) do
    Enum.map(nodes, fn node ->
      sees = node[:peers] || []
      expected = node[:expected_peers] || []

      %{
        node: node.name,
        sees: sees,
        expected: expected,
        missing: expected -- sees,
        attached: node.attached,
        local: node[:local] || false
      }
    end)
  end

  defp correlate_runtimes(host, nodes) do
    local_by_pid =
      nodes
      |> Enum.filter(&(&1[:attached] && &1[:local] && is_integer(&1[:os_pid]) && &1[:os_pid] > 0))
      |> Map.new(&{&1.os_pid, &1.name})

    runtimes =
      Enum.map(host.runtimes, fn runtime ->
        case local_by_pid[runtime.pid] do
          nil -> runtime
          node_name -> runtime |> Map.put(:os_only, false) |> Map.put(:node_name, node_name)
        end
      end)

    %{host | runtimes: runtimes}
  end

  defp history_sample(snapshot) do
    %{
      at_ms: snapshot.at_ms,
      schedulers_online: snapshot.summary.schedulers_online,
      process_count: snapshot.summary.process_count,
      beam_rss_bytes: snapshot.summary.beam_rss_bytes,
      nodes:
        Enum.map(snapshot.nodes, fn node ->
          %{
            name: node.name,
            run_queue: node[:run_queue] || 0,
            processes: node[:processes] || 0,
            atoms: node[:atoms] || 0
          }
        end)
    }
  end

  defp ensure_walltime(%{panel_open: false} = state, _candidates), do: state

  defp ensure_walltime(state, candidates) do
    originals =
      Enum.reduce(candidates, state.walltime_originals, fn node, acc ->
        ensure_walltime_for_node(node, acc)
      end)

    %{state | walltime_originals: originals}
  end

  defp ensure_walltime_for_node(node, originals) do
    name = to_string(node)

    case Map.fetch(originals, name) do
      {:ok, _old} -> originals
      :error -> maybe_enable_walltime(node, name, originals)
    end
  end

  defp maybe_enable_walltime(node, name, originals) do
    with :ok <- Remote.connect(node),
         {:ok, old} <- Remote.set_scheduler_wall_time(node, true) do
      Map.put(originals, name, old)
    else
      _ -> originals
    end
  end

  defp restore_walltime(state) do
    Enum.each(state.walltime_originals, &restore_walltime_entry/1)
    %{state | walltime_originals: %{}}
  end

  defp restore_walltime_entry({_name, true}), do: :ok

  defp restore_walltime_entry({name, false}) do
    with {:ok, node} <- node_atom(name) do
      Remote.set_scheduler_wall_time(node, false)
    end
  end

  defp mutate_scheduler(state, name, flag, value) when is_integer(value) and value > 0 do
    with {:ok, node} <- node_atom(name),
         {:ok, old} <- Remote.set_flag(node, flag, value) do
      original = Map.get(state.originals, name, %{}) |> Map.put_new(flag, old)
      emit_action("set_#{flag}", name, {:ok, old})

      {:noreply,
       %{state | originals: Map.put(state.originals, name, original)} |> reschedule_now()}
    else
      error ->
        emit_action("set_#{flag}", name, error)
        {:noreply, state}
    end
  end

  defp mutate_scheduler(state, name, flag, _value) do
    emit_action("set_#{flag}", name, {:error, :invalid_value})
    {:noreply, state}
  end

  defp restore(state, name) do
    values = state.originals[name] || %{}

    result =
      with {:ok, node} <- node_atom(name) do
        Enum.map(values, fn {flag, value} -> {flag, Remote.set_flag(node, flag, value)} end)
      end

    emit_action("restore", name, result)
    {:noreply, %{state | originals: Map.delete(state.originals, name)} |> reschedule_now()}
  end

  defp restore_runtime_mutations(state) do
    Enum.each(state.originals, fn {name, values} -> restore_node_mutations(name, values) end)
  end

  defp restore_node_mutations(name, values) do
    with {:ok, node} <- node_atom(name) do
      restore_flag(node, :schedulers_online, values[:schedulers_online])
      restore_flag(node, :dirty_cpu_schedulers_online, values[:dirty_cpu_schedulers_online])
    end
  end

  defp restore_flag(_node, _flag, nil), do: :ok
  defp restore_flag(node, flag, value), do: Remote.set_flag(node, flag, value)

  defp deep_events(state, name, true) do
    if state.probes[name] do
      {:noreply, state}
    else
      with {:ok, node} <- node_atom(name),
           {:ok, pid} <- DeepEvents.start(node, state.config["event_thresholds"]) do
        emit_action("deep_events", name, :ok)
        {:noreply, %{state | probes: Map.put(state.probes, name, pid)} |> reschedule_now()}
      else
        error ->
          emit_action("deep_events", name, error)
          {:noreply, state}
      end
    end
  end

  defp deep_events(state, name, false) do
    case Map.pop(state.probes, name) do
      {nil, _probes} ->
        {:noreply, state}

      {pid, probes} ->
        with {:ok, node} <- node_atom(name), do: DeepEvents.stop(node, pid)
        emit_action("deep_events_off", name, :ok)
        {:noreply, %{state | probes: probes} |> reschedule_now()}
    end
  end

  defp stop_all_probes(state) do
    Enum.each(state.probes, fn {name, pid} ->
      with {:ok, node} <- node_atom(name), do: DeepEvents.stop(node, pid)
    end)

    %{state | probes: %{}}
  end

  defp push_runtime_event(state, node, kind, info) do
    event = %{
      node: to_string(node),
      kind: kind,
      subject: to_string(node),
      info: info,
      at_ms: System.system_time(:millisecond)
    }

    emit(%{type: "event", event: event})
    %{state | events: Enum.take([event | state.events], 200)}
  end

  defp reschedule_now(state) do
    if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
    schedule_poll(%{state | poll_timer: nil}, 0)
  end

  defp schedule_poll(state, delay) do
    %{state | poll_timer: Process.send_after(self(), :poll, delay)}
  end

  defp node_atom(name) when is_binary(name) do
    if Regex.match?(~r/^[A-Za-z0-9_.-]+@[A-Za-z0-9_.:-]+$/, name),
      do: {:ok, String.to_atom(name)},
      else: {:error, :invalid_node}
  end

  defp emit_action(action, node, result),
    do: emit(%{type: "action", action: action, node: node, result: inspect(result)})

  defp emit(map), do: Output.puts(Json.encode(map))
end
