defmodule BeamDeck.DiscoveryTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Discovery

  test "explicit metadata is directional and validates expected node names" do
    config = %{
      "nodes" => [
        %{
          "name" => "api@ws",
          "required" => true,
          "expected_peers" => ["worker@omen", "not a node", "worker@omen"]
        }
      ]
    }

    assert Discovery.metadata(config, :api@ws) == %{
             configured: true,
             required: true,
             expected_peers: ["worker@omen"]
           }

    assert Discovery.metadata(config, :other@ws) == %{
             configured: false,
             required: false,
             expected_peers: []
           }
  end

  test "only numeric internal helper names are excluded from discovery" do
    config = %{
      "nodes" => [
        %{"name" => "beam_deck_58391@host"},
        %{"name" => "beam_deck_shell_58391@host"},
        %{"name" => "beam_deck_demo@host"},
        %{"name" => "beam_deck_api@host"}
      ]
    }

    candidates = Discovery.candidates(config)

    refute :beam_deck_58391@host in candidates
    refute :beam_deck_shell_58391@host in candidates
    assert :beam_deck_demo@host in candidates
    assert :beam_deck_api@host in candidates
  end
end
