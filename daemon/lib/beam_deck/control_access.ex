defmodule BeamDeck.ControlAccess do
  @moduledoc "Execution-time authority for a live view, never inferred from a queued request."
  def authorize(state, epoch, name, creation, now) do
    cond do
      not state.panel_open or state[:historical_mode] == true or state.panel_epoch != epoch ->
        {:error, :live_view_changed}

      not fresh_target?(state[:snapshot], name, creation, now) ->
        {:error, :target_stale_or_changed}

      true ->
        :ok
    end
  end

  defp fresh_target?(%{at_ms: at, nodes: nodes}, name, creation, now) when is_integer(at) do
    now - at <= 10_000 and now >= at - 5_000 and
      Enum.any?(nodes, fn n ->
        n.name == name and n[:attached] == true and
          is_integer(creation) and n[:creation] == creation
      end)
  end

  defp fresh_target?(_, _, _, _), do: false
end
