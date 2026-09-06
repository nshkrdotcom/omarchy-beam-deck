defmodule BeamDeck.WatchlistTest do
  use ExUnit.Case, async: true
  import Bitwise
  alias BeamDeck.{Config, Json, Watchlist}
  setup do
    dir = Path.join(System.tmp_dir!(), "bd-pins-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, file: Path.join(dir, "watchlist.json")}
  end
  test "normalization is stable, drops PID and rejects arbitrary unobserved names", c do
    proposed = %{"kind" => "registered_process", "node" => "app@host", "name" => "Worker", "pid" => "<0.99.0>"}
    assert {:ok, pin} = Watchlist.normalize(proposed)
    assert {:ok, ^pin} = Watchlist.normalize(pin)
    refute Map.has_key?(pin, "pid")
    assert {:error, :pin_not_observed_or_limit} = Watchlist.add([], proposed, [], Config.defaults(), c.file)
  end
  test "atomic save/load has private modes and no PID dependency", c do
    proposed = %{"kind" => "node", "node" => "app@host", "label" => "API"}
    assert {:ok, entries} = Watchlist.add([], proposed, [%{name: "app@host"}], Config.defaults(), c.file)
    assert {^entries, nil} = Watchlist.load(c.file)
    assert (File.stat!(c.file).mode &&& 0o777) == 0o600
    assert (File.stat!(c.dir).mode &&& 0o777) == 0o700
    assert {:ok, ^entries} = Watchlist.add(entries, proposed, [%{name: "app@host"}], Map.put(Config.defaults(), "watchlist_max_entries", 1), c.file)
    assert {:ok, []} = Watchlist.remove(entries, hd(entries)["id"], c.file)
  end
  test "malformed or symlinked persistence fails closed and preserves the target", c do
    File.write!(c.file, "not JSON")
    assert {[], "invalid_watchlist"} = Watchlist.load(c.file)
    target = Path.join(c.dir, "target")
    File.write!(target, "untouched")
    File.rm!(c.file)
    File.ln_s!(target, c.file)
    assert {[], "invalid_watchlist"} = Watchlist.load(c.file)
    refute Watchlist.save([], c.file) == :ok
    assert File.read!(target) == "untouched"
  end
  test "loaded process pins cannot exceed the hard per-node ceiling", c do
    entries = for n <- 1..65, do: %{"kind" => "registered_process", "node" => "app@host", "name" => "W#{n}"}
    File.write!(c.file, Json.encode(%{schema: 1, entries: entries}))
    assert {[], "watchlist_limit"} = Watchlist.load(c.file)
  end
  test "filesystem failure never reports that a pin was saved", c do
    File.mkdir_p!(c.file)
    assert {:error, :watchlist_write_failed} = Watchlist.add([], %{"kind" => "node", "node" => "app@host"}, [%{name: "app@host"}], Config.defaults(), c.file)
  end
end
