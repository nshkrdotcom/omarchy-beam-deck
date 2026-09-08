defmodule BeamDeck.Projection do
  import Kernel, except: [node: 1]

  @moduledoc "Allowlisted retained/exported operational metadata; unknown extensions never escape."
  def snapshot(s) do
    pick(
      s,
      ~w(type protocol at_ms session_id sample_mono_ms frame_id sequence omitted_incidents omitted_activity)a
    )
    |> Map.merge(%{
      summary:
        pick(
          s[:summary],
          ~w(beam_rss_bytes process_count schedulers_online runtime_count attached_count warning_count critical_count)a
        ),
      collection:
        pick(s[:collection], ~w(status duration_ms poll_interval_ms deep_interval_ms deep)a),
      host: host(s[:host]),
      nodes: rows(s[:nodes], &node/1, 64),
      alerts: rows(s[:alerts], &alert/1, 100),
      forecasts: rows(s[:forecasts], &forecast/1, 100),
      incidents: incidents(s[:incidents]),
      events: events(s[:events]),
      new_events: events(s[:new_events]),
      activity: activity(s[:activity]),
      watchlist: %{entries: rows(get_in(s, [:watchlist, :entries]), &watch/1, 64)},
      budget: rows(s[:budget], &pick(&1, ~w(node current suggested)a), 16),
      budget_trial: trial(s[:budget_trial])
    })
  end

  def node(n) do
    pick(
      n,
      ~w(name attached local required error otp erts elixir os_pid creation uptime_ms processes process_limit atoms atom_limit ports port_limit ets ets_limit schedulers schedulers_online dirty_cpu_schedulers dirty_cpu_schedulers_online run_queue hot_processes_at_ms process_scan_error observer_backend deep_events_capable deep_events_active)a
    )
    |> Map.merge(%{
      memory: memory(n[:memory]),
      capabilities:
        pick(
          n[:capabilities],
          ~w(process_inspect process_binary_info supervisor_focus ets_inspect scheduler_wall_time deep_events)a
        ),
      process_scan: pick(n[:process_scan], ~w(status scanned reported limit returned)a),
      hot_processes: rows(n[:hot_processes], &process/1, 24),
      registered_processes: rows(n[:registered_processes], &pick(&1, [:name, :pid]), 128),
      scheduler_utilization:
        rows(n[:scheduler_utilization], &pick(&1, [:id, :kind, :utilization]), 256),
      restart_churn: rows(n[:restart_churn], &pick(&1, [:name, :pid, :count]), 32),
      peers: Enum.take(n[:peers] || [], 64),
      expected_peers: Enum.take(n[:expected_peers] || [], 64)
    })
  end

  def incidents(values), do: rows(values, &incident/1, 100)

  def events(values),
    do: rows(values, &pick(&1, ~w(id node kind subject at_ms target_at_ms)a), 200)

  def activity(values),
    do:
      rows(
        values,
        &pick(
          &1,
          ~w(id node kind domain name subject creation summary changed_fields evidence_class frame_id sequence at_ms captured_at_ms)a
        ),
        200
      )

  def crashes(values),
    do:
      rows(
        values,
        &pick(
          &1,
          ~w(id node pid starttime status at_ms last_frame_id slogan system_version dump_timestamp bytes_read partial)a
        ),
        256
      )

  defp host(s) do
    %{
      logical_cpus: get(s, :logical_cpus),
      memory: pick(get(s, :memory), ~w(total_bytes available_bytes used_bytes)a),
      runtimes:
        rows(
          get(s, :runtimes),
          &pick(&1, ~w(pid starttime rss_bytes cpu_percent os_only node_name state)a),
          64
        )
    }
  end

  defp memory(m),
    do: pick(m, ~w(total processes processes_used system atom atom_used binary code ets)a)

  defp process(p),
    do: pick(p, ~w(pid name identity_kind memory_bytes mailbox reductions current_function)a)

  defp alert(a), do: pick(a, ~w(id node process severity title message count missing)a)

  defp forecast(f),
    do:
      pick(
        f,
        ~w(node metric kind severity summary current limit eta_ms confidence rate_per_second span_ms sample_count)a
      )

  defp incident(i) do
    pick(
      i,
      ~w(id family node subject severity status title summary evidence_class first_seen_ms last_seen_ms resolved_at_ms creation)a
    )
    |> Map.put(:evidence, rows(i[:evidence], &evidence/1, 12))
    |> Map.put(
      :actions,
      rows(i[:actions], &pick(&1, ~w(kind label node name pid frame_id trial_id)a), 8)
    )
  end

  defp evidence(e) do
    pick(
      e,
      ~w(class kind text summary at_ms subject ref frame_id metric eta_ms confidence rate_per_second current limit window_ms sample_count count status)a
    )
    |> Map.merge(%{
      processes: rows(e[:processes], &process/1, 3),
      schedulers: rows(e[:schedulers], &pick(&1, [:id, :kind, :utilization]), 256),
      failures: rows(e[:failures], &pick(&1, ~w(node flag error original applied)a), 32),
      header: pick(e[:header], ~w(slogan system_version dump_timestamp)a)
    })
  end

  defp watch(w) do
    pick(
      w,
      ~w(id kind node name label status pid creation stale mailbox memory_bytes observed_at_ms last_seen_ms at_ms error)a
    )
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp trial(nil), do: nil

  defp trial(t) do
    pick(t, ~w(trial_id status reason started_at_ms expires_at_ms remaining_ms)a)
    |> Map.merge(%{
      rows: rows(t[:rows], &pick(&1, ~w(node current suggested)a), 16),
      failures: rows(t[:failures], &pick(&1, ~w(node flag error original applied)a), 32),
      before_metrics: rows(t[:before_metrics], &node/1, 16)
    })
  end

  defp rows(values, fun, cap) when is_list(values), do: values |> Enum.take(cap) |> Enum.map(fun)
  defp rows(_, _, _), do: []
  defp pick(m, keys) when is_map(m), do: Map.new(keys, &{&1, scalar(get(m, &1))})
  defp pick(_, _), do: %{}
  defp scalar(v) when is_number(v) or is_atom(v) or is_binary(v), do: v
  defp scalar(v) when is_list(v), do: v |> Enum.take(64) |> Enum.map(&scalar/1)
  defp scalar(_), do: nil
  defp get(m, k) when is_map(m), do: Map.get(m, k, Map.get(m, Atom.to_string(k)))
  defp get(_, _), do: nil
end
