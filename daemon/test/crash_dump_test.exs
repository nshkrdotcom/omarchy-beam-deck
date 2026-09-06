defmodule BeamDeck.CrashDumpTest do
  use ExUnit.Case, async: true
  alias BeamDeck.CrashDump

  test "header extraction never retains process, binary or environment sections" do
    text =
      "=erl_crash_dump:0.5\nSun Sep 6 02:00:00 2026\nSlogan: out of memory\nSystem version: Erlang/OTP 28\n=proc:<0.1.0>\nPassword: should-not-retain\n=binary:123\nsecret"

    result = CrashDump.parse_header(text)
    assert result.slogan == "out of memory"
    refute BeamDeck.Json.encode(result) =~ "secret"
    refute BeamDeck.Json.encode(result) =~ "Password"
  end

  test "PID reuse is a disappearance, not continuous life" do
    old = %{runtimes: [%{pid: 42, starttime: 10, cwd: "/tmp", node_name: nil}]}
    new = %{runtimes: [%{pid: 42, starttime: 20}]}
    assert [%{pid: 42}] = CrashDump.disappeared(old, new, 100)
  end

  test "real file matching reads only a bounded new regular-file prefix" do
    dir = Path.join(System.tmp_dir!(), "bd-crash-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, "erl_crash.dump")

    bytes =
      "=erl_crash_dump:0.5\nTimestamp\nSlogan: controlled test\n=scheduler:1\nCurrent Process: <0.9.0>\nCurrent Function: app:run/0\n=memory\nbinary: 1024\n=proc:<0.9.0>\n" <>
        String.duplicate("PRIVATE_REMAINDER", 2000)

    File.write!(path, bytes)

    opts =
      BeamDeck.Config.defaults()["diagnostics"]
      |> Map.put("crash_dump_read_bytes", 1024)
      |> Map.put("crash_dump_retry_ms", 1)

    exit = %{
      id: "test",
      at_ms: System.system_time(:millisecond),
      pid: 42,
      cwd: dir,
      previous_fingerprint: nil
    }

    result = CrashDump.triage(exit, opts)
    assert result.status == "matched"
    assert result.slogan == "controlled test"
    assert result.bytes_read == 1024
    assert result.prefix_only
    refute BeamDeck.Json.encode(result) =~ "PRIVATE_REMAINDER"

    assert CrashDump.triage(%{exit | previous_fingerprint: CrashDump.fingerprint(dir)}, opts).status ==
             "unchanged"

    assert CrashDump.triage(%{exit | at_ms: exit.at_ms + 60_000}, opts).status == "unmatched"
    File.rm!(path)
    other = Path.join(dir, "other")
    File.write!(other, bytes)
    File.ln_s!(other, path)
    assert CrashDump.triage(exit, opts).status == "missing"
  end

  test "a dump created during the bounded retry is found without traversing elsewhere" do
    dir = Path.join(System.tmp_dir!(), "bd-retry-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    exit = %{
      id: "retry",
      at_ms: System.system_time(:millisecond),
      pid: 42,
      cwd: dir,
      previous_fingerprint: nil
    }

    task =
      Task.async(fn ->
        Process.sleep(20)

        File.write!(
          Path.join(dir, "erl_crash.dump"),
          "=erl_crash_dump:0.5\nTest\nSlogan: delayed\n=end\n"
        )
      end)

    opts = Map.put(BeamDeck.Config.defaults()["diagnostics"], "crash_dump_retry_ms", 100)
    assert CrashDump.triage(exit, opts).status == "matched"
    Task.await(task)
  end
end
