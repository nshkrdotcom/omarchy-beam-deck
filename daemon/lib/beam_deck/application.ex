defmodule BeamDeck.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    :ok = BeamDeck.Output.init()
    children = [BeamDeck.Daemon, {Task, fn -> BeamDeck.Input.run() end}]
    Supervisor.start_link(children, strategy: :one_for_one, name: BeamDeck.Supervisor)
  end
end
