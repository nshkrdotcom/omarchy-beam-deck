defmodule BeamDeck.Redaction do
  @moduledoc "Bounded metadata sanitization. Never a substitute for collection allowlists."
  @forbidden ~w(cookie setcookie password secret token authorization environment environ dictionary messages process_state table_values raw_dump raw_prefix)
  @export_only ~w(cwd argv command config config_path cookie_env)

  def configure(config) do
    secrets = config["nodes"] |> Enum.map(&System.get_env(&1["cookie_env"] || ""))
    cookie = if Node.alive?(), do: Atom.to_string(Node.get_cookie()), else: nil

    :persistent_term.put(
      {__MODULE__, :secrets},
      Enum.filter([cookie | secrets], &(is_binary(&1) and &1 != ""))
    )

    :ok
  end

  def sanitize(value, opts \\ []) do
    secrets = Keyword.get(opts, :secrets, :persistent_term.get({__MODULE__, :secrets}, []))
    walk(value, 0, secrets, Keyword.get(opts, :export, false))
  end

  def export(value), do: sanitize(value, export: true)
  def text(value, cap \\ 1_024)

  def text(value, cap) when is_binary(value) do
    value
    |> String.to_charlist()
    |> Enum.map(fn c -> if c < 32 and c not in [9, 10], do: 32, else: c end)
    |> List.to_string()
    |> truncate(cap)
  rescue
    _ ->
      value
      |> :binary.bin_to_list()
      |> Enum.map(fn c -> if c in 32..126, do: c, else: 63 end)
      |> List.to_string()
      |> truncate(cap)
  end

  def text(value, cap) when is_atom(value) or is_integer(value), do: text(to_string(value), cap)
  def text(_value, _cap), do: "[metadata]"

  defp truncate(value, cap) when byte_size(value) <= cap, do: value

  defp truncate(value, cap) do
    marker = String.duplicate(".", min(max(cap, 0), 3))
    part = binary_part(value, 0, max(cap - byte_size(marker), 0))
    valid_prefix(part) <> marker
  end

  defp valid_prefix(part) do
    if String.valid?(part),
      do: part,
      else: valid_prefix(binary_part(part, 0, byte_size(part) - 1))
  end

  defp walk(_value, depth, _secrets, _export) when depth > 12, do: "[TRUNCATED]"

  defp walk(
         value,
         depth,
         secrets,
         export?
       )
       when is_map(value) do
    value
    |> Enum.take(128)
    |> Enum.reduce(
      %{},
      fn pair, acc ->
        walk_map_pair(
          pair,
          acc,
          depth,
          secrets,
          export?
        )
      end
    )
  end

  defp walk(value, depth, secrets, export?) when is_list(value),
    do: value |> Enum.take(256) |> Enum.map(&walk(&1, depth + 1, secrets, export?))

  defp walk({key, value}, depth, secrets, export?) when is_atom(key) or is_binary(key) do
    if sensitive_key?(key),
      do: [text(key, 128), "[REDACTED]"],
      else: [walk(key, depth + 1, secrets, export?), walk(value, depth + 1, secrets, export?)]
  end

  defp walk(value, depth, secrets, export?) when is_tuple(value),
    do: walk(Tuple.to_list(value), depth + 1, secrets, export?)

  defp walk(value, _depth, secrets, _export) when is_binary(value),
    do: value |> scrub(secrets) |> text()

  defp walk(value, _depth, _secrets, _export)
       when is_number(value) or is_boolean(value) or is_nil(value), do: value

  defp walk(value, _depth, secrets, _export) when is_atom(value),
    do: value |> Atom.to_string() |> scrub(secrets) |> text()

  defp walk(value, _depth, _secrets, _export) when is_pid(value),
    do: BeamDeck.Remote.pid_text(value)

  defp walk(_value, _depth, _secrets, _export), do: "[metadata]"

  defp walk_map_pair(
         {key, value},
         acc,
         depth,
         secrets,
         export?
       ) do
    name =
      key
      |> text(128)
      |> String.downcase()

    if forbidden_map_key?(
         key,
         name,
         export?
       ) do
      acc
    else
      Map.put(
        acc,
        safe_map_key(key, secrets),
        walk(
          value,
          depth + 1,
          secrets,
          export?
        )
      )
    end
  end

  defp forbidden_map_key?(key, name, export?) do
    name in @forbidden or
      sensitive_key?(key) or
      (export? and name in @export_only)
  end

  defp safe_map_key(key, secrets) do
    raw =
      if is_binary(key),
        do: key,
        else: text(key, 128)

    safe =
      raw
      |> scrub(secrets)
      |> text(128)

    if is_atom(key) and safe == raw,
      do: key,
      else: safe
  end

  defp sensitive_key?(key) do
    normalized = key |> text(128) |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")

    Regex.match?(
      ~r/(password|passwd|secret|token|cookie|credential|credentials|authorization|apikey|privatekey)$/,
      normalized
    )
  end

  defp scrub(value, secrets) do
    # Replace exact secrets BEFORE truncation in callers that collect larger text.
    value = if String.valid?(value), do: value, else: text(value, byte_size(value))

    value =
      Enum.reduce(Enum.sort_by(secrets, &byte_size/1, :desc), value, fn secret, acc ->
        String.replace(acc, secret, "[REDACTED]")
      end)

    Regex.replace(
      ~r/((?:-setcookie|--cookie|cookie|password|token|secret)\s*[=: ]\s*)[^\s,;"}]+/i,
      value,
      "\\1[REDACTED]"
    )
  end
end
