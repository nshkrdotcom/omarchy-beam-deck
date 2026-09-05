defmodule BeamDeck.Protocol do
  @moduledoc false
  alias BeamDeck.Json

  def parse(line) do
    case Json.decode(String.trim(line)) do
      {:ok, %{"cmd" => cmd} = map} when is_binary(cmd) -> {:ok, cmd, map}
      {:ok, _} -> {:error, :missing_cmd}
      error -> error
    end
  end
end
