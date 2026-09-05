defmodule BeamDeck.Budget do
  @moduledoc false

  def recommend(nodes, cpus) do
    cpus = max(cpus, 1)

    demand =
      nodes
      |> Enum.filter(&(&1[:attached] && &1[:local]))
      |> Enum.map(fn node ->
        %{
          name: node.name,
          current: max(node.schedulers_online || 1, 1),
          pressure: max(node.run_queue || 0, 0) + 1
        }
      end)

    current_total = Enum.sum(Enum.map(demand, & &1.current))

    cond do
      demand == [] ->
        []

      current_total <= cpus ->
        Enum.map(demand, &result(&1, &1.current))

      true ->
        allocate(demand, cpus)
    end
  end

  defp allocate(demand, cpus) do
    count = length(demand)
    capacity = max(cpus - count, 0)
    total_pressure = Enum.sum(Enum.map(demand, & &1.pressure))

    weighted =
      Enum.map(demand, fn entry ->
        ideal = if total_pressure > 0, do: entry.pressure / total_pressure * capacity, else: 0.0
        floor_extra = min(trunc(:math.floor(ideal)), entry.current - 1)
        Map.merge(entry, %{ideal_extra: ideal, floor_extra: max(floor_extra, 0)})
      end)

    allocations = Map.new(weighted, &{&1.name, 1 + &1.floor_extra})
    used = Enum.sum(Map.values(allocations))
    remaining = max(cpus - used, 0)

    order =
      Enum.sort_by(weighted, fn entry ->
        fraction = entry.ideal_extra - :math.floor(entry.ideal_extra)
        {-fraction, -entry.pressure, entry.name}
      end)

    allocations = distribute(order, allocations, remaining)
    Enum.map(demand, &result(&1, allocations[&1.name] || 1))
  end

  defp distribute(_entries, allocations, 0), do: allocations
  defp distribute([], allocations, _remaining), do: allocations

  defp distribute(entries, allocations, remaining) do
    {next, used} =
      Enum.reduce_while(entries, {allocations, 0}, fn entry, {acc, used} ->
        cond do
          used >= remaining ->
            {:halt, {acc, used}}

          (acc[entry.name] || 1) < entry.current ->
            {:cont, {Map.update!(acc, entry.name, &(&1 + 1)), used + 1}}

          true ->
            {:cont, {acc, used}}
        end
      end)

    if used == 0, do: next, else: distribute(entries, next, remaining - used)
  end

  defp result(entry, suggested) do
    %{node: entry.name, current: entry.current, suggested: min(max(suggested, 1), entry.current)}
  end
end
