defmodule BeamDeck.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam_deck,
      version: "1.1.0",
      elixir: ">= 1.18.0",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      erlc_paths: ["src"],
      deps: deps()
    ]
  end

  def application do
    base = [extra_applications: [:logger, :runtime_tools, :crypto]]
    if Mix.env() == :test, do: base, else: Keyword.put(base, :mod, {BeamDeck.Application, []})
  end

  defp deps do
    if Mix.env() == :prod do
      []
    else
      [
        {:dialyxir, "~> 1.4.7", only: [:dev], runtime: false},
        {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false}
      ]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
