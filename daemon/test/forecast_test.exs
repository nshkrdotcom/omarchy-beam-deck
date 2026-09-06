defmodule BeamDeck.ForecastTest do
  use ExUnit.Case, async: true
  alias BeamDeck.{Config, Forecast}

  defp history(metric, values, step \\ 6_000) do
    values
    |> Enum.with_index()
    |> Enum.map(fn {value, i} ->
      n = %{
        name: "dev@host",
        attached: true,
        uptime_ms: i * step + 1,
        processes: 100,
        process_limit: 100_000,
        atoms: 100,
        atom_limit: 100_000,
        ports: 10,
        port_limit: 65_536,
        memory: %{binary: 0, ets: 0},
        ets: 0
      }

      %{at_ms: i * step, nodes: [Map.put(n, metric, value)]}
    end)
    |> Enum.reverse()
  end

  test "stable growth forecasts actual hard capacity, never ETS count" do
    rows = history(:atoms, Enum.map(1..20, &(&1 * 1_000)))

    assert [%{metric: "atoms", kind: "capacity", confidence: c, eta_ms: eta}] =
             Forecast.derive(rows, Config.defaults())

    assert c > 0.99
    assert abs(eta - 480_000) < 2
    assert Forecast.derive(history(:ets, 1..20), Config.defaults()) == []
  end

  test "warmup, flat and decreasing signals do not fabricate forecasts" do
    for values <- [1..5, List.duplicate(100, 20), Enum.reverse(Enum.to_list(1..20))] do
      assert Forecast.derive(history(:atoms, values), Config.defaults()) == []
    end
  end

  test "a restarted VM, a gap, or a changed limit resets the fitting segment" do
    [newest | rest] = history(:atoms, Enum.map(1..20, &(&1 * 1_000)))
    n = hd(newest.nodes)

    for replacement <- [%{n | uptime_ms: 1}, %{n | attached: false}, %{n | atom_limit: 200_000}] do
      assert Forecast.derive([%{newest | nodes: [replacement]} | rest], Config.defaults()) == []
    end
  end

  test "missing measurements and already exhausted limits do not yield ETA" do
    assert Forecast.derive(history(:atoms, List.duplicate(nil, 20)), Config.defaults()) == []

    assert Forecast.derive(history(:atoms, Enum.map(1..20, &(&1 * 10_000))), Config.defaults()) ==
             []
  end

  test "sample span, duplicate timestamps, sawtooth and distant horizons suppress claims" do
    assert Forecast.derive(history(:atoms, Enum.map(1..20, &(&1 * 1000)), 100), Config.defaults()) ==
             []

    [newest, before | rest] = history(:atoms, Enum.map(1..20, &(&1 * 1000)))

    assert Forecast.derive([newest, %{before | at_ms: newest.at_ms} | rest], Config.defaults()) ==
             []

    assert Forecast.derive(
             history(:atoms, Enum.map(1..20, &if(rem(&1, 2) == 0, do: 30_000, else: 500))),
             Config.defaults()
           ) == []

    assert Forecast.derive(history(:atoms, Enum.to_list(1..20)), Config.defaults()) == []
  end

  test "process and port capacities forecast and classify displayed ETA boundaries" do
    for metric <- [:processes, :ports] do
      [f] = Forecast.derive(history(metric, Enum.map(1..20, &(&1 * 1000))), Config.defaults())
      assert f.metric == Atom.to_string(metric)
      assert f.kind == "capacity"
      assert f.severity == "critical"
    end

    rows = history(:atoms, Enum.map(1..20, &(&1 * 1000)))

    for {critical, warning, severity} <- [
          {480_000, 600_000, "critical"},
          {1000, 480_000, "warning"},
          {1000, 2000, "info"}
        ] do
      config =
        put_in(Config.defaults(), ["forecast", "critical_eta_ms"], critical)
        |> put_in(["forecast", "warning_eta_ms"], warning)

      assert [%{severity: ^severity, eta_ms: 480_000}] = Forecast.derive(rows, config)
    end
  end

  test "growth signals have no capacity or ETA and require absolute and fractional growth" do
    rows = history(:ets, Enum.map(1..20, &(&1 * 4)))
    [ets] = Forecast.derive(rows, Config.defaults())
    assert ets.metric == "ets_count" and ets.kind == "growth"
    assert is_nil(ets.limit) and is_nil(ets.eta_ms)

    for metric <- [:binary, :ets] do
      data =
        history(:atoms, List.duplicate(100, 20))
        |> Enum.map(fn frame ->
          i = div(frame.at_ms, 6000)
          n = hd(frame.nodes)

          %{
            frame
            | nodes: [Map.put(n, :memory, Map.put(n.memory, metric, 100_000_000 + i * 4_000_000))]
          }
        end)

      [f] = Forecast.derive(data, Config.defaults())
      assert f.kind == "growth" and is_nil(f.limit) and is_nil(f.eta_ms)

      high_absolute =
        Config.defaults()
        |> put_in(["forecast", "binary_growth_min_bytes"], 999_000_000)
        |> put_in(["forecast", "ets_memory_growth_min_bytes"], 999_000_000)

      assert Forecast.derive(data, high_absolute) == []

      high_fraction =
        Config.defaults()
        |> put_in(["forecast", "binary_growth_min_fraction"], 0.99)
        |> put_in(["forecast", "ets_memory_growth_min_fraction"], 0.99)

      assert Forecast.derive(data, high_fraction) == []
    end
  end

  test "incarnation change resets history even when uptime alone would look continuous" do
    rows =
      history(:atoms, Enum.map(1..20, &(&1 * 1000)))
      |> Enum.map(fn f ->
        %{f | nodes: Enum.map(f.nodes, &Map.put(&1, :creation, 9))}
      end)

    [latest | rest] = rows
    latest = %{latest | nodes: [Map.put(hd(latest.nodes), :creation, 10)]}
    assert Forecast.derive([latest | rest], Config.defaults()) == []
  end

  test "weighted regression preserves an exact line under irregular timestamps" do
    points = for t <- [0, 3_100, 7_900, 11_000, 19_000], do: %{at_ms: t, value: 7 + t / 1000 * 3}
    fit = Forecast.fit(points, 90_000)
    assert_in_delta fit.slope, 3.0, 1.0e-9
    assert_in_delta fit.r2, 1.0, 1.0e-9
  end
end
