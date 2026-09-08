defmodule BeamDeck.Diagnostics.Interval do
  @moduledoc "Exact-incarnation endpoint comparisons of capped observational metadata."
  alias BeamDeck.Redaction

  def compare(kind, first, last) do
    cond do
      first.node != last.node or not is_integer(first.creation) or
          first.creation != last.creation ->
        {:error, :incomparable_identity}

      last.mono_ms <= first.mono_ms ->
        {:error, :invalid_sample_span}

      true ->
        {:ok, report(kind, first, last)}
    end
  end

  def deltas(first, last, span) do
    reds = difference(first[:reductions], last[:reductions])

    %{
      memory_delta_bytes: difference(first[:memory_bytes], last[:memory_bytes]),
      mailbox_delta: difference(first[:mailbox], last[:mailbox]),
      size_delta: difference(first[:size], last[:size]),
      reductions_delta: if(is_number(reds) and reds >= 0, do: reds),
      reductions_per_second:
        if(is_number(reds) and reds >= 0 and span > 0, do: reds * 1000 / span),
      counter_reset: is_number(reds) and reds < 0
    }
  end

  def rank(rows, keys, cap) do
    ranked = Enum.map(keys, fn key -> Enum.sort_by(rows, &{-score(&1[key]), &1.key}) end)

    ranked
    |> Enum.zip()
    |> Enum.flat_map(&Tuple.to_list/1)
    |> Enum.uniq_by(& &1.key)
    |> Enum.take(cap)
  end

  defp score(n) when is_number(n), do: n
  defp score(_), do: -1.0e100
  defp difference(a, b) when is_number(a) and a >= 0 and is_number(b) and b >= 0, do: b - a
  defp difference(_, _), do: nil

  defp report(kind, first, last) do
    a = index(kind, first.rows)
    b = index(kind, last.rows)
    span = last.mono_ms - first.mono_ms
    keys = (Map.keys(a) ++ Map.keys(b)) |> Enum.uniq()
    rows = Enum.map(keys, &row(&1, a[&1], b[&1], span))

    metrics =
      if kind == "process_window",
        do: [:reductions_per_second, :memory_delta_bytes, :mailbox_delta],
        else: [:memory_delta_bytes, :size_delta]

    selected = rank(rows, metrics, 60)

    Redaction.sanitize(%{
      kind: kind,
      node: last.node,
      creation: last.creation,
      from_at_ms: first.at_ms,
      at_ms: last.at_ms,
      span_ms: span,
      first_scanned: first.scanned,
      last_scanned: last.scanned,
      first_total: first.total,
      last_total: last.total,
      partial: first.partial or last.partial,
      matched: Enum.count(keys, &(Map.has_key?(a, &1) and Map.has_key?(b, &1))),
      first_only: Enum.count(keys, &(not Map.has_key?(b, &1))),
      last_only: Enum.count(keys, &(not Map.has_key?(a, &1))),
      rows: selected,
      omitted_rows: length(rows) - length(selected),
      warning:
        "Racing endpoint observations. Unmatched does not prove exit or creation; short-lived work can be missed. Reductions/s is not CPU percent; growth is not proof of a leak."
    })
  end

  defp index(kind, rows) do
    key = if kind == "process_window", do: :pid, else: :identity
    rows |> Enum.filter(&(is_binary(&1[key]) and &1[key] != "")) |> Map.new(&{&1[key], &1})
  end

  defp row(key, first, last, span) do
    status =
      cond do
        is_nil(first) -> "newly_observed"
        is_nil(last) -> "not_reobserved"
        true -> "matched"
      end

    data =
      Map.take(last || first, [
        :pid,
        :name,
        :identity,
        :owner,
        :owner_name,
        :memory_bytes,
        :mailbox,
        :size,
        :current_function
      ])

    Map.merge(data, deltas(first || %{}, last || %{}, span))
    |> Map.merge(%{
      key: key,
      status: status,
      owner_changed: not is_nil(first) and not is_nil(last) and first[:owner] != last[:owner]
    })
  end
end
