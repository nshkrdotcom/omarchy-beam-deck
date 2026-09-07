defmodule BeamDeck.Alerts do
  @moduledoc false

  def derive(snapshot, previous, config) do
    host_alerts(snapshot, config) ++ node_alerts(snapshot, previous, config)
  end

  defp host_alerts(%{host: host, nodes: nodes}, _config) do
    local_nodes = Enum.filter(nodes, &(&1[:attached] && &1[:local]))
    online = Enum.reduce(local_nodes, 0, &((&1[:schedulers_online] || 0) + &2))
    cpus = max(host.logical_cpus || 1, 1)
    ratio = online / cpus

    if ratio >= 2.0 and length(local_nodes) > 1 do
      [
        %{
          id: "host.scheduler_density",
          severity: if(ratio >= 4.0, do: "critical", else: "warning"),
          title: "Local scheduler density",
          message: "#{online} normal schedulers online across #{cpus} host CPUs",
          value: ratio
        }
      ]
    else
      []
    end
  end

  defp node_alerts(%{nodes: nodes}, previous, config) do
    old_nodes = Map.new((previous && previous.nodes) || [], &{&1.name, &1})

    connectivity =
      nodes
      |> Enum.filter(&(&1[:configured] && &1[:required] && !&1[:attached]))
      |> Enum.map(fn node ->
        %{
          id: "#{node.name}.unavailable",
          severity: "critical",
          title: "Required node unavailable",
          node: node.name,
          message: "#{node.name} is configured as required but is not attachable"
        }
      end)

    attached =
      nodes
      |> Enum.filter(& &1[:attached])
      |> Enum.flat_map(fn node ->
        old = old_nodes[node.name]

        limits(node, config) ++
          port_limit(node, config) ++
          runq(node, config) ++
          mailboxes(node, old, config) ++
          expected_links(node) ++
          restart_churn(node)
      end)

    connectivity ++ attached
  end

  defp limits(node, config) do
    process_ratio = ratio(node.processes, node.process_limit)
    atom_ratio = ratio(node.atoms, node.atom_limit)

    []
    |> maybe(
      process_ratio >= config["process_usage_warn"],
      %{
        id: "#{node.name}.process_limit",
        severity: "warning",
        title: "Process table pressure",
        node: node.name,
        message: pct(process_ratio) <> " of process table used"
      }
    )
    |> maybe(
      atom_ratio >= config["atom_usage_warn"],
      %{
        id: "#{node.name}.atom_limit",
        severity: if(atom_ratio >= 0.95, do: "critical", else: "warning"),
        title: "Atom table pressure",
        node: node.name,
        message: pct(atom_ratio) <> " of atom table used"
      }
    )
  end

  defp port_limit(node, config) do
    usage = ratio(node[:ports], node[:port_limit])

    if usage >= config["process_usage_warn"] do
      [
        %{
          id: "#{node.name}.port_limit",
          node: node.name,
          severity: if(usage >= 0.95, do: "critical", else: "warning"),
          title: "Port table pressure",
          message: pct(usage) <> " of port table used"
        }
      ]
    else
      []
    end
  end

  defp runq(node, config) do
    schedulers = max(node.schedulers_online || 1, 1)
    pressure = (node.run_queue || 0) / schedulers

    if pressure >= config["run_queue_per_scheduler_warn"] do
      [
        %{
          id: "#{node.name}.run_queue",
          severity: if(pressure >= 3, do: "critical", else: "warning"),
          title: "Run queue pressure",
          node: node.name,
          message: "run queue #{node.run_queue} across #{schedulers} schedulers",
          value: pressure
        }
      ]
    else
      []
    end
  end

  defp mailboxes(node, old, config) do
    old_processes = Map.new((old && old.hot_processes) || [], &{&1.pid, &1})

    elapsed =
      if BeamDeck.Evidence.fresh_deep_pair?(old, node),
        do: mailbox_elapsed(node[:hot_processes_at_ms], old[:hot_processes_at_ms])

    rows = if node[:process_scan_error], do: [], else: node.hot_processes || []

    Enum.flat_map(rows, fn process ->
      mailbox_alert(node, process, old_processes[process.pid], elapsed, config)
    end)
  end

  defp mailbox_elapsed(current_at, old_at)
       when is_integer(current_at) and is_integer(old_at) and current_at > old_at,
       do: (current_at - old_at) / 1_000.0

  defp mailbox_elapsed(_current_at, _old_at), do: nil

  defp mailbox_alert(node, process, prior, elapsed, config) do
    rate = mailbox_rate(process, prior, elapsed)

    cond do
      process.mailbox >= config["mailbox_critical"] ->
        [
          mailbox_item(
            node,
            process,
            "critical",
            "Mailbox backlog",
            "#{process.name} mailbox is #{process.mailbox}"
          )
        ]

      process.mailbox >= config["mailbox_warn"] or rate >= config["mailbox_rate_warn"] ->
        message = "#{process.name} mailbox #{process.mailbox} (#{round(rate)}/s)"
        [mailbox_item(node, process, "warning", "Mailbox growth", message)]

      true ->
        []
    end
  end

  defp mailbox_rate(process, prior, elapsed) when is_map(prior) and is_number(elapsed),
    do: (process.mailbox - prior.mailbox) / elapsed

  defp mailbox_rate(_process, _prior, _elapsed), do: 0.0

  defp mailbox_item(node, process, severity, title, message) do
    %{
      id: "#{node.name}.#{process.pid}.mailbox",
      severity: severity,
      title: title,
      node: node.name,
      process: process.pid,
      message: message
    }
  end

  defp expected_links(node) do
    missing = (node[:expected_peers] || []) -- (node[:peers] || [])

    if missing == [] do
      []
    else
      [
        %{
          id: "#{node.name}.expected_peers",
          severity: "warning",
          title: "Expected cluster link missing",
          node: node.name,
          message: "#{node.name} cannot currently see #{Enum.join(missing, ", ")}",
          missing: missing
        }
      ]
    end
  end

  defp restart_churn(node) do
    node
    |> Map.get(:restart_churn, [])
    |> Enum.filter(&(&1.count >= 3))
    |> Enum.map(fn churn ->
      %{
        id: "#{node.name}.restart_churn.#{churn.name}",
        severity: "warning",
        title: "Registered process churn",
        node: node.name,
        message: "#{churn.name} changed PID #{churn.count} times in the last 30 seconds",
        count: churn.count
      }
    end)
  end

  defp ratio(_, 0), do: 0.0
  defp ratio(a, b), do: (a || 0) / max(b || 1, 1)
  defp pct(value), do: "#{Float.round(value * 100, 1)}%"
  defp maybe(list, true, item), do: [item | list]
  defp maybe(list, false, _item), do: list
end
