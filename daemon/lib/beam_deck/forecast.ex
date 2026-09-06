defmodule BeamDeck.Forecast do
  @moduledoc "Conservative weighted trend estimates; confidence is fit quality, not probability."
  @metrics [
    {:processes, :process_limit, "processes"},
    {:atoms, :atom_limit, "atoms"},
    {:ports, :port_limit, "ports"},
    {:binary, nil, "binary_memory"},
    {:ets_memory, nil, "ets_memory"},
    {:ets, nil, "ets_count"}
  ]

  def derive([], _config), do: []

  def derive(history, config) do
    f = config["forecast"]

    if f["enabled"] do
      names =
        hd(history) |> Map.get(:nodes, []) |> Enum.filter(& &1[:attached]) |> Enum.map(& &1.name)

      rows =
        for name <- names,
            metric <- @metrics,
            result = estimate(segment(history, name, metric), name, metric, f),
            not is_nil(result),
            do: result

      rows
      |> Enum.sort_by(
        &{Map.get(%{"critical" => 0, "warning" => 1, "info" => 2}, &1.severity),
         &1.eta_ms || 86_400_000, &1.id}
      )
      |> Enum.take(100)
    else
      []
    end
  end

  defp value(n, :binary), do: get_in(n, [:memory, :binary])
  defp value(n, :ets_memory), do: get_in(n, [:memory, :ets])
  defp value(n, key), do: n[key]

  defp segment(history, name, {key, limit, _label}) do
    {points, _newer} =
      Enum.reduce_while(history, {[], nil}, fn frame, acc ->
        segment_frame(frame, acc, name, key, limit)
      end)

    points
  end

  defp segment_frame(frame, {acc, newer}, name, key, limit) do
    node = Enum.find(frame[:nodes] || [], &(&1.name == name))

    if continuous_point?(node, frame, newer, key, limit) do
      point = segment_point(node, frame, key, limit)
      {:cont, {[point | acc], point}}
    else
      {:halt, {acc, newer}}
    end
  end

  defp continuous_point?(nil, _frame, _newer, _key, _limit), do: false

  defp continuous_point?(node, _frame, nil, key, _limit) do
    valid_point?(node, key)
  end

  defp continuous_point?(node, frame, newer, key, limit) do
    valid_point?(node, key) and node.uptime_ms <= newer.uptime_ms and
      node[:creation] == newer.creation and frame.at_ms < newer.at_ms and
      frame.at_ms >= newer.at_ms - 120_000 and
      (is_nil(limit) or node[limit] == newer.limit)
  end

  defp valid_point?(node, key) do
    node[:attached] == true and is_number(value(node, key)) and is_number(node[:uptime_ms])
  end

  defp segment_point(node, frame, key, limit) do
    %{
      at_ms: frame.at_ms,
      value: value(node, key),
      uptime_ms: node.uptime_ms,
      creation: node[:creation],
      limit: node[limit]
    }
  end

  defp estimate(points, name, {key, limit_key, label}, f) do
    if length(points) >= f["min_samples"] do
      first = hd(points)
      latest = List.last(points)
      span = latest.at_ms - first.at_ms
      fit = fit(points, f["half_life_ms"])
      stable = stability(points)

      if span >= f["min_span_ms"] and fit.slope > 0 and fit.r2 >= f["min_r2"] and
           stable >= f["min_stability"] do
        base = %{
          id: "forecast:#{name}:#{label}",
          node: name,
          metric: label,
          current: latest.value,
          rate_per_second: fit.slope,
          fit_r2: fit.r2,
          stability: stable,
          confidence: min(fit.r2, stable),
          sample_count: length(points),
          span_ms: span,
          evidence_class: "heuristic",
          at_ms: latest.at_ms
        }

        finish(base, first.value, latest.limit, key, limit_key, f)
      end
    end
  end

  defp finish(base, _first, limit, _key, limit_key, f) when not is_nil(limit_key) do
    if capacity_available?(base, limit) do
      capacity_forecast(base, limit, f)
    end
  end

  defp finish(base, first, _limit, key, _limit_key, f) do
    prefix =
      case key do
        :binary -> "binary_growth"
        :ets_memory -> "ets_memory_growth"
        :ets -> "ets_count_growth"
      end

    absolute = f[prefix <> if(key == :ets, do: "_min", else: "_min_bytes")]
    fraction = f[prefix <> "_min_fraction"]
    delta = base.current - first

    if delta >= absolute and delta / max(first, 1) >= fraction do
      Map.merge(base, %{
        kind: "growth",
        limit: nil,
        eta_ms: nil,
        severity: "warning",
        growth: delta,
        summary: "Sustained #{base.metric} growth; this is not an exhaustion forecast"
      })
    end
  end

  defp capacity_available?(base, limit) do
    is_number(limit) and limit > base.current and limit > 0
  end

  defp capacity_forecast(base, limit, f) do
    eta = round((limit - base.current) / base.rate_per_second * 1_000)

    if eta <= f["info_eta_ms"] do
      Map.merge(base, %{
        kind: "capacity",
        limit: limit,
        eta_ms: eta,
        severity: capacity_severity(eta, f),
        summary:
          "#{base.metric} may reach the configured hard limit if the observed trend continues"
      })
    end
  end

  defp capacity_severity(eta, f) do
    cond do
      eta <= f["critical_eta_ms"] -> "critical"
      eta <= f["warning_eta_ms"] -> "warning"
      true -> "info"
    end
  end

  def fit([], _half_life_ms), do: %{slope: 0.0, r2: 0.0}

  def fit(points, half_life_ms) do
    last = List.last(points).at_ms

    rows =
      Enum.map(points, fn p ->
        {(p.at_ms - last) / 1_000, p.value, :math.pow(0.5, (last - p.at_ms) / half_life_ms)}
      end)

    weight = Enum.reduce(rows, 0.0, fn {_, _, w}, acc -> acc + w end)
    mx = Enum.reduce(rows, 0.0, fn {x, _, w}, acc -> acc + x * w end) / weight
    my = Enum.reduce(rows, 0.0, fn {_, y, w}, acc -> acc + y * w end) / weight
    vx = Enum.reduce(rows, 0.0, fn {x, _, w}, acc -> acc + w * (x - mx) * (x - mx) end)
    cov = Enum.reduce(rows, 0.0, fn {x, y, w}, acc -> acc + w * (x - mx) * (y - my) end)
    slope = if vx > 0, do: cov / vx, else: 0.0
    total = Enum.reduce(rows, 0.0, fn {_, y, w}, acc -> acc + w * (y - my) * (y - my) end)

    error =
      Enum.reduce(rows, 0.0, fn {x, y, w}, acc ->
        residual = y - (my + slope * (x - mx))
        acc + w * residual * residual
      end)

    %{slope: slope, r2: if(total > 0, do: max(0.0, 1 - error / total), else: 0.0)}
  end

  defp stability(points) do
    pairs = Enum.chunk_every(points, 2, 1, :discard)
    Enum.count(pairs, fn [a, b] -> b.value >= a.value end) / max(length(pairs), 1)
  end
end
