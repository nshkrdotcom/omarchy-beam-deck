defmodule BeamDeck.InputTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Input

  test "split lines and oversized input preserve framing and bounded memory" do
    {state, []} = Input.feed({"", false}, "{\"cmd\":")
    {_state, [{:line, line}]} = Input.feed(state, "\"refresh\"}\n")
    assert line == "{\"cmd\":\"refresh\"}"
    {state, messages} = Input.feed({"", false}, String.duplicate("x", 16_385))
    assert messages == [{:error, :command_too_large}]
    assert {"", true} == state
    {_state, [{:line, "{}"}]} = Input.feed(state, "discarded\n{}\n")
  end
end
