defmodule BeamDeck.JsonTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Json

  test "round trips nested protocol data" do
    value = %{
      "type" => "snapshot",
      "ok" => true,
      "nothing" => nil,
      "number" => 42,
      "float" => 1.25,
      "text" => "quote \" slash \\ newline\n snowman ☃",
      "list" => [1, "two", false]
    }

    assert {:ok, ^value} = value |> Json.encode() |> Json.decode()
  end

  test "rejects trailing and malformed data" do
    assert {:error, :trailing_data} = Json.decode("{} nope")
    assert {:error, :bad_array} = Json.decode("[1,")
    assert {:error, :bad_object} = Json.decode("{nope}")
  end

  test "encodes atom keys and BEAM identifiers safely" do
    encoded = Json.encode(%{status: :ok, self: self()})
    assert {:ok, decoded} = Json.decode(encoded)
    assert decoded["status"] == "ok"
    assert is_binary(decoded["self"])
  end
end
