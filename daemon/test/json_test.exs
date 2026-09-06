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
    assert {:error, :invalid_json} = Json.decode("[1,")
    assert {:error, :invalid_json} = Json.decode("{nope}")
  end

  test "encodes atom keys and BEAM identifiers safely" do
    encoded = Json.encode(%{status: :ok, self: self()})
    assert {:ok, decoded} = Json.decode(encoded)
    assert decoded["status"] == "ok"
    assert is_binary(decoded["self"])
  end

  test "OTP parser rejects duplicate keys, trailing commas and oversized/deep input" do
    for value <- [~s({"a":1,"a":2}), "[1,]", ~s({"a":1,}), ~s("\\uD800")] do
      assert {:error, _} = Json.decode(value)
    end

    assert {:error, :json_too_deep} =
             Json.decode(String.duplicate("[", 33) <> "0" <> String.duplicate("]", 33))

    assert {:error, :json_too_large} = Json.decode(String.duplicate("x", 1_048_577))
    assert {:ok, text} = Json.decode(~s("\\uD83D\\uDE80"))
    assert text == <<0x1F680::utf8>>
  end
end
