defmodule BeamDeck.DeepEvents do
  @moduledoc false

  @probe :nshkr_beam_deck_probe

  def start(node, thresholds, parent \\ self()) do
    with {:ok, false} <- BeamDeck.Remote.call_raw(node, :code, :is_loaded, [@probe]),
         {:ok, {_mod, binary, _file}} <- object_code(),
         {:ok, {:module, @probe}} <-
           BeamDeck.Remote.call_raw(node, :code, :load_binary, [
             @probe,
             ~c"beam-deck://nshkr-probe",
             binary
           ]),
         opts <- atomize_thresholds(thresholds) do
      case BeamDeck.Remote.call_raw(node, @probe, :start, [parent, opts], 6_000) do
        {:ok, {:ok, pid}} when is_pid(pid) ->
          {:ok, pid}

        other ->
          unload(node)
          {:error, other}
      end
    else
      other -> {:error, other}
    end
  end

  def stop(node, pid) do
    case BeamDeck.Remote.call_raw(node, @probe, :stop, [pid], 3_000) do
      {:ok, :ok} -> unload(node)
      _ -> {:error, :stop_unconfirmed}
    end
  end

  defp unload(node) do
    _ = BeamDeck.Remote.call_raw(node, :code, :delete, [@probe])
    _ = BeamDeck.Remote.call_raw(node, :code, :soft_purge, [@probe])
    :ok
  end

  defp object_code do
    case :code.get_object_code(@probe) do
      {m, bin, file} -> {:ok, {m, bin, file}}
      :error -> {:error, :probe_not_compiled}
    end
  end

  defp atomize_thresholds(map) do
    %{
      long_gc_ms: map["long_gc_ms"] || 100,
      long_schedule_ms: map["long_schedule_ms"] || 100,
      mailbox_enable: map["mailbox_enable"] || 5_000,
      mailbox_disable: map["mailbox_disable"] || 1_000,
      large_heap_words: map["large_heap_words"] || 8_000_000
    }
  end
end
