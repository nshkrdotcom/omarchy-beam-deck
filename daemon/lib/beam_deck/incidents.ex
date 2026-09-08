defmodule BeamDeck.Incidents do
  @moduledoc "Evidence-backed condition grouping, temporal association and capped lifecycle."
  @rank %{"critical" => 0, "warning" => 1, "info" => 2}
  def update(previous, snapshot, config, recorder \\ nil) do
    now = snapshot.at_ms

    conditions =
      (alert_conditions(snapshot, recorder) ++
         watch_conditions(snapshot, config) ++
         Enum.map(snapshot[:forecasts] || [], &from_forecast/1) ++
         crash_conditions(snapshot) ++ trial_conditions(snapshot))
      |> Enum.map(&Map.put(&1, :at_ms, now))
      |> Enum.group_by(& &1.id)
      |> Enum.map(fn {_id, group} -> merge(group) end)

    old = Map.new(previous, &{&1.id, &1})

    active =
      Enum.map(conditions, fn item ->
        before = old[item.id]

        Map.merge(item, %{
          status: "active",
          first_seen_ms: if(before, do: before.first_seen_ms, else: now),
          last_seen_ms: observation_time(item, snapshot),
          last_checked_ms: now,
          resolved_at_ms: nil,
          quiet_polls: 0
        })
      end)

    ids = Enum.map(active, & &1.id)

    quiet =
      previous
      |> Enum.reject(&(&1.id in ids))
      |> Enum.map(&quiet_incident(&1, snapshot, now))
      |> Enum.filter(
        &(is_nil(&1.resolved_at_ms) or now - &1.resolved_at_ms <= config["incident_retention_ms"])
      )

    (active ++ quiet)
    |> Enum.sort_by(
      &{if(&1.status == "active", do: 0, else: 1), @rank[&1.severity] || 2, -&1.last_seen_ms}
    )
    |> Enum.take(100)
  end

  defp observation_time(item, snapshot) do
    node = Enum.find(snapshot[:nodes] || [], &(&1.name == item.node)) || %{}

    if item.family in ["mailbox", "restart"] and is_integer(node[:hot_processes_at_ms]),
      do: min(snapshot.at_ms, node.hot_processes_at_ms),
      else: snapshot.at_ms
  end

  defp quiet_incident(item, snapshot, now) do
    unknown = unavailable_evidence?(item, snapshot)

    if not unknown and now <= (item[:last_checked_ms] || item.last_seen_ms),
      do: item,
      else: update_quiet(item, unknown, now)
  end

  defp update_quiet(item, unknown, now) do
    misses = if unknown, do: 0, else: item.quiet_polls + 1
    resolved = misses >= 2

    status =
      cond do
        unknown -> "unknown"
        resolved -> "resolved"
        true -> "active"
      end

    Map.merge(item, %{
      quiet_polls: misses,
      status: status,
      last_checked_ms: now,
      resolved_at_ms: if(resolved, do: item.resolved_at_ms || now, else: nil)
    })
  end

  defp unavailable_evidence?(%{status: "resolved"}, _snapshot), do: false

  defp unavailable_evidence?(item, snapshot) do
    case Enum.find(snapshot[:nodes] || [], &(&1.name == item.node)) do
      %{attached: false} ->
        item.family not in ["runtime_exit", "watch", "budget"]

      node when is_map(node) ->
        unavailable_metric?(item.family, node)

      _ ->
        is_binary(item.node) and item.node != "host" and
          item.family not in ["runtime_exit", "watch", "budget"]
    end
  end

  defp unavailable_metric?(family, node) when family in ["mailbox", "restart"],
    do: !!node[:process_scan_error] or not is_integer(node[:hot_processes_at_ms])

  defp unavailable_metric?("runq", node), do: not is_number(node[:run_queue])

  defp unavailable_metric?("resource", node),
    do:
      not is_number(node[:processes]) or not is_number(node[:atoms]) or
        not is_number(node[:ports])

  defp unavailable_metric?(_, _), do: false

  defp alert_conditions(snapshot, recorder) do
    Enum.flat_map(snapshot[:alerts] || [], &alert_condition_rows(&1, snapshot, recorder))
  end

  defp alert_condition_rows(alert, snapshot, recorder) do
    case alert[:missing] do
      missing when is_list(missing) and missing != [] ->
        Enum.map(missing, fn peer ->
          alert
          |> Map.put(:missing_peer, peer)
          |> Map.put(
            :message,
            "Expected peer #{peer} is not visible from #{alert.node}; this is a configured directional contract."
          )
          |> from_alert(snapshot, recorder)
        end)

      _ ->
        [from_alert(alert, snapshot, recorder)]
    end
  end

  defp watch_conditions(snapshot, config) do
    entries = get_in(snapshot, [:watchlist, :entries]) || []
    Enum.flat_map(entries, &watch_condition(&1, snapshot, config))
  end

  defp watch_condition(pin, snapshot, config) do
    status = pin["status"]
    mailbox = pin["mailbox"] || 0

    cond do
      status == "present" and mailbox >= config["mailbox_warn"] ->
        [watched_mailbox_condition(pin, mailbox, snapshot, config)]

      status in ["missing", "node_unavailable"] ->
        [unavailable_watch_condition(pin, status)]

      true ->
        []
    end
  end

  defp watched_mailbox_condition(pin, mailbox, snapshot, config) do
    severity = if mailbox >= config["mailbox_critical"], do: "critical", else: "warning"

    from_alert(
      %{
        id: "#{pin["node"]}.#{pin["pid"]}.mailbox",
        node: pin["node"],
        process: pin["pid"],
        title: "Watched mailbox pressure",
        message: "#{pin["label"]} has #{mailbox} queued messages.",
        severity: severity
      },
      snapshot
    )
  end

  defp unavailable_watch_condition(pin, status) do
    %{
      id: "watch:#{pin["id"]}",
      family: "watch",
      node: pin["node"],
      subject: nil,
      title: "Watched identity unavailable",
      summary: "#{pin["label"]}: #{status}. A stop or restart may be intentional.",
      severity: "warning",
      evidence_class: "observed",
      evidence: [%{class: "observed", text: "Targeted registered-name lookup: #{status}"}],
      actions: actions(pin["node"], nil, "watch")
    }
  end

  defp from_alert(alert, snapshot, recorder \\ nil) do
    node = alert[:node] || "host"
    {family, metric} = alert_family(alert)
    candidate = Enum.find(snapshot[:nodes] || [], &(&1.name == node))
    registered = registered_restart(alert, node, family, candidate)
    subject = resolved_subject(alert[:process], registered)
    related = related_events(snapshot, node, subject, family)
    evidence = alert_evidence(alert, snapshot, related)
    evidence = add_registered_evidence(evidence, alert, snapshot, registered)
    evidence = add_scheduler_evidence(evidence, snapshot, family, candidate)
    nearest = nearest_deep_frame(recorder, node, snapshot, candidate)
    {sampled, hot} = sampled_hot_processes(nearest, candidate, snapshot, family, subject)
    evidence = add_hot_evidence(evidence, family, hot, sampled, nearest)

    %{
      id: "#{family}:#{node}:#{metric}",
      family: family,
      node: node,
      subject: subject,
      title: alert.title,
      summary: alert.message,
      severity: alert.severity,
      evidence_class: if(related == [], do: "observed", else: "correlated"),
      evidence: evidence,
      actions:
        enriched_actions(node, subject, family, candidate, hot, registered) ++
          frame_action(nearest)
    }
  end

  defp alert_family(alert) do
    resource_family(alert.id) || non_resource_alert_family(alert)
  end

  defp resource_family(id) do
    cond do
      String.ends_with?(id, ".process_limit") -> {"resource", "processes"}
      String.ends_with?(id, ".atom_limit") -> {"resource", "atoms"}
      String.ends_with?(id, ".port_limit") -> {"resource", "ports"}
      true -> nil
    end
  end

  defp non_resource_alert_family(alert) do
    cond do
      String.contains?(alert.id, ".mailbox") ->
        {"mailbox", alert[:process] || "node"}

      String.contains?(alert.id, ".run_queue") ->
        {"runq", "node"}

      String.contains?(alert.id, ".restart_churn.") ->
        {"restart", alert.id}

      String.contains?(alert.id, ".expected_peers") ->
        {"link", alert[:missing_peer] || "expected"}

      true ->
        {"condition", alert.id}
    end
  end

  defp registered_restart(_alert, _node, family, _candidate) when family != "restart", do: nil
  defp registered_restart(_alert, _node, _family, nil), do: nil

  defp registered_restart(alert, node, "restart", candidate) do
    name = String.replace_prefix(alert.id, "#{node}.restart_churn.", "")
    Enum.find(candidate[:registered_processes] || [], &(&1.name == name))
  end

  defp resolved_subject(subject, nil), do: subject
  defp resolved_subject(_subject, registered), do: registered.pid

  defp related_events(snapshot, node, subject, family) do
    (snapshot[:events] || [])
    |> Enum.filter(&related_event?(&1, snapshot.at_ms, node, subject, family))
    |> Enum.take(6)
  end

  defp related_event?(event, at_ms, node, subject, family) do
    event[:node] == node and event[:at_ms] >= at_ms - 15_000 and event[:at_ms] <= at_ms and
      related_subject?(event, subject, family) and related_kind?(event[:kind])
  end

  defp related_subject?(_event, nil, _family), do: true
  defp related_subject?(_event, _subject, "restart"), do: true
  defp related_subject?(event, subject, _family), do: event[:subject] == subject

  defp related_kind?(kind) do
    kind in [
      "long_gc",
      "long_schedule",
      "long_message_queue",
      "busy_dist_port",
      "nodedown",
      "nodeup"
    ]
  end

  defp alert_evidence(alert, snapshot, related) do
    [%{class: "observed", at_ms: snapshot.at_ms, text: alert.message}] ++
      Enum.map(
        related,
        &%{
          class: "correlated",
          at_ms: &1.at_ms,
          text: "Nearby #{&1.kind}; temporal association, not proven cause."
        }
      )
  end

  defp add_registered_evidence(evidence, _alert, _snapshot, nil), do: evidence

  defp add_registered_evidence(evidence, alert, snapshot, registered) do
    evidence ++
      [
        %{
          class: "observed",
          at_ms: snapshot.at_ms,
          text:
            "Registered name now resolves to #{registered.pid}; replacements are sampled, not Supervisor intensity.",
          count: alert[:count],
          window_ms: 30_000,
          subject: registered.pid
        }
      ]
  end

  defp add_scheduler_evidence(evidence, _snapshot, family, _candidate) when family != "runq",
    do: evidence

  defp add_scheduler_evidence(evidence, _snapshot, "runq", nil), do: evidence

  defp add_scheduler_evidence(evidence, _snapshot, "runq", candidate) do
    case candidate[:scheduler_utilization] || [] do
      [] ->
        evidence

      schedulers ->
        evidence ++
          [
            %{
              class: "correlated",
              at_ms: candidate[:hot_processes_at_ms],
              text: "Nearby scheduler utilization sample",
              schedulers: Enum.take(schedulers, 256)
            }
          ]
    end
  end

  defp nearest_deep_frame(recorder, node, snapshot, candidate) do
    case BeamDeck.FlightRecorder.nearest_deep(
           recorder,
           node,
           snapshot.at_ms,
           10_000,
           candidate_creation(candidate)
         ) do
      {:ok, frame} -> frame
      _ -> nil
    end
  end

  defp candidate_creation(nil), do: nil
  defp candidate_creation(candidate), do: candidate[:creation]

  defp sampled_hot_processes(nearest, candidate, snapshot, family, subject) do
    sampled = if nearest, do: nearest.node, else: candidate
    hot = recent_hot_processes(sampled, snapshot.at_ms)
    hot = if family == "mailbox", do: Enum.filter(hot, &(&1.pid == subject)), else: hot
    {sampled, Enum.take(hot, 3)}
  end

  defp recent_hot_processes(nil, _at_ms), do: []

  defp recent_hot_processes(sampled, at_ms) do
    if is_integer(sampled[:hot_processes_at_ms]) and
         abs(at_ms - sampled.hot_processes_at_ms) <= 10_000,
       do: sampled[:hot_processes] || [],
       else: []
  end

  defp add_hot_evidence(evidence, family, hot, sampled, nearest)
       when family in ["runq", "mailbox"] and hot != [] do
    evidence ++
      [
        %{
          class: "correlated",
          text: "Nearby sampled hot processes",
          processes: hot,
          at_ms: sampled[:hot_processes_at_ms],
          frame_id: nearest && nearest.frame_id
        }
      ]
  end

  defp add_hot_evidence(evidence, _family, _hot, _sampled, _nearest), do: evidence

  defp frame_action(nil), do: []
  defp frame_action(frame), do: [%{kind: "view_frame", frame_id: frame.frame_id}]

  defp from_forecast(f) do
    %{
      id: "resource:#{f.node}:#{f.metric}",
      family: "resource",
      node: f.node,
      subject: nil,
      title: if(f.kind == "capacity", do: "Capacity trend", else: "Sustained resource growth"),
      summary: f.summary,
      severity: f.severity,
      evidence_class: "heuristic",
      evidence: [
        %{
          class: "heuristic",
          text: f.summary,
          metric: f.metric,
          eta_ms: f.eta_ms,
          confidence: f.confidence,
          rate_per_second: f.rate_per_second,
          current: f.current,
          limit: f.limit,
          window_ms: f.span_ms,
          sample_count: f.sample_count
        }
      ],
      actions: actions(f.node, nil, "resource")
    }
  end

  defp crash_conditions(snapshot) do
    for crash <- snapshot[:crash_triage] || [], snapshot.at_ms - crash.at_ms <= 60_000 do
      crash_condition(crash, snapshot)
    end
  end

  defp crash_condition(crash, snapshot) do
    matched = crash[:status] == "matched"

    %{
      id: "exit:#{crash.id}",
      family: "runtime_exit",
      node: crash[:node],
      subject: crash[:pid],
      title: crash_title(matched),
      summary: crash_summary(crash, matched),
      severity: if(matched, do: "critical", else: "info"),
      evidence_class: "observed",
      evidence: crash_evidence(crash, snapshot),
      actions: crash_actions(crash)
    }
  end

  defp crash_title(true), do: "Runtime exit with crash-dump evidence"
  defp crash_title(false), do: "Local runtime disappeared"

  defp crash_summary(crash, true), do: crash[:slogan] || "Matched crash-dump header"

  defp crash_summary(_crash, false),
    do: "Observed OS process disappearance; normal shutdown is possible."

  defp crash_evidence(crash, snapshot) do
    [
      %{
        class: "observed",
        at_ms: crash.at_ms,
        status: crash[:status],
        text: "Local OS process identity disappeared.",
        frame_id: crash[:last_frame_id],
        header: Map.take(crash, [:slogan, :system_version, :dump_timestamp])
      }
    ] ++ nearby_node_down_evidence(crash, snapshot)
  end

  defp nearby_node_down_evidence(crash, snapshot) do
    (snapshot[:events] || [])
    |> Enum.filter(&nearby_node_down?(&1, crash))
    |> Enum.take(3)
    |> Enum.map(
      &%{
        class: "correlated",
        at_ms: &1.at_ms,
        text: "Nearby node-down event; crash cause is not inferred.",
        info: &1[:info]
      }
    )
  end

  defp nearby_node_down?(event, crash) do
    event[:kind] == "nodedown" and event[:node] == crash[:node] and
      abs(event.at_ms - crash.at_ms) <= 30_000
  end

  defp crash_actions(%{last_frame_id: frame_id}) when not is_nil(frame_id),
    do: [%{kind: "export_bundle"}, %{kind: "view_frame", frame_id: frame_id}]

  defp crash_actions(_crash), do: [%{kind: "export_bundle"}]

  defp trial_conditions(%{budget_trial: %{status: "rollback_failed"} = trial}) do
    [
      %{
        id: "budget:#{trial.trial_id}",
        family: "budget",
        node: nil,
        subject: nil,
        title: "Scheduler rollback needs attention",
        summary:
          "One or more original values are not restored. Retry Revert while the same VM is reachable.",
        severity: "critical",
        evidence_class: "observed",
        evidence: [%{class: "observed", failures: trial[:failures] || []}],
        actions: [%{kind: "budget_trial_revert", trial_id: trial.trial_id}]
      }
    ]
  end

  defp trial_conditions(_), do: []

  defp enriched_actions(node, subject, family, candidate, hot, registered) do
    list = actions(node, subject, family)

    list =
      if family == "runq",
        do:
          Enum.map(
            Enum.take(Enum.sort_by(hot, & &1.reductions, :desc), 2),
            &%{
              kind: "inspect_process",
              node: node,
              pid: &1.pid,
              label: "Inspect " <> BeamDeck.Redaction.text(&1.name, 40)
            }
          ) ++ list,
        else: list

    list =
      if (family == "runq" and candidate) && candidate[:local],
        do: [%{kind: "apply_budget_trial"} | list],
        else: list

    list =
      if registered,
        do: [%{kind: "pin_process", node: node, name: registered.name} | list],
        else: list

    if family == "mailbox" and is_binary(subject),
      do: [%{kind: "gc_process", node: node, pid: subject} | list],
      else: list
  end

  defp actions(node, pid, family) do
    base = [%{kind: "export_bundle"}]

    base =
      if node && node != "host",
        do: [%{kind: "remsh", node: node}, %{kind: "pin_node", node: node} | base],
        else: base

    base =
      if is_binary(pid), do: [%{kind: "inspect_process", node: node, pid: pid} | base], else: base

    if family == "resource", do: [%{kind: "inspect_ets", node: node} | base], else: base
  end

  defp merge(group) do
    sorted = Enum.sort_by(group, &(@rank[&1.severity] || 2))
    item = hd(sorted)

    %{
      item
      | title: BeamDeck.Redaction.text(item.title, 120),
        summary: BeamDeck.Redaction.text(item.summary, 512),
        evidence: merged_evidence(sorted, item),
        actions: Enum.flat_map(sorted, & &1.actions) |> Enum.uniq() |> Enum.take(8)
    }
  end

  defp merged_evidence(sorted, item) do
    sorted
    |> Enum.flat_map(& &1.evidence)
    |> Enum.uniq()
    |> Enum.take(12)
    |> Enum.map(&normalize_evidence(&1, item))
  end

  defp normalize_evidence(evidence, item) do
    Map.merge(
      %{
        kind: evidence_kind(evidence),
        at_ms: evidence[:at_ms] || item.at_ms,
        subject: evidence[:subject] || item.subject,
        summary: BeamDeck.Redaction.text(evidence[:text] || item.summary, 512),
        ref: evidence[:frame_id]
      },
      evidence
    )
  end

  defp evidence_kind(evidence) do
    cond do
      evidence[:class] == "heuristic" -> "forecast"
      Map.has_key?(evidence, :header) -> "crash_dump"
      recorder_evidence?(evidence) -> "recorder"
      evidence[:class] == "correlated" -> "deep_event"
      true -> "alert"
    end
  end

  defp recorder_evidence?(evidence) do
    Map.has_key?(evidence, :frame_id) or Map.has_key?(evidence, :processes) or
      Map.has_key?(evidence, :schedulers)
  end

  def notifications(current, previous, sent, now, config) do
    old = Map.new(previous, &{&1.id, &1})

    transitions =
      Enum.filter(current, fn item ->
        prior = old[item.id]

        item.status == "active" and item.severity == "critical" and
          (is_nil(prior) or prior.status != "active" or prior.severity != "critical") and
          (not Map.has_key?(sent, item.id) or
             now - sent[item.id] >= config["critical_notification_cooldown_ms"])
      end)

    messages =
      Enum.map(transitions, fn item ->
        %{
          type: "notification",
          id: item.id,
          urgency: "critical",
          title: "BEAM Deck needs attention",
          body:
            BeamDeck.Redaction.text(item.title, 120) <>
              ". Open BEAM Deck for evidence and safe next actions."
        }
      end)

    sent =
      Enum.reduce(transitions, sent, &Map.put(&2, &1.id, now))
      |> Enum.sort_by(fn {_id, at} -> at end, :desc)
      |> Enum.take(256)
      |> Map.new()

    {messages, sent}
  end
end
