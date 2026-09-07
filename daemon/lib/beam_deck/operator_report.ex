defmodule BeamDeck.OperatorReport do
  @moduledoc "Explicit bounded human handoff; never a dump of internal state."
  alias BeamDeck.Redaction

  def render(snapshot, frames, diff, historical?) do
    selected = if historical?, do: List.last(frames) || %{}, else: snapshot
    selected = Redaction.export(selected)
    diff = Redaction.export(diff)

    lines =
      [
        "BEAM Deck operator report",
        if(historical?,
          do: "HISTORICAL RANGE / read-only evidence",
          else: "LIVE CAPTURE / retained range"
        ),
        range_text(frames),
        "Quality: #{quality(selected)}",
        "",
        "FINDINGS"
      ] ++
        findings(selected) ++
        ["", "BEFORE / AFTER (directional, not proof of intervention benefit)"] ++
        comparison(diff) ++
        ["", "WATCH CONTEXT"] ++
        watches(selected) ++
        ["", "RECORDED ACTIVITY"] ++
        activity(selected) ++
        [
          "",
          "UNRESOLVED QUESTIONS",
          "Was the workload comparable? Were symptoms reproduced after the intervention?",
          "Capped or missing evidence cannot establish absence. Nearby events are correlation, not cause.",
          "Names may identify applications. Review before sharing. No messages, state, ETS contents, arguments or cookies are intentionally collected."
        ]

    lines |> Enum.join("\n") |> Redaction.text(65_536)
  end

  defp range_text([]), do: "No retained frames available."

  defp range_text(frames) do
    a = hd(frames)
    b = List.last(frames)

    "#{a.frame_id} at #{timestamp(a.at_ms)} -> #{b.frame_id} at #{timestamp(b.at_ms)} / #{length(frames)} retained frames"
  end

  defp timestamp(at) when is_integer(at) do
    case DateTime.from_unix(at, :millisecond) do
      {:ok, time} -> DateTime.to_iso8601(time)
      _ -> "unavailable"
    end
  end

  defp timestamp(_), do: "unavailable"

  defp quality(s) do
    c = s[:collection] || %{}

    "#{c[:status] || "unknown"}; capture #{timestamp(s[:at_ms])}; collection #{c[:duration_ms] || "unavailable"} ms. Deep samples have independent ages."
  end

  defp findings(s) do
    rows = Enum.take(s[:incidents] || [], 20)

    if rows == [],
      do: ["No retained findings; this does not establish health."],
      else:
        Enum.map(rows, fn i ->
          "#{i[:severity]} / #{i[:status]} / #{i[:evidence_class]} / #{i[:node] || "host"}: #{i[:title]} — #{i[:summary]}"
        end)
  end

  defp comparison(nil), do: ["Comparison unavailable."]

  defp comparison(diff) do
    rss = get_in(diff, [:summary_delta, :beam_rss_bytes])

    ["Host BEAM RSS: #{signed(rss)} B"] ++
      Enum.flat_map(Enum.take(diff.nodes, 16), fn n ->
        ["#{n.node}: #{n.change}; utilization #{signed(n[:utilization_delta_pp])} pp"] ++
          Enum.map([:processes, :atoms, :ports, :run_queue], fn key ->
            "  #{key}: #{signed(get_in(n, [:delta, key]))}"
          end) ++
          Enum.map([:total, :processes, :binary, :ets, :code], fn key ->
            "  #{key} memory: #{signed(get_in(n, [:memory_delta, key]))} B"
          end)
      end)
  end

  defp signed(n) when is_number(n), do: if(n > 0, do: "+", else: "") <> to_string(n)
  defp signed(_), do: "unavailable"

  defp watches(s) do
    rows = Enum.take(get_in(s, [:watchlist, :entries]) || [], 64)

    if rows == [],
      do: ["No retained watches."],
      else:
        Enum.map(rows, fn w ->
          "#{w["node"]} / #{w["name"] || "node"}: #{w["status"] || "unknown"}"
        end)
  end

  defp activity(s) do
    rows = Enum.take(s[:activity] || get_in(s, [:flight_recorder, :activity]) || [], 20)

    if rows == [],
      do: ["No retained activity in this context."],
      else:
        Enum.map(rows, fn e ->
          "#{timestamp(e[:at_ms])} / #{e[:node]} / #{e[:kind]} / #{e[:frame_id]}: #{e[:summary]}"
        end)
  end
end
