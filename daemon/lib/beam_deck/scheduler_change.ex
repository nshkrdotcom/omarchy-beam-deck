defmodule BeamDeck.SchedulerChange do
  @moduledoc false
  alias BeamDeck.Remote

  def set(node, flag, value) do
    with {:ok, coupled} <- coupled_before(node, flag),
         {:ok, old} <- Remote.call_raw(node, :erlang, :system_flag, [flag, value]),
         :ok <- await_counts(node, expected(flag, value, old, coupled), 50) do
      {:ok, old}
    end
  end

  defp coupled_before(node, :schedulers_online) do
    with {:ok, normal} <- info(node, :schedulers),
         {:ok, dirty} <- info(node, :dirty_cpu_schedulers),
         {:ok, online} <- info(node, :dirty_cpu_schedulers_online) do
      {:ok, {normal, dirty, online}}
    end
  end

  defp coupled_before(_node, _flag), do: {:ok, nil}

  # OTP 27-29 erl_process.c uses integer percentages in this order.
  # This predicts an observation only; it never authorizes an extra write.
  def coupled_count(normal, dirty, online, previous, requested) do
    total_percent = div(dirty * 100, normal)
    online_percent = div(requested * total_percent, previous)
    max(div(online * online_percent, 100), 1)
  end

  defp expected(:schedulers_online, value, old, {normal, dirty, online}) do
    [
      schedulers_online: value,
      dirty_cpu_schedulers_online: coupled_count(normal, dirty, online, old, value)
    ]
  end

  defp expected(flag, value, _old, _coupled), do: [{flag, value}]

  defp await_counts(_node, _expected, 0), do: {:error, :scheduler_change_unconfirmed}

  defp await_counts(node, expected, attempts) do
    observed = Enum.map(expected, fn {flag, value} -> {info(node, flag), value} end)

    cond do
      Enum.any?(observed, fn {result, _} -> match?({:error, _}, result) end) ->
        {:error, :scheduler_change_unconfirmed}

      Enum.all?(observed, fn {result, value} -> result == {:ok, value} end) ->
        :ok

      true ->
        Process.sleep(10)
        await_counts(node, expected, attempts - 1)
    end
  end

  defp info(node, flag), do: Remote.call_raw(node, :erlang, :system_info, [flag])
end
