defmodule BeamDeck.Input do
  @moduledoc false
  def run do
    IO.stream(:stdio, :line)
    |> Enum.each(fn line ->
      case BeamDeck.Protocol.parse(line) do
        {:ok, cmd, args} -> BeamDeck.Daemon.command(cmd, args)
        {:error, reason} -> BeamDeck.Daemon.protocol_error(reason)
      end
    end)
  end
end
