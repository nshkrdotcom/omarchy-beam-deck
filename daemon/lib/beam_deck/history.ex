defmodule BeamDeck.History do
  @moduledoc false
  def push(history, sample, max) do
    list = [sample | history]
    if length(list) > max, do: Enum.take(list, max), else: list
  end

  def chronological(history), do: Enum.reverse(history)

  def present(history, max_points) when is_integer(max_points) and max_points > 1 do
    rows = chronological(history)
    count = length(rows)

    if count <= max_points do
      rows
    else
      last = count - 1
      slots = max_points - 1

      for slot <- 0..slots do
        Enum.at(rows, round(slot * last / slots))
      end
    end
  end
end
