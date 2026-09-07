defmodule BeamDeck.Activity do
  @moduledoc "Bounded safe explanations of observed changes, owned by the flight recorder."
  alias BeamDeck.{Evidence, Redaction}
  @fields [:schedulers_online, :dirty_cpu_schedulers_online]
  @events ~w(nodeup nodedown long_gc long_schedule long_message_queue large_heap busy_port busy_dist_port events_dropped probe_overloaded)

  def derive(previous, frame) do
    before = Map.new(previous[:nodes] || [], &{&1.name, &1})
    nodes = Enum.flat_map(frame.nodes, &node_changes(before[&1.name], &1))
    events = Enum.map(frame.new_events, &runtime_event/1)

    (nodes ++ events)
    |> Enum.take(64)
    |> Enum.with_index()
    |> Enum.map(fn {row, i} ->
      Map.merge(row, %{
        id: "activity:#{frame.sequence}:#{i}",
        frame_id: frame.frame_id,
        sequence: frame.sequence,
        captured_at_ms: frame.at_ms,
        at_ms: row[:at_ms] || frame.at_ms,
        evidence_class: "observed"
      })
    end)
  end

  defp node_changes(nil, node),
    do: [change(node, "discovered", "Node first observed; attachment is separate evidence.")]

  defp node_changes(old, node) do
    cond do
      old[:attached] == true and node[:attached] != true ->
        [change(node, "unreachable", "OTP attachment lost; this does not prove the VM exited.")]

      old[:attached] != true and node[:attached] == true ->
        [change(node, "attached", "OTP attachment became available.")]

      node[:attached] != true ->
        []

      known_restart?(old, node) ->
        [
          change(
            node,
            "restarted",
            "VM incarnation changed; process identities and counters are discontinuous."
          )
        ]

      true ->
        field_changes(old, node) ++ replacements(old, node)
    end
  end

  defp known_restart?(old, node) do
    is_integer(old[:creation]) and is_integer(node[:creation]) and
      not Evidence.same_incarnation?(old, node)
  end

  defp field_changes(old, node) do
    fields =
      Enum.filter(@fields, &(is_number(old[&1]) and is_number(node[&1]) and old[&1] != node[&1]))

    if fields == [],
      do: [],
      else: [
        Map.put(
          change(node, "changed", "Changed measured fields: " <> Enum.join(fields, ", ")),
          :changed_fields,
          Enum.map(fields, &Atom.to_string/1)
        )
      ]
  end

  defp replacements(old, node) do
    if Evidence.fresh_deep_pair?(old, node) do
      prior = Map.new(old[:registered_processes] || [], &{&1.name, &1.pid})

      for p <- node[:registered_processes] || [],
          is_binary(prior[p.name]),
          prior[p.name] != p.pid do
        change(
          node,
          "registered_replaced",
          "Registered name resolved to a different PID; supervision cause is unknown."
        )
        |> Map.merge(%{
          domain: "process",
          name: Redaction.text(p.name, 255),
          subject: p.pid,
          changed_fields: ["pid"]
        })
      end
    else
      []
    end
  end

  defp change(node, kind, summary) do
    %{
      domain: "node",
      kind: kind,
      node: node.name,
      creation: node[:creation],
      summary: summary,
      changed_fields: []
    }
  end

  defp runtime_event(event) do
    kind = if event[:kind] in @events, do: event.kind, else: "runtime_event"

    summary =
      case kind do
        "nodedown" -> "Distribution disconnected; not proof of VM exit."
        "nodeup" -> "Distribution connected."
        _ -> "Explicit system event: #{kind}. Temporal association is not a demonstrated cause."
      end

    event
    |> Map.take([:node, :subject, :at_ms])
    |> Map.merge(%{domain: "runtime", kind: kind, summary: summary, changed_fields: []})
  end
end
