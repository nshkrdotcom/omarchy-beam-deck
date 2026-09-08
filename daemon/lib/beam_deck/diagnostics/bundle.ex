defmodule BeamDeck.Diagnostics.Bundle do
  @moduledoc "Explicit, capped, private ZIP export using OTP's built-in ZIP implementation."
  alias BeamDeck.{FlightRecorder, Json, PrivateFile, Redaction}
  @limit 16_777_216
  def directory do
    Path.join([
      System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state"),
      "beam-deck",
      "exports"
    ])
  end

  def export(snapshot, recorder, from, to, dir \\ directory()) do
    with {:ok, frames} <- FlightRecorder.range(recorder, from, to),
         {:ok, encoded_frames} <- encode_frames(frames),
         {:ok, files} <-
           entries(snapshot, encoded_frames, frames, recorder, not is_nil(from) or not is_nil(to)),
         {:ok, {_name, archive}} <- :zip.create(~c"diagnostics.zip", files, [:memory]),
         true <- byte_size(archive) <= @limit,
         path <-
           Path.join(
             dir,
             "beam-deck-" <>
               Integer.to_string(System.system_time(:millisecond)) <>
               "-" <> Integer.to_string(System.unique_integer([:positive])) <> ".zip"
           ),
         :ok <- PrivateFile.write(path, archive) do
      {:ok,
       %{
         path: path,
         bytes: byte_size(archive),
         frame_count: length(frames),
         privacy:
           "Redacted operational metadata may still identify applications. Review before sharing."
       }}
    else
      {:error, :frame_expired} = error -> error
      _ -> {:error, :export_failed_or_too_large}
    end
  end

  defp encode_frames(frames) do
    result =
      Enum.reduce_while(frames, {[], 2}, fn frame, {encoded, size} ->
        bytes = frame |> BeamDeck.Projection.snapshot() |> Redaction.export() |> Json.encode()
        total = size + byte_size(bytes) + 1
        if total <= @limit, do: {:cont, {[bytes | encoded], total}}, else: {:halt, :too_large}
      end)

    case result do
      {parts, _} -> {:ok, "[" <> Enum.join(Enum.reverse(parts), ",") <> "]"}
      _ -> {:error, :export_too_large}
    end
  end

  defp entries(snapshot, frames_json, frames, recorder, historical?) do
    fields = BeamDeck.Projection.snapshot(snapshot)

    metadata = %{
      product: "BEAM Deck",
      version: "1.1.0",
      protocol: 1,
      agentless: true,
      exported_at_ms: System.system_time(:millisecond),
      frame_count: length(frames),
      from_at_ms: if(frames == [], do: nil, else: hd(frames).at_ms),
      to_at_ms: if(frames == [], do: nil, else: List.last(frames).at_ms)
    }

    diff =
      case frames do
        [] ->
          nil

        [first | _] ->
          {:ok, diff} =
            FlightRecorder.compare(recorder, first.frame_id, List.last(frames).frame_id)

          diff
      end

    context_frames =
      Enum.map(frames, fn f ->
        {:ok, enriched} = FlightRecorder.get(recorder, f.frame_id)
        enriched
      end)

    report = BeamDeck.OperatorReport.render(snapshot, context_frames, diff, historical?)

    data = [
      {~c"BEAM-DECK-DIAGNOSTICS.txt", report},
      {~c"metadata.json", Json.encode(metadata)},
      {~c"current-snapshot.json", fields |> Redaction.export() |> Json.encode()},
      {~c"flight-recorder.json", frames_json},
      {~c"incidents.json",
       snapshot[:incidents]
       |> BeamDeck.Projection.incidents()
       |> Redaction.export()
       |> Json.encode()},
      {~c"recent-events.json",
       snapshot[:events] |> BeamDeck.Projection.events() |> Redaction.export() |> Json.encode()},
      {~c"crash-triage.json",
       snapshot[:crash_triage]
       |> BeamDeck.Projection.crashes()
       |> Redaction.export()
       |> Json.encode()}
    ]

    if Enum.sum(Enum.map(data, fn {_, bytes} -> byte_size(bytes) end)) <= @limit,
      do: {:ok, data},
      else: {:error, :export_too_large}
  end
end
