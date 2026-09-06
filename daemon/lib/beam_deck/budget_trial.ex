defmodule BeamDeck.BudgetTrial do
  @moduledoc "Single owner for scheduler mutations, leases, original values and conditional rollback."
  use GenServer
  alias BeamDeck.{Discovery, Remote}
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def panel(open, epoch, owner), do: GenServer.cast(__MODULE__, {:panel, open, epoch, owner})

  def begin(rows, budget, nodes, epoch, lease),
    do: GenServer.call(__MODULE__, {:begin, rows, budget, nodes, epoch, lease}, 30_000)

  def keep(id), do: GenServer.call(__MODULE__, {:keep, id})
  def revert(id), do: GenServer.call(__MODULE__, {:revert, id})
  def status, do: GenServer.call(__MODULE__, :status)
  def request(owner, id, command), do: GenServer.cast(__MODULE__, {:request, owner, id, command})
  def set(name, flag, value), do: GenServer.call(__MODULE__, {:set, name, flag, value}, 5_000)
  def restore(name), do: GenServer.call(__MODULE__, {:restore, name}, 10_000)

  def validate(rows, budget, nodes) do
    normalized =
      Enum.map(rows, fn row ->
        %{node: row["node"], current: row["current"], suggested: row["suggested"]}
      end)

    eligible =
      Enum.all?(normalized, fn row ->
        node = Enum.find(nodes, &(&1.name == row.node))

        not is_nil(node) and node[:attached] == true and node[:local] == true and
          node[:schedulers_online] == row.current and
          is_integer(row.suggested) and row.suggested >= 1 and row.suggested <= row.current
      end)

    if eligible and length(rows) in 1..16 and
         length(Enum.uniq_by(normalized, & &1.node)) == length(rows) and
         Enum.sort_by(normalized, & &1.node) == Enum.sort_by(budget, & &1.node) do
      {:ok, normalized}
    else
      {:error, :stale_or_unsafe_budget}
    end
  end

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)
    {:ok, %{panel: false, epoch: 0, owner: nil, monitor: nil, trial: nil, originals: %{}}}
  end

  @impl true
  def handle_cast({:request, owner, id, {action, _trial_id} = command}, state)
      when action in [:keep, :revert] do
    {:reply, result, next} = handle_call(command, nil, state)
    base = %{type: "job", kind: "budget_trial_#{action}", request_id: id}

    message =
      case result do
        {:ok, data} -> Map.merge(base, %{status: "complete", result: data})
        {:error, error} -> Map.merge(base, %{status: "error", error: error})
      end

    send(owner, {:diagnostic, message})
    {:noreply, next}
  end

  def handle_cast({:panel, open, epoch, owner}, state) do
    if state.monitor, do: Process.demonitor(state.monitor, [:flush])
    next = %{state | panel: open, epoch: epoch, owner: owner, monitor: Process.monitor(owner)}
    {:noreply, if(open, do: next, else: start_rollback(next, :panel_closed))}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, public(state.trial), state}

  def handle_call({:begin, rows, budget, nodes, epoch, lease}, from, state) do
    with true <- state.panel and state.epoch == epoch and not busy?(state),
         {:ok, accepted} <- validate(rows, budget, nodes) do
      id = "trial-#{System.unique_integer([:positive, :monotonic])}"
      lease = min(max(lease, 5_000), 30_000)
      timer = Process.send_after(self(), {:expire, id}, lease)

      targets =
        Map.new(nodes, fn node ->
          {node.name, %{creation: node[:creation], os_pid: to_string(node[:os_pid] || "")}}
        end)

      trial = %{
        trial_id: id,
        targets: targets,
        status: "applying",
        rows: accepted,
        pending: accepted,
        journal: [],
        failures: [],
        reason: nil,
        from: from,
        timer: timer,
        remaining: [],
        started_at_ms: System.system_time(:millisecond),
        before_metrics:
          Enum.map(
            nodes,
            &Map.take(&1, [:name, :run_queue, :processes, :memory, :schedulers_online])
          ),
        deadline: System.monotonic_time(:millisecond) + lease,
        expires_at_ms: System.system_time(:millisecond) + lease
      }

      send(self(), {:step, id})
      next = %{state | trial: trial}
      notify(next)
      {:noreply, next}
    else
      false -> {:reply, {:error, :trial_unavailable_or_panel_closed}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:keep, id}, _from, %{trial: %{trial_id: id, status: "active"} = t} = state) do
    if state.panel and System.monotonic_time(:millisecond) < t.deadline do
      Process.cancel_timer(t.timer)
      next = %{state | trial: %{t | status: "kept"}}
      notify(next)
      {:reply, {:ok, public(next.trial)}, next}
    else
      next = start_rollback(state, :expired)
      {:reply, {:error, :lease_expired}, next}
    end
  end

  def handle_call({:keep, _id}, _from, state), do: {:reply, {:error, :trial_not_active}, state}

  def handle_call({:revert, id}, _from, %{trial: %{trial_id: id}} = state) do
    next = start_rollback(state, :requested)
    {:reply, {:ok, public(next.trial)}, next}
  end

  def handle_call({:revert, _id}, _from, state), do: {:reply, {:error, :trial_not_found}, state}

  def handle_call({:set, name, flag, value}, _from, state) do
    Process.put(:beam_deck_rpc_deadline, System.monotonic_time(:millisecond) + 1_500)

    if busy?(state) do
      {:reply, {:error, :trial_active}, state}
    else
      with {:ok, node} <- Discovery.existing_node(name),
           {:ok, identity} <- Remote.identity(node),
           {:ok, current} when is_integer(current) <-
             Remote.call_raw(node, :erlang, :system_info, [flag]) do
        entry = %{node: name, flag: flag, original: current, applied: value, identity: identity}
        next = %{state | originals: remember(state.originals, entry)}

        case Remote.set_flag(node, flag, value) do
          {:ok, old} ->
            corrected = %{entry | original: old}

            {:reply, {:ok, %{previous: old, applied: value}},
             %{next | originals: remember(state.originals, corrected)}}

          _ ->
            {:reply, {:error, :mutation_outcome_uncertain_use_restore}, next}
        end
      else
        _ -> {:reply, {:error, :mutation_failed}, state}
      end
    end
  end

  def handle_call({:restore, name}, _from, state) do
    if busy?(state) do
      {:reply, {:error, :trial_active}, state}
    else
      {originals, failures} = restore_entries(state.originals, name)

      result =
        if failures == [],
          do: {:ok, %{restored: true}},
          else: {:ok, %{restored: false, failures: failures}}

      {:reply, result, %{state | originals: originals}}
    end
  end

  @impl true
  def handle_info({:step, id}, %{trial: %{trial_id: id, status: "applying"} = trial} = state) do
    cond do
      not state.panel or System.monotonic_time(:millisecond) >= trial.deadline ->
        {:noreply, start_rollback(state, :lease_expired)}

      trial.pending == [] ->
        next = %{state | trial: %{trial | status: "active", from: nil}}
        GenServer.reply(trial.from, {:ok, public(next.trial)})
        notify(next)
        {:noreply, next}

      true ->
        [row | rest] = trial.pending
        next = %{state | trial: %{trial | pending: rest}}
        {:noreply, apply_row(next, row)}
    end
  end

  def handle_info({:step, id}, %{trial: %{trial_id: id, status: "reverting"} = trial} = state) do
    case trial.remaining do
      [] ->
        status = if trial.failures == [], do: "reverted", else: "rollback_failed"
        if trial.from, do: GenServer.reply(trial.from, {:error, :trial_not_applied})
        next = %{state | trial: %{trial | status: status, from: nil}}
        notify(next)
        {:noreply, next}

      [entry | rest] ->
        case restore_entry(entry) do
          :ok ->
            originals = after_rollback(state.originals, entry)
            next = %{state | originals: originals, trial: %{trial | remaining: rest}}
            send(self(), {:step, id})
            {:noreply, next}

          {:error, reason} ->
            failure = %{
              node: entry.node,
              error: reason,
              original: entry.original,
              applied: entry.applied
            }

            next = %{
              state
              | trial: %{trial | remaining: rest, failures: [failure | trial.failures]}
            }

            send(self(), {:step, id})
            {:noreply, next}
        end
    end
  end

  def handle_info({:expire, id}, %{trial: %{trial_id: id}} = state),
    do: {:noreply, start_rollback(state, :lease_expired)}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    send(self(), :restore_session)
    {:noreply, start_rollback(%{state | panel: false, owner: nil, monitor: nil}, :owner_down)}
  end

  def handle_info(:restore_session, state) do
    if busy?(state) and state.trial.status != "rollback_failed" do
      Process.send_after(self(), :restore_session, 100)
      {:noreply, state}
    else
      {originals, _failures} = restore_entries(state.originals, :all)
      {:noreply, %{state | originals: originals}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    restore_entries(state.originals, :all)
    :ok
  end

  defp apply_row(state, %{current: value, suggested: value}) do
    send(self(), {:step, state.trial.trial_id})
    state
  end

  defp apply_row(state, row) do
    Process.put(:beam_deck_rpc_deadline, System.monotonic_time(:millisecond) + 1_500)

    with {:ok, node} <- Discovery.existing_node(row.node),
         {:ok, identity} <- Remote.identity(node),
         {:ok, current} <- Remote.call_raw(node, :erlang, :system_info, [:schedulers_online]),
         true <- current == row.current and identity == state.trial.targets[row.node] do
      entry = %{
        node: row.node,
        flag: :schedulers_online,
        original: current,
        applied: row.suggested,
        identity: identity
      }

      # Journal BEFORE requesting a side effect: an RPC timeout is not proof of no mutation.
      next = %{
        state
        | trial: %{state.trial | journal: [entry | state.trial.journal]},
          originals: remember(state.originals, entry)
      }

      case Remote.set_flag(node, :schedulers_online, row.suggested) do
        {:ok, ^current} ->
          send(self(), {:step, state.trial.trial_id})
          notify(next)
          next

        {:ok, actual_old} ->
          corrected = %{entry | original: actual_old}
          journal = [corrected | tl(next.trial.journal)]

          start_rollback(
            %{
              next
              | originals: remember(state.originals, corrected),
                trial: %{next.trial | journal: journal}
            },
            :concurrent_change
          )

        _ ->
          start_rollback(next, :apply_failed)
      end
    else
      _ -> start_rollback(state, :stale_target)
    end
  end

  defp start_rollback(%{trial: nil} = state, _reason), do: state

  defp start_rollback(%{trial: %{status: status}} = state, _reason)
       when status in ["kept", "reverted", "reverting"], do: state

  defp start_rollback(state, reason) do
    t = state.trial
    Process.cancel_timer(t.timer)

    next = %{
      state
      | trial: %{t | status: "reverting", reason: reason, remaining: t.journal, failures: []}
    }

    send(self(), {:step, t.trial_id})
    notify(next)
    next
  end

  defp busy?(%{trial: nil}), do: false

  defp busy?(state),
    do: state.trial.status in ["applying", "active", "reverting", "rollback_failed"]

  defp remember(originals, entry) do
    key = {entry.node, entry.flag}

    case originals[key] do
      %{identity: identity} = old when identity == entry.identity ->
        Map.put(originals, key, %{entry | original: old.original})

      _ ->
        Map.put(originals, key, entry)
    end
  end

  defp after_rollback(originals, entry) do
    key = {entry.node, entry.flag}

    case originals[key] do
      nil ->
        originals

      old ->
        if old.original == entry.original,
          do: Map.delete(originals, key),
          else: Map.put(originals, key, %{old | applied: entry.original})
    end
  end

  defp restore_entries(originals, name) do
    Enum.reduce(originals, {originals, []}, fn {key, entry}, {acc, failures} ->
      if name == :all or entry.node == name do
        case restore_entry(entry) do
          :ok ->
            {Map.delete(acc, key), failures}

          {:error, error} ->
            {acc, [%{node: entry.node, flag: entry.flag, error: error} | failures]}
        end
      else
        {acc, failures}
      end
    end)
  end

  defp restore_entry(entry) do
    Process.put(:beam_deck_rpc_deadline, System.monotonic_time(:millisecond) + 1_500)

    with {:ok, node} <- Discovery.existing_node(entry.node),
         {:ok, identity} <- Remote.identity(node),
         true <- identity == entry.identity,
         {:ok, current} <- Remote.call_raw(node, :erlang, :system_info, [entry.flag]) do
      cond do
        current == entry.original ->
          :ok

        current != entry.applied ->
          {:error, :externally_changed}

        true ->
          case Remote.set_flag(node, entry.flag, entry.original) do
            {:ok, _} ->
              if Remote.call(node, :erlang, :system_info, [entry.flag], nil) == entry.original,
                do: :ok,
                else: {:error, :restore_unconfirmed}

            _ ->
              {:error, :restore_failed}
          end
      end
    else
      false -> {:error, :vm_identity_changed}
      _ -> {:error, :node_unavailable}
    end
  end

  defp public(nil), do: nil

  defp public(trial) do
    Map.take(trial, [
      :trial_id,
      :status,
      :rows,
      :failures,
      :reason,
      :started_at_ms,
      :expires_at_ms,
      :before_metrics
    ])
    |> Map.put(:remaining_ms, max(trial.deadline - System.monotonic_time(:millisecond), 0))
  end

  defp notify(%{owner: nil}), do: :ok
  defp notify(state), do: send(state.owner, {:budget_trial, public(state.trial)})
end
