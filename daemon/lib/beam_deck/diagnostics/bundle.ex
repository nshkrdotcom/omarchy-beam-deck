defmodule BeamDeck.Diagnostics.Bundle do
  @moduledoc "Explicit, bounded, private ZIP export using OTP's built-in ZIP implementation."
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
         {:ok, files} <- entries(snapshot, encoded_frames, frames),
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
        bytes = frame |> Redaction.export() |> Json.encode()
        total = size + byte_size(bytes) + 1
        if total <= @limit, do: {:cont, {[bytes | encoded], total}}, else: {:halt, :too_large}
      end)

    case result do
      {parts, _} -> {:ok, "[" <> Enum.join(Enum.reverse(parts), ",") <> "]"}
      _ -> {:error, :export_too_large}
    end
  end

  defp entries(snapshot, frames_json, frames) do
    fields =
      Map.take(
        snapshot,
        ~w(type protocol at_ms session_id host summary nodes alerts forecasts budget budget_trial topology)a
      )

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

    data = [
      {~c"BEAM-DECK-DIAGNOSTICS.txt",
       "BEAM Deck 1.1 diagnostics\nReview before sharing. Node, module and registered names are operational metadata.\nNo process state/messages, ETS contents, cookies, raw config/logs or crash dump are included.\n"},
      {~c"metadata.json", Json.encode(metadata)},
      {~c"current-snapshot.json", fields |> Redaction.export() |> Json.encode()},
      {~c"flight-recorder.json", frames_json},
      {~c"incidents.json", snapshot[:incidents] |> Redaction.export() |> Json.encode()},
      {~c"recent-events.json", snapshot[:events] |> Redaction.export() |> Json.encode()},
      {~c"crash-triage.json", snapshot[:crash_triage] |> Redaction.export() |> Json.encode()}
    ]

    if Enum.sum(Enum.map(data, fn {_, bytes} -> byte_size(bytes) end)) <= @limit,
      do: {:ok, data},
      else: {:error, :export_too_large}
  end
end
