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

  test "new jobs require request IDs and reject malformed targets without atom creation" do
    assert {:error, :invalid_arguments} =
             Protocol.parse(~s({"cmd":"inspect_ets","node":"app@host"}))

    assert {:ok, "inspect_process", _} =
             Protocol.parse(
               ~s({"cmd":"inspect_process","request_id":"ui-1","node":"app@host","pid":"<0.1.0>"})
             )

    assert {:error, :invalid_arguments} =
             Protocol.parse(
               ~s({"cmd":"inspect_process","request_id":"ui-1","node":"app@host","pid":"#PID<0.1.0>"})
             )

    assert {:error, :invalid_arguments} =
             Protocol.parse(~s({"cmd":"budget_trial_begin","request_id":"ui-2","rows":[]}))
  end

  test "historical view commands are typed and exact inspection identities are validated" do
    assert {:ok, "view", _} = BeamDeck.Protocol.parse(~s({"cmd":"view","historical":true}))

    assert {:error, :invalid_arguments} =
             BeamDeck.Protocol.parse(~s({"cmd":"view","historical":"false"}))

    assert {:error, :invalid_arguments} =
             BeamDeck.Protocol.parse(
               ~s({"cmd":"inspect_process","request_id":"p1","node":"fixture@host","pid":"<0.1.0>","expected_creation":"bad"})
             )
  end

  test "interval commands require exact incarnation and an allowlisted duration" do
    for cmd <- ["process_window", "ets_window", "sample_process"] do
      args = %{
        "cmd" => cmd,
        "request_id" => "survey-1",
        "node" => "fixture@host",
        "pid" => "<0.1.0>",
        "expected_creation" => 1,
        "duration_ms" => 1000
      }

      assert {:ok, ^cmd, _} = Protocol.parse(BeamDeck.Json.encode(args))

      for bad <- [
            Map.delete(args, "expected_creation"),
            Map.put(args, "duration_ms", 60_000),
            Map.put(args, "node", "bad")
          ] do
        assert {:error, :invalid_arguments} = Protocol.parse(BeamDeck.Json.encode(bad))
      end
    end

    assert {:error, :invalid_arguments} =
             Protocol.parse(~s({"cmd":"cancel_job","request_id":"bad id"}))
  end
end
