defmodule BeamDeck.RemoteIntegrationTest do
  use ExUnit.Case
  @moduletag :integration

  alias BeamDeck.{DeepEvents, Remote}

  setup_all do
    ensure_epmd!()
    ensure_distribution!()

    :erlang.set_cookie(Node.self(), :beam_deck_test_cookie)

    case :peer.start(%{
           name: :beam_deck_test_target,
           args: [~c"-setcookie", ~c"beam_deck_test_cookie"]
         }) do
      {:ok, peer, node} ->
        on_exit(fn ->
          if Process.alive?(peer), do: :peer.stop(peer)
        end)

        {:ok, node: node}

      other ->
        flunk("could not start OTP peer: #{inspect(other)}")
    end
  end

  test "agentlessly inspects an actual peer VM and its processes", %{node: node} do
    assert {:ok, info} = Remote.inspect_node(node, processes: true, max_process_scan: 100_000)
    assert info.attached
    assert info.processes > 0
    assert info.process_limit >= info.processes
    assert info.schedulers >= info.schedulers_online
    assert is_list(info.hot_processes)
    assert is_list(info.registered_processes)
    assert info.os_pid > 0
    assert is_map(info.memory)
  end

  test "scheduler mutation is live and reversible", %{node: node} do
    original = Remote.call(node, :erlang, :system_info, [:schedulers_online], 1)
    target = min(original, 1)
    assert {:ok, ^original} = Remote.set_flag(node, :schedulers_online, target)
    assert Remote.call(node, :erlang, :system_info, [:schedulers_online], 0) == target
    assert {:ok, ^target} = Remote.set_flag(node, :schedulers_online, original)
  end

  test "OTP 28+ deep-event probe can be loaded and cleanly removed", %{node: node} do
    otp =
      Remote.call(node, :erlang, :system_info, [:otp_release], ~c"0")
      |> to_string()
      |> String.to_integer()

    if otp >= 28 do
      assert {:ok, pid} = DeepEvents.start(node, BeamDeck.Config.defaults()["event_thresholds"])
      assert is_pid(pid)
      assert :ok = DeepEvents.stop(node, pid)
      assert Remote.call(node, :code, :is_loaded, [:nshkr_beam_deck_probe], false) == false
    end
  end

  defp ensure_epmd! do
    case System.find_executable("epmd") do
      nil ->
        flunk("epmd executable is not available")

      epmd ->
        ensure_epmd_running!(epmd)
    end
  end

  defp ensure_epmd_running!(epmd) do
    case System.cmd(epmd, ["-names"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      _ ->
        start_epmd!(epmd)
    end
  end

  defp start_epmd!(epmd) do
    case System.cmd(epmd, ["-daemon"], stderr_to_stdout: true) do
      {_output, 0} ->
        wait_for_epmd!(epmd, 20)

      {output, status} ->
        flunk("could not start epmd (status #{status}): #{String.trim(output)}")
    end
  end

  defp wait_for_epmd!(_epmd, 0), do: flunk("epmd did not become reachable")

  defp wait_for_epmd!(epmd, attempts) do
    case System.cmd(epmd, ["-names"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      _ ->
        Process.sleep(50)
        wait_for_epmd!(epmd, attempts - 1)
    end
  end

  defp ensure_distribution! do
    unless Node.alive?() do
      case :net_kernel.start([:beam_deck_test_controller, :shortnames]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        other -> flunk("could not start distributed test node: #{inspect(other)}")
      end
    end
  end
end
