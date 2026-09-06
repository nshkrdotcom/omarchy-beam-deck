defmodule BeamDeck.Output do
  @moduledoc false
  @key {__MODULE__, :device}

  def init do
    device =
      case System.get_env("BEAM_DECK_PROTOCOL_PATH") do
        nil ->
          :stdio

        path ->
          case File.open(path, [:write]) do
            {:ok, io} ->
              io

            {:error, reason} ->
              raise "protocol output unavailable: #{inspect(reason)}"
          end
      end

    :persistent_term.put(@key, device)
    :ok
  end

  def puts(value) do
    IO.puts(:persistent_term.get(@key, :stdio), value)
  end
end
