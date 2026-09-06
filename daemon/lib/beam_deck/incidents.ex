defmodule BeamDeck.Incidents do
  @moduledoc "Evidence-backed condition grouping, temporal association and bounded lifecycle."
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
          last_seen_ms: now,
          resolved_at_ms: nil,
          quiet_polls: 0
        })
      end)

    ids = Enum.map(active, & &1.id)

    quiet =
      previous
      |> Enum.reject(&(&1.id in ids))
      |> Enum.map(fn item ->
        misses = item.quiet_polls + 1
        resolved = misses >= 2

        %{
          item
          | quiet_polls: misses,
            status: if(resolved, do: "resolved", else: "active"),
            resolved_at_ms: if(resolved, do: item.resolved_at_ms || now, else: nil)
        }
      end)
      |> Enum.filter(
        &(is_nil(&1.resolved_at_ms) or now - &1.resolved_at_ms <= config["incident_retention_ms"])
      )

    (active ++ quiet)
    |> Enum.sort_by(
      &{if(&1.status == "active", do: 0, else: 1), @rank[&1.severity] || 2, -&1.last_seen_ms}
    )
    |> Enum.take(100)
  end

  defp alert_conditions(snapshot, recorder) do
    Enum.flat_map(snapshot[:alerts] || [], fn alert ->
      if is_list(alert[:missing]) and alert.missing != [] do
        Enum.map(alert.missing, fn peer ->
          alert
          |> Map.put(:missing_peer, peer)
          |> Map.put(
            :message,
            "Expected peer #{peer} is not visible from #{alert.node}; this is a configured directional contract."
          )
          |> from_alert(snapshot, recorder)
        end)
      else
        [from_alert(alert, snapshot, recorder)]
      end
    end)
  end

  defp watch_conditions(snapshot, config) do
    entries = get_in(snapshot, [:watchlist, :entries]) || []

    Enum.flat_map(entries, fn pin ->
      status = pin["status"]
      mailbox = pin["mailbox"] || 0

      cond do
        status == "present" and mailbox >= config["mailbox_warn"] ->
          severity = if mailbox >= config["mailbox_critical"], do: "critical", else: "warning"

          [
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
          ]

        status in ["missing", "node_unavailable"] ->
          [
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
          ]

        true ->
          []
      end
    end)
  end

  defp from_alert(alert, snapshot, recorder \\ nil) do
    node = alert[:node] || "host"
    subject = alert[:process]

    {family, metric} =
      cond do
        String.ends_with?(alert.id, ".process_limit") ->
          {"resource", "processes"}

        String.ends_with?(alert.id, ".atom_limit") ->
          {"resource", "atoms"}

        String.ends_with?(alert.id, ".port_limit") ->
          {"resource", "ports"}

        String.contains?(alert.id, ".mailbox") ->
          {"mailbox", subject || "node"}

        String.contains?(alert.id, ".run_queue") ->
          {"runq", "node"}

        String.contains?(alert.id, ".restart_churn.") ->
          {"restart", alert.id}

        String.contains?(alert.id, ".expected_peers") ->
          {"link", alert[:missing_peer] || "expected"}

        true ->
          {"condition", alert.id}
      end

    candidate = Enum.find(snapshot[:nodes] || [], &(&1.name == node))

    registered =
      if family == "restart" and candidate do
        name = String.replace_prefix(alert.id, "#{node}.restart_churn.", "")
        Enum.find(candidate[:registered_processes] || [], &(&1.name == name))
      end

    subject = if registered, do: registered.pid, else: subject

    related =
      (snapshot[:events] || [])
      |> Enum.filter(fn event ->
        event[:node] == node and event[:at_ms] >= snapshot.at_ms - 15_000 and
          event[:at_ms] <= snapshot.at_ms and
          (is_nil(subject) or family == "restart" or event[:subject] == subject) and
          event[:kind] in [
            "long_gc",
            "long_schedule",
            "long_message_queue",
            "busy_dist_port",
            "nodedown",
            "nodeup"
          ]
      end)
      |> Enum.take(6)

    evidence =
      [%{class: "observed", at_ms: snapshot.at_ms, text: alert.message}] ++
        Enum.map(
          related,
          &%{
            class: "correlated",
            at_ms: &1.at_ms,
            text: "Nearby #{&1.kind}; temporal association, not proven cause."
          }
        )

    evidence =
      if registered,
        do:
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
            ],
        else: evidence

    evidence =
      if (family == "runq" and candidate) && (candidate[:scheduler_utilization] || []) != [],
        do:
          evidence ++
            [
              %{
                class: "correlated",
                at_ms: candidate[:hot_processes_at_ms],
                text: "Nearby scheduler utilization sample",
                schedulers: Enum.take(candidate[:scheduler_utilization] || [], 256)
              }
            ],
        else: evidence

    nearest =
      case BeamDeck.FlightRecorder.nearest_deep(
             recorder,
             node,
             snapshot.at_ms,
             10_000,
             candidate && candidate[:creation]
           ) do
        {:ok, frame} -> frame
        _ -> nil
      end

    sampled = if nearest, do: nearest.node, else: candidate

    hot =
      if sampled && is_integer(sampled[:hot_processes_at_ms]) &&
           abs(snapshot.at_ms - sampled.hot_processes_at_ms) <= 10_000,
         do: sampled[:hot_processes] || [],
         else: []

    hot = if family == "mailbox", do: Enum.filter(hot, &(&1.pid == subject)), else: hot
    hot = Enum.take(hot, 3)

    evidence =
      if family in ["runq", "mailbox"] and hot != [],
        do:
          evidence ++
            [
              %{
                class: "correlated",
                text: "Nearby sampled hot processes",
                processes: hot,
                at_ms: sampled[:hot_processes_at_ms],
                frame_id: nearest && nearest.frame_id
              }
            ],
        else: evidence

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
          if(nearest, do: [%{kind: "view_frame", frame_id: nearest.frame_id}], else: [])
    }
  end

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
    for c <- snapshot[:crash_triage] || [], snapshot.at_ms - c.at_ms <= 60_000 do
      matched = c[:status] == "matched"

      %{
        id: "exit:#{c.id}",
        family: "runtime_exit",
        node: c[:node],
        subject: c[:pid],
        title:
          if(matched,
            do: "Runtime exit with crash-dump evidence",
            else: "Local runtime disappeared"
          ),
        summary:
          if(matched,
            do: c[:slogan] || "Matched bounded crash-dump header",
            else: "Observed OS process disappearance; normal shutdown is possible."
          ),
        severity: if(matched, do: "critical", else: "info"),
        evidence_class: "observed",
        evidence:
          [
            %{
              class: "observed",
              at_ms: c.at_ms,
              status: c[:status],
              text: "Local OS process identity disappeared.",
              frame_id: c[:last_frame_id],
              header: Map.take(c, [:slogan, :system_version, :dump_timestamp])
            }
          ] ++
            Enum.map(
              Enum.filter(snapshot[:events] || [], fn e ->
                e[:kind] == "nodedown" and e[:node] == c[:node] and
                  abs(e.at_ms - c.at_ms) <= 30_000
              end)
              |> Enum.take(3),
              &%{
                class: "correlated",
                at_ms: &1.at_ms,
                text: "Nearby node-down event; crash cause is not inferred.",
                info: &1[:info]
              }
            ),
        actions:
          [%{kind: "export_bundle"}] ++
            if(c[:last_frame_id],
              do: [%{kind: "view_frame", frame_id: c.last_frame_id}],
              else: []
            )
      }
    end
  end

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
        evidence:
          Enum.flat_map(sorted, & &1.evidence)
          |> Enum.uniq()
          |> Enum.take(12)
          |> Enum.map(fn e ->
            kind =
              cond do
                e[:class] == "heuristic" ->
                  "forecast"

                Map.has_key?(e, :header) ->
                  "crash_dump"

                Map.has_key?(e, :frame_id) or Map.has_key?(e, :processes) or
                    Map.has_key?(e, :schedulers) ->
                  "recorder"

                e[:class] == "correlated" ->
                  "deep_event"

                true ->
                  "alert"
              end

            Map.merge(
              %{
                kind: kind,
                at_ms: e[:at_ms] || item.at_ms,
                subject: e[:subject] || item.subject,
                summary: BeamDeck.Redaction.text(e[:text] || item.summary, 512),
                ref: e[:frame_id]
              },
              e
            )
          end),
        actions: Enum.flat_map(sorted, & &1.actions) |> Enum.uniq() |> Enum.take(8)
    }
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
