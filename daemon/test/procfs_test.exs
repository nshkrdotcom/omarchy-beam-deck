defmodule BeamDeck.ProcfsTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Procfs

  test "parses /proc stat even when comm contains spaces and parentheses" do
    stat = "123 (beam (dev) node) S 1 2 3 4 5 6 7 8 9 10 120 30 0 0 0 0 0"
    parsed = Procfs.parse_stat(stat)
    assert parsed.state == "S"
    assert parsed.utime == 120
    assert parsed.stime == 30
  end

  test "parses status and meminfo-shaped key/value data" do
    parsed = Procfs.parse_status("VmRSS:\t2048 kB\nThreads:\t17\nName:\tbeam.smp\n")
    assert parsed["VmRSS"] == "2048 kB"
    assert parsed["Threads"] == "17"
    assert parsed["Name"] == "beam.smp"
  end

  test "redacts distribution cookies from proc command lines" do
    argv = ["beam.smp", "-sname", "app", "-setcookie", "supersecret", "--cookie=other", "+S", "4"]

    assert Procfs.redact_argv(argv) == [
             "beam.smp",
             "-sname",
             "app",
             "-setcookie",
             "[REDACTED]",
             "--cookie=[REDACTED]",
             "+S",
             "4"
           ]
  end

  test "OS discovery omits arbitrary argv and internal remsh clients" do
    root = Path.join(System.tmp_dir!(), "bd-procfs-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    for {pid, name} <- [{"101", "app"}, {"102", "beam_deck_shell_555"}] do
      dir = Path.join(root, pid)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "comm"), "beam.smp")
      File.write!(Path.join(dir, "stat"), "#{pid} (beam) S 1 2 3 4 5 6 7 8 9 10 120 30 0 0 0 0 0")
      File.write!(Path.join(dir, "status"), "VmRSS: 2048 kB")

      File.write!(
        Path.join(dir, "cmdline"),
        Enum.join(
          [
            "beam.smp",
            "-sname",
            name,
            "-eval",
            "ARGV_SECRET_CANARY",
            "--token",
            "ARGV_SECRET_CANARY"
          ],
          <<0>>
        )
      )
    end

    snapshot = Procfs.snapshot(root)
    refute BeamDeck.Json.encode(snapshot) =~ "ARGV_SECRET_CANARY"
    assert Enum.map(snapshot.runtimes, & &1.pid) == [101]
    refute Map.has_key?(hd(snapshot.runtimes), :argv)
    refute Map.has_key?(hd(snapshot.runtimes), :command)
  end

  test "a localhost-looking name alone cannot enter the physical host budget" do
    host = %{runtimes: [%{pid: 10}]}

    rows = [
      %{name: "real@localhost", attached: true, local: true, os_pid: 10},
      %{name: "tunnel@localhost", attached: true, local: true, os_pid: 11},
      %{name: "remote@elsewhere", attached: true, local: false, os_pid: 10}
    ]

    assert Enum.map(Procfs.verify_local_nodes(host, rows), & &1.local) == [true, false, false]
  end
end
