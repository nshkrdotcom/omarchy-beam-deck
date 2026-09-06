defmodule BeamDeck.Application do
  @moduledoc false
  use Application
  @impl true
  def start(_type, _args) do
    :ok = BeamDeck.Output.init()

    config =
      case BeamDeck.Config.load() do
        {:ok, config, _} -> config
        {:error, _, defaults, _} -> defaults
      end

    children = [
      Supervisor.child_spec({Task.Supervisor, name: BeamDeck.DiagnosticTasks},
        id: :diagnostic_tasks
      ),
      Supervisor.child_spec({Task.Supervisor, name: BeamDeck.CollectionTasks},
        id: :collection_tasks
      ),
      {BeamDeck.Diagnostics, config["diagnostics"]},
      Supervisor.child_spec(BeamDeck.BudgetTrial, shutdown: 60_000),
      Supervisor.child_spec(BeamDeck.Daemon, shutdown: 30_000),
      Supervisor.child_spec({Task, fn -> BeamDeck.Input.run() end}, restart: :transient)
    ]

    Supervisor.start_link(children, strategy: :rest_for_one, name: BeamDeck.Supervisor)
  end
end
