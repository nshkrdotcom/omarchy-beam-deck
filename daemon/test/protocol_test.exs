defmodule BeamDeck.ProtocolTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Protocol

  test "parses commands while preserving arguments" do
    assert {:ok, "set_schedulers", args} =
             Protocol.parse(~s({"cmd":"set_schedulers","node":"app@host","value":4}) <> "\n")

    assert args["node"] == "app@host"
    assert args["value"] == 4
  end

  test "requires a string command" do
    assert {:error, :missing_cmd} = Protocol.parse("{}")
    assert {:error, :missing_cmd} = Protocol.parse(~s({"cmd":12}))
  end
end
