defmodule BeamDeck.Json do
  @moduledoc false

  def encode(term), do: term |> enc() |> IO.iodata_to_binary()

  def decode(binary) when is_binary(binary) do
    with {:ok, value, rest} <- value(skip(binary)),
         <<>> <- skip(rest) do
      {:ok, value}
    else
      {:error, _} = error -> error
      _ -> {:error, :trailing_data}
    end
  end

  defp enc(nil), do: "null"
  defp enc(true), do: "true"
  defp enc(false), do: "false"
  defp enc(v) when is_integer(v), do: Integer.to_string(v)
  defp enc(v) when is_float(v), do: :erlang.float_to_binary(v, [:compact])
  defp enc(v) when is_binary(v), do: [?\", escape(v), ?\"]
  defp enc(v) when is_atom(v), do: enc(Atom.to_string(v))
  defp enc(v) when is_pid(v) or is_port(v) or is_reference(v), do: enc(inspect(v))
  defp enc(v) when is_tuple(v), do: enc(Tuple.to_list(v))
  defp enc(v) when is_list(v), do: ["[", join(Enum.map(v, &enc/1)), "]"]

  defp enc(v) when is_map(v) do
    pairs =
      v
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map(fn {k, val} -> [enc(to_string(k)), ?:, enc(val)] end)

    [?{, join(pairs), ?}]
  end

  defp enc(v), do: enc(inspect(v))

  defp join([]), do: []
  defp join([x]), do: x
  defp join([x | xs]), do: [x, ?, | join(xs)]

  defp escape(<<>>), do: []
  defp escape(<<?\", rest::binary>>), do: ["\\\"", escape(rest)]
  defp escape(<<?\\, rest::binary>>), do: ["\\\\", escape(rest)]
  defp escape(<<?\b, rest::binary>>), do: ["\\b", escape(rest)]
  defp escape(<<?\f, rest::binary>>), do: ["\\f", escape(rest)]
  defp escape(<<?\n, rest::binary>>), do: ["\\n", escape(rest)]
  defp escape(<<?\r, rest::binary>>), do: ["\\r", escape(rest)]
  defp escape(<<?\t, rest::binary>>), do: ["\\t", escape(rest)]

  defp escape(<<c, rest::binary>>) when c < 0x20,
    do: ["\\u", Base.encode16(<<c>>, case: :lower) |> String.pad_leading(4, "0"), escape(rest)]

  defp escape(<<c::utf8, rest::binary>>), do: [<<c::utf8>>, escape(rest)]

  defp skip(<<c, rest::binary>>) when c in [32, 9, 10, 13], do: skip(rest)
  defp skip(rest), do: rest

  defp value(<<"null", rest::binary>>), do: {:ok, nil, rest}
  defp value(<<"true", rest::binary>>), do: {:ok, true, rest}
  defp value(<<"false", rest::binary>>), do: {:ok, false, rest}
  defp value(<<?\", rest::binary>>), do: string(rest, [])
  defp value(<<?{, rest::binary>>), do: object(skip(rest), %{})
  defp value(<<?[, rest::binary>>), do: array(skip(rest), [])
  defp value(bin), do: number(bin)

  defp string(<<?\", rest::binary>>, acc), do: {:ok, IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp string(<<?\\, ?\", rest::binary>>, acc), do: string(rest, ["\"" | acc])
  defp string(<<?\\, ?\\, rest::binary>>, acc), do: string(rest, ["\\" | acc])
  defp string(<<?\\, ?/, rest::binary>>, acc), do: string(rest, ["/" | acc])
  defp string(<<?\\, ?b, rest::binary>>, acc), do: string(rest, [<<8>> | acc])
  defp string(<<?\\, ?f, rest::binary>>, acc), do: string(rest, [<<12>> | acc])
  defp string(<<?\\, ?n, rest::binary>>, acc), do: string(rest, ["\n" | acc])
  defp string(<<?\\, ?r, rest::binary>>, acc), do: string(rest, ["\r" | acc])
  defp string(<<?\\, ?t, rest::binary>>, acc), do: string(rest, ["\t" | acc])

  defp string(<<?\\, ?u, a, b, c, d, rest::binary>>, acc) do
    case Integer.parse(<<a, b, c, d>>, 16) do
      {cp, ""} when cp not in 0xD800..0xDFFF -> string(rest, [<<cp::utf8>> | acc])
      _ -> {:error, :bad_unicode_escape}
    end
  end

  defp string(<<c::utf8, rest::binary>>, acc) when c >= 0x20,
    do: string(rest, [<<c::utf8>> | acc])

  defp string(_, _), do: {:error, :unterminated_string}

  defp array(<<?], rest::binary>>, acc), do: {:ok, Enum.reverse(acc), rest}
  defp array(<<>>, _acc), do: {:error, :bad_array}

  defp array(bin, acc) do
    with {:ok, value, rest} <- value(bin) do
      case skip(rest) do
        <<?,, tail::binary>> -> array(skip(tail), [value | acc])
        <<?], tail::binary>> -> {:ok, Enum.reverse([value | acc]), tail}
        _ -> {:error, :bad_array}
      end
    end
  end

  defp object(<<?}, rest::binary>>, acc), do: {:ok, acc, rest}

  defp object(<<?\", rest::binary>>, acc) do
    with {:ok, key, after_key} <- string(rest, []),
         <<?:, after_colon::binary>> <- skip(after_key),
         {:ok, val, after_val} <- value(skip(after_colon)) do
      case skip(after_val) do
        <<?,, tail::binary>> -> object(skip(tail), Map.put(acc, key, val))
        <<?}, tail::binary>> -> {:ok, Map.put(acc, key, val), tail}
        _ -> {:error, :bad_object}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :bad_object}
    end
  end

  defp object(_, _), do: {:error, :bad_object}

  defp number(bin) do
    case Regex.run(~r/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/, bin) do
      [raw] -> parse_number(raw, bin)
      _ -> {:error, :unexpected_token}
    end
  end

  defp parse_number(raw, bin) do
    rest = binary_part(bin, byte_size(raw), byte_size(bin) - byte_size(raw))

    parsed =
      if String.contains?(raw, [".", "e", "E"]),
        do: Float.parse(raw),
        else: Integer.parse(raw)

    case parsed do
      {value, ""} -> {:ok, value, rest}
      _ -> {:error, :bad_number}
    end
  end
end
