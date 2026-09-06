defmodule BeamDeck.Input do
  @moduledoc "Low-volume command input with a hard line-buffer bound before JSON parsing."
  def run, do: read({<<>>, false})

  def feed({buffer, dropping}, chunk) do
    Enum.reduce(:binary.bin_to_list(chunk), {{buffer, dropping}, []}, fn byte,
                                                                         {{acc, discard}, out} ->
      cond do
        byte == 10 and discard -> {{<<>>, false}, out}
        byte == 10 -> {{<<>>, false}, [{:line, acc} | out]}
        discard -> {{<<>>, true}, out}
        byte_size(acc) >= 16_384 -> {{<<>>, true}, [{:error, :command_too_large} | out]}
        true -> {{<<acc::binary, byte>>, false}, out}
      end
    end)
    |> then(fn {state, lines} -> {state, Enum.reverse(lines)} end)
  end

  defp read(state) do
    # Reading one byte avoids get_chars(N) delaying a short interactive line until N bytes arrive.
    case IO.binread(:stdio, 1) do
      byte when is_binary(byte) ->
        {next, lines} = feed(state, byte)
        Enum.each(lines, &dispatch/1)
        read(next)

      _ ->
        GenServer.cast(BeamDeck.Daemon, :input_closed)
    end
  end

  defp dispatch({:error, :command_too_large}),
    do: BeamDeck.Daemon.protocol_error(:command_too_large)

  defp dispatch({:line, line}) do
    case BeamDeck.Protocol.parse(line) do
      {:ok, command, args} -> BeamDeck.Daemon.command(command, args)
      {:error, reason} -> BeamDeck.Daemon.protocol_error(reason)
    end
  end
end
