defmodule BeamDeck.Json do
  @moduledoc "OTP 27 JSON with capped input, string keys and duplicate-key rejection."

  def encode(term), do: term |> :json.encode(&encode_value/2) |> IO.iodata_to_binary()

  def decode(binary) when is_binary(binary) and byte_size(binary) <= 1_048_576 do
    with :ok <- depth(binary, 0, false, false) do
      decoders = %{
        null: nil,
        object_start: fn _parent -> %{} end,
        object_push: &object_push/3,
        object_finish: fn object, parent -> {object, parent} end
      }

      {value, _acc, rest} = :json.decode(binary, nil, decoders)
      if String.trim(rest) == "", do: {:ok, value}, else: {:error, :trailing_data}
    end
  rescue
    _ -> {:error, :invalid_json}
  end

  def decode(_), do: {:error, :json_too_large}

  defp object_push(key, value, object) do
    if Map.has_key?(object, key), do: :erlang.error(:duplicate_key)
    Map.put(object, key, value)
  end

  defp encode_value(nil, _encoder), do: "null"

  defp encode_value(value, encoder) when is_tuple(value),
    do: :json.encode_list(Tuple.to_list(value), encoder)

  defp encode_value(value, _encoder) when is_pid(value),
    do: :json.encode_binary(BeamDeck.Remote.pid_text(value))

  defp encode_value(value, _encoder) when is_port(value) or is_reference(value),
    do: :json.encode_binary("[metadata]")

  defp encode_value(value, encoder), do: :json.encode_value(value, encoder)

  defp depth(_rest, count, _quoted, _escaped) when count > 32,
    do: {:error, :json_too_deep}

  defp depth(<<>>, _count, _quoted, _escaped), do: :ok

  defp depth(<<_c, rest::binary>>, count, true, true),
    do: depth(rest, count, true, false)

  defp depth(<<92, rest::binary>>, count, true, false),
    do: depth(rest, count, true, true)

  defp depth(<<34, rest::binary>>, count, quoted, false),
    do: depth(rest, count, not quoted, false)

  defp depth(<<c, rest::binary>>, count, false, false) when c in [123, 91],
    do: depth(rest, count + 1, false, false)

  defp depth(<<c, rest::binary>>, count, false, false) when c in [125, 93],
    do: depth(rest, count - 1, false, false)

  defp depth(<<_c, rest::binary>>, count, quoted, _escaped),
    do: depth(rest, count, quoted, false)
end
