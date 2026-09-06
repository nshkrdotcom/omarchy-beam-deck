defmodule BeamDeck.RedactionTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Redaction

  test "recursively removes prohibited categories and exact secrets" do
    data = %{
      text: "cookie=abc secret-value",
      messages: ["never"],
      rows: [%{dictionary: [{:password, "never"}], ok: "secret-value"}]
    }

    clean = Redaction.sanitize(data, secrets: ["secret-value"])
    refute Map.has_key?(clean, :messages)
    refute Map.has_key?(hd(clean.rows), :dictionary)
    refute BeamDeck.Json.encode(clean) =~ "secret-value"
    refute clean.text =~ "abc"
  end

  test "handles invalid UTF8, controls, oversized strings and nested structures" do
    assert is_binary(Redaction.text(<<255, 0, 65>>, 8))
    assert byte_size(Redaction.text(String.duplicate("x", 4_000), 128)) <= 128
    assert Redaction.sanitize(List.duplicate(%{ok: 1}, 1_000)) |> length() == 256
    nested = Enum.reduce(1..30, "end", fn _, acc -> %{next: acc} end)
    assert BeamDeck.Json.encode(Redaction.sanitize(nested)) =~ "TRUNCATED"
  end

  test "export removes host paths, commands and raw configuration" do
    out =
      Redaction.export(%{cwd: "/private", argv: ["secret"], config_path: "/home/u", status: "ok"})

    assert out == %{status: "ok"}
  end

  test "sensitive concepts and key/value lists are scrubbed without redacting harmless counts" do
    data = %{
      api_key: "never",
      privateKey: "never",
      passwd: "never",
      access_token: "never",
      key_count: 4,
      entries: [authorization: "never", credentials: "never", size: 3]
    }

    clean = Redaction.sanitize(data)
    assert clean.key_count == 4
    refute BeamDeck.Json.encode(clean) =~ "never"
  end

  test "exact secrets are replaced before string truncation including binary keys" do
    secret = String.duplicate("s", 1200)
    clean = Redaction.sanitize(%{secret => "x", "text" => "prefix " <> secret}, secrets: [secret])
    refute BeamDeck.Json.encode(clean) =~ String.duplicate("s", 50)
  end

  test "an exact configured secret cannot escape through atom keys or values" do
    sanitized =
      BeamDeck.Redaction.sanitize(%{test_secret_atom: :test_secret_atom},
        secrets: ["test_secret_atom"]
      )

    refute BeamDeck.Json.encode(sanitized) =~ "test_secret_atom"
  end
end
