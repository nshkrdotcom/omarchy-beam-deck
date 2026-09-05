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
end
