defmodule BeamDeck.TestPeer do
  @moduledoc false
  def start do
    epmd = System.find_executable("epmd") || raise "epmd executable is required"
    {_text, 0} = System.cmd(epmd, ["-daemon"], stderr_to_stdout: true)

    unless Node.alive?() do
      {:ok, _} = :net_kernel.start([:beam_deck_test_controller, :shortnames])
    end

    :erlang.set_cookie(Node.self(), :beam_deck_test_cookie)
    name = String.to_atom("bd_fixture_#{System.unique_integer([:positive])}")

    {:ok, peer, node} =
      :peer.start(%{
        name: name,
        wait_boot: 15_000,
        args: [
          ~c"+S",
          ~c"3:3",
          ~c"+SDcpu",
          ~c"1:1",
          ~c"+SDio",
          ~c"1",
          ~c"-setcookie",
          ~c"beam_deck_test_cookie"
        ]
      })

    Enum.each(["bd_test_worker", "bd_test_sup"], fn name ->
      file = Path.expand("../fixtures/#{name}.erl", __DIR__)

      compiled =
        :compile.file(String.to_charlist(file), [:binary, :return_errors, :return_warnings])

      {module, binary} =
        case compiled do
          {:ok, module, binary} -> {module, binary}
          {:ok, module, binary, []} -> {module, binary}
          other -> raise "fixture compilation failed: #{inspect(other)}"
        end

      {:ok, {:module, ^module}} =
        BeamDeck.Remote.call_raw(node, :code, :load_binary, [
          module,
          String.to_charlist(file),
          binary
        ])
    end)

    {:ok, {:ok, _sup}} = BeamDeck.Remote.call_raw(node, :bd_test_sup, :start, [])
    {peer, node}
  end

  def stop(peer) do
    if Process.alive?(peer), do: :peer.stop(peer)
    :ok
  catch
    :exit, _ -> :ok
  end

  def eventually(fun, attempts \\ 200)
  def eventually(_fun, 0), do: raise("condition did not become true before deadline")

  def eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(25)
          eventually(fun, attempts - 1)
        )
  end
end
