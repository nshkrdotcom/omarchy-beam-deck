defmodule BeamDeck.OutputTest do
  use ExUnit.Case, async: false

  alias BeamDeck.Output

  test "configured protocol transport fails closed when it cannot be opened" do
    previous = System.get_env("BEAM_DECK_PROTOCOL_PATH")

    on_exit(fn ->
      if previous do
        System.put_env("BEAM_DECK_PROTOCOL_PATH", previous)
      else
        System.delete_env("BEAM_DECK_PROTOCOL_PATH")
      end
    end)

    missing =
      Path.join([
        System.tmp_dir!(),
        "beam-deck-output-#{System.unique_integer([:positive])}",
        "missing",
        "protocol"
      ])

    System.put_env("BEAM_DECK_PROTOCOL_PATH", missing)

    assert_raise RuntimeError, ~r/protocol output unavailable/, fn ->
      Output.init()
    end
  end
end
