defmodule BeamDeck.Diagnostics do
  @moduledoc "Bounded isolated work queue. Workers return metadata, never write protocol output."
  use GenServer
  def start_link(config), do: GenServer.start_link(__MODULE__, config, name: __MODULE__)
  def submit(owner, id, kind, node, fun, opts \\ []),
    do: GenServer.call(__MODULE__, {:submit, owner, id, kind, node, fun, opts})
  def cancel_interactive(owner), do: GenServer.cast(__MODULE__, {:cancel, owner})

  @impl true
  def init(config), do: {:ok, %{config: config, active: %{}, queue: [], owners: %{}, recent: []}}

  @impl true
  def handle_call({:submit, owner, id, kind, node, fun, opts}, _from, state) do
    ids = Enum.map(state.queue, & &1.id) ++ Enum.map(Map.values(state.active), & &1.id) ++ state.recent
    cond do
      not BeamDeck.Protocol.request_id?(id) -> {:reply, {:error, :invalid_request_id}, state}
      id in ids -> {:reply, {:error, :duplicate_request}, state}
      length(state.queue) >= state.config["max_queued_jobs"] -> {:reply, {:error, :queue_full}, state}
      true ->
        job = %{owner: owner, id: id, kind: kind, node: node, fun: fun,
          interactive: Keyword.get(opts, :interactive, true),
          timeout: min(max(Keyword.get(opts, :timeout, 5_000), 10), 30_000)}
        owners = if Map.has_key?(state.owners, owner), do: state.owners, else: Map.put(state.owners, owner, Process.monitor(owner))
        state = %{state | queue: state.queue ++ [job], owners: owners}
        {:reply, :ok, dispatch(state)}
    end
  end

  @impl true
  def handle_cast({:cancel, owner}, state), do: {:noreply, cancel(state, owner, true) |> dispatch()}

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.pop(state.active, ref) do
      {nil, _} -> {:noreply, state}
      {job, active} ->
        Process.demonitor(ref, [:flush])
        Process.cancel_timer(job.timer)
        deliver(job, result)
        {:noreply, finish(%{state | active: active}, job) |> dispatch()}
    end
  end
  def handle_info({:deadline, ref}, state) do
    case Map.pop(state.active, ref) do
      {nil, _} -> {:noreply, state}
      {job, active} ->
        Task.Supervisor.terminate_child(BeamDeck.DiagnosticTasks, job.task.pid)
        Process.demonitor(ref, [:flush])
        deliver(job, {:error, :timeout})
        {:noreply, finish(%{state | active: active}, job) |> dispatch()}
    end
  end
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.active, ref) do
      {nil, _} ->
        case Enum.find(state.owners, fn {_owner, monitor} -> monitor == ref end) do
          nil -> {:noreply, state}
          {owner, _} -> {:noreply, cancel(state, owner, false) |> dispatch()}
        end
      {job, active} ->
        Process.cancel_timer(job.timer)
        deliver(job, {:error, :worker_failed})
        {:noreply, finish(%{state | active: active}, job) |> dispatch()}
    end
  end
  def handle_info(_message, state), do: {:noreply, state}

  defp dispatch(state) do
    busy = Map.values(state.active) |> Enum.map(& &1.node) |> Enum.reject(&is_nil/1)
    index = Enum.find_index(state.queue, &(is_nil(&1.node) or &1.node not in busy))
    if map_size(state.active) < state.config["max_concurrent_jobs"] and not is_nil(index) do
      {job, queue} = List.pop_at(state.queue, index)
      task = Task.Supervisor.async_nolink(BeamDeck.DiagnosticTasks, fn ->
        try do
          job.fun.()
        rescue
          _ -> {:error, :diagnostic_failed}
        catch
          _, _ -> {:error, :diagnostic_failed}
        end
      end)
      timer = Process.send_after(self(), {:deadline, task.ref}, job.timeout)
      send(job.owner, {:diagnostic, %{type: "job", request_id: job.id, kind: job.kind, node: job.node, status: "started"}})
      active = Map.put(state.active, task.ref, Map.merge(job, %{task: task, timer: timer}))
      dispatch(%{state | active: active, queue: queue})
    else
      state
    end
  end

  defp cancel(state, owner, interactive_only) do
    matches = fn job -> job.owner == owner and (not interactive_only or job.interactive) end
    {removed, queue} = Enum.split_with(state.queue, matches)
    {killed, kept} = Enum.split_with(state.active, fn {_ref, job} -> matches.(job) end)
    Enum.each(killed, fn {ref, job} ->
      Task.Supervisor.terminate_child(BeamDeck.DiagnosticTasks, job.task.pid)
      Process.cancel_timer(job.timer)
      Process.demonitor(ref, [:flush])
    end)
    jobs = removed ++ Enum.map(killed, &elem(&1, 1))
    Enum.each(jobs, &deliver(&1, :canceled))
    Enum.reduce(jobs, %{state | queue: queue, active: Map.new(kept)}, &finish(&2, &1))
  end

  defp finish(state, job) do
    pending = state.queue ++ Map.values(state.active)
    owners = if Enum.any?(pending, &(&1.owner == job.owner)) do
      state.owners
    else
      if state.owners[job.owner], do: Process.demonitor(state.owners[job.owner], [:flush])
      Map.delete(state.owners, job.owner)
    end
    %{state | owners: owners, recent: Enum.take([job.id | state.recent], 128)}
  end
  defp deliver(job, result) do
    base = %{type: "job", request_id: job.id, kind: job.kind, node: job.node}
    message = case result do
      {:ok, data} -> Map.merge(base, %{status: "complete", result: data})
      {:error, code} when is_atom(code) -> Map.merge(base, %{status: "error", error: Atom.to_string(code)})
      :canceled -> Map.put(base, :status, "canceled")
      _ -> Map.merge(base, %{status: "error", error: "diagnostic_failed"})
    end
    send(job.owner, {:diagnostic, message})
  end
end
