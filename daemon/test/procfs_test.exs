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
end
