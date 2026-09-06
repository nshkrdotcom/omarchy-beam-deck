defmodule BeamDeck.WatchlistTest do
  use ExUnit.Case, async: true
  import Bitwise
  alias BeamDeck.{Config, Json, Watchlist}

  setup do
    dir = Path.join(System.tmp_dir!(), "bd-pins-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, watchlist_path: Path.join(dir, "watchlist.json")}
  end

  test "normalization is stable, drops PID and rejects arbitrary unobserved names", c do
    proposed = %{
      "kind" => "registered_process",
      "node" => "app@host",
      "name" => "Worker",
      "pid" => "<0.99.0>"
    }

    assert {:ok, pin} = Watchlist.normalize(proposed)
    assert {:ok, ^pin} = Watchlist.normalize(pin)
    refute Map.has_key?(pin, "pid")

    assert {:error, :pin_not_observed_or_limit} =
             Watchlist.add([], proposed, [], Config.defaults(), c.watchlist_path)
  end

  test "atomic save/load has private modes and no PID dependency", c do
    proposed = %{"kind" => "node", "node" => "app@host", "label" => "API"}

    assert {:ok, entries} =
             Watchlist.add(
               [],
               proposed,
               [%{name: "app@host"}],
               Config.defaults(),
               c.watchlist_path
             )

    assert {^entries, nil} = Watchlist.load(c.watchlist_path)
    assert (File.stat!(c.watchlist_path).mode &&& 0o777) == 0o600
    assert (File.stat!(c.dir).mode &&& 0o777) == 0o700

    assert {:ok, ^entries} =
             Watchlist.add(
               entries,
               proposed,
               [%{name: "app@host"}],
               Map.put(Config.defaults(), "watchlist_max_entries", 1),
               c.watchlist_path
             )

    assert {:ok, []} = Watchlist.remove(entries, hd(entries)["id"], c.watchlist_path)
  end

  test "malformed or symlinked persistence fails closed and preserves the target", c do
    File.write!(c.watchlist_path, "not JSON")
    assert {[], "invalid_watchlist"} = Watchlist.load(c.watchlist_path)
    target = Path.join(c.dir, "target")
    File.write!(target, "untouched")
    File.rm!(c.watchlist_path)
    File.ln_s!(target, c.watchlist_path)
    assert {[], "invalid_watchlist"} = Watchlist.load(c.watchlist_path)
    refute Watchlist.save([], c.watchlist_path) == :ok
    assert File.read!(target) == "untouched"
  end

  test "loaded process pins cannot exceed the hard per-node ceiling", c do
    entries =
      for n <- 1..65,
          do: %{"kind" => "registered_process", "node" => "app@host", "name" => "W#{n}"}

    File.write!(c.watchlist_path, Json.encode(%{schema: 1, entries: entries}))
    assert {[], "watchlist_limit"} = Watchlist.load(c.watchlist_path)
  end

  test "filesystem failure never reports that a pin was saved", c do
    File.mkdir_p!(c.watchlist_path)

    assert {:error, :watchlist_write_failed} =
             Watchlist.add(
               [],
               %{"kind" => "node", "node" => "app@host"},
               [%{name: "app@host"}],
               Config.defaults(),
               c.watchlist_path
             )
  end
end
