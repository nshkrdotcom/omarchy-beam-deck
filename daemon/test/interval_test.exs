defmodule BeamDeck.IntervalTest do
  use ExUnit.Case, async: true
  alias BeamDeck.Diagnostics.{Interval, StackSample}

  defp sample(rows, mono \\ 1000, extra \\ %{}) do
    Map.merge(
      %{
        node: "fixture@host",
        creation: 1,
        mono_ms: mono,
        at_ms: 10_000 + mono,
        rows: rows,
        scanned: length(rows),
        total: length(rows),
        partial: false
      },
      extra
    )
  end

  defp process(pid, reds, mem, queue) do
    %{pid: pid, name: "worker", reductions: reds, memory_bytes: mem, mailbox: queue}
  end

  test "interval ranks actual work, retains signed gauges and excludes arbitrary fields" do
    a = sample([process("<0.1.0>", 100_000, 500, 9), process("<0.2.0>", 1, 20, 0)])

    b =
      sample(
        [
          process("<0.1.0>", 100_010, 300, 4),
          Map.put(process("<0.2.0>", 2001, 120, 5), :arbitrary, "WINDOW_CANARY")
        ],
        3000
      )

    assert {:ok, r} = Interval.compare("process_window", a, b)
    assert r.span_ms == 2000
    assert hd(r.rows).pid == "<0.2.0>"
    assert hd(r.rows).reductions_per_second == 1000.0
    first = Enum.find(r.rows, &(&1.pid == "<0.1.0>"))
    assert first.memory_delta_bytes == -200
    assert first.mailbox_delta == -5
    refute BeamDeck.Json.encode(r) =~ "WINDOW_CANARY"
  end

  test "unmatched, missing, reset and partial measurements are not fabricated zero rates" do
    a = sample([process("<0.1.0>", 100, 50, 3), process("<0.2.0>", 8, 8, 8)])

    b =
      sample([process("<0.1.0>", 20, nil, nil), process("<0.3.0>", 50, 30, 3)], 2000, %{
        partial: true
      })

    assert {:ok, r} = Interval.compare("process_window", a, b)
    assert r.partial
    assert r.matched == 1 && r.first_only == 1 && r.last_only == 1
    assert Enum.all?(r.rows, &is_nil(&1.reductions_per_second))
    row = Enum.find(r.rows, &(&1.pid == "<0.1.0>"))
    assert row.counter_reset
    assert is_nil(row.memory_delta_bytes)
    assert is_nil(row.mailbox_delta)
    assert Enum.find(r.rows, &(&1.pid == "<0.2.0>")).status == "not_reobserved"
  end

  test "unknown incarnation, node mismatch and nonpositive sample spans reject continuity" do
    for extra <- [%{creation: 2}, %{creation: nil}, %{node: "other@host"}] do
      assert {:error, :incomparable_identity} =
               Interval.compare("process_window", sample([]), sample([], 2000, extra))
    end

    for ms <- [1000, 999] do
      assert {:error, :invalid_sample_span} =
               Interval.compare("process_window", sample([]), sample([], ms))
    end
  end

  test "named ETS replacement uses underlying ID, not its reusable name" do
    row = %{
      id: "same_name",
      identity: "table-1",
      name: "same_name",
      owner: "<0.1.0>",
      memory_bytes: 100,
      size: 10
    }

    a = sample([row])
    b = sample([%{row | identity: "table-2", memory_bytes: 200, size: 20}], 2000)
    assert {:ok, r} = Interval.compare("ets_window", a, b)
    assert r.matched == 0 && r.first_only == 1 && r.last_only == 1
    assert Enum.all?(r.rows, &is_nil(&1.memory_delta_bytes))

    assert {:ok, same} =
             Interval.compare(
               "ets_window",
               a,
               sample([%{row | memory_bytes: 120, size: 12}], 2000)
             )

    assert hd(same.rows).size_delta == 2
    assert hd(same.rows).memory_delta_bytes == 20
  end

  test "ranked results and stack summaries are bounded and never retain stack arguments" do
    rows = for i <- 1..200, do: process("<0.#{i}.0>", i, i, i)
    assert {:ok, r} = Interval.compare("process_window", sample(rows), sample(rows, 2000))
    assert length(r.rows) == 60
    assert r.omitted_rows == 140
    frames = [{:fixture, :loop, ["STACK_ARGUMENT_CANARY"], [file: ~c"SECRET_PATH", line: 12]}]

    entries =
      for i <- 1..20,
          do: %{
            mono_ms: i * 250,
            status: :waiting,
            stack: frames,
            memory_bytes: i,
            mailbox: 0,
            reductions: i
          }

    r = StackSample.summarize(entries, 20)
    assert r.samples == 20
    assert hd(r.stacks).count == 20
    assert r.statuses == [%{status: "waiting", count: 20}]
    encoded = BeamDeck.Json.encode(r)
    refute encoded =~ "STACK_ARGUMENT_CANARY"
    refute encoded =~ "SECRET_PATH"
    assert hd(hd(r.stacks).frames).arity == 1
  end
end
