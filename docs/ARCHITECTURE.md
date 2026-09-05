# Architecture

## Design constraints

BEAM Deck is built around five constraints:

1. Omarchy's shell is a long-running Quickshell process, so heavy runtime introspection must not execute in QML.
2. One Linux host can run many independent BEAM VMs, each with its own scheduler pool and VM limits.
3. Not every local BEAM is distributed, so OS census and deep OTP attachment are separate capabilities.
4. Erlang distribution already supplies the correct remote-control semantics; BEAM Deck does not reimplement the distribution protocol.
5. Topology/health claims must be evidence-backed: unconfigured missing edges are not called partitions, and Supervisor-private restart thresholds are not guessed.

## Omarchy side

`manifest.json` declares `service`, `bar-widget`, and `panel` entry points under plugin id `nshkr.beam-deck`.

`qml/Service.qml` is the single owner of the helper process and latest snapshot. It starts `bin/beam-deckd`, parses JSONL, forwards mutation commands, exposes terminal helpers, and registers the `nshkr.beam-deck` Omarchy IPC target.

`qml/BarWidget.qml` reads that shared service state and renders only the compact runtime/alert surface. It never starts its own telemetry worker.

`qml/Panel.qml` implements `open(payloadJson)` and `close()`. The panel provides host budget, node detail, process pathology, runtime events, topology, recent history, and reversible controls. Opening/closing drives the daemon's inspection session so expensive scans and scheduler-wall-time instrumentation are not always on.

## Helper launch and missing-runtime behavior

`bin/beam-deckd` works before BEAM exists. If `erl`, `elixir`, or `mix` is unavailable, it emits a synthetic `runtime_missing` snapshot from POSIX shell and periodically rechecks. If the long-running Omarchy shell has a stale `PATH`, it can discover a global Mise toolchain and re-enter through `mise exec`.

When available, the dependency-free Elixir helper is compiled under XDG cache and started as a hidden, intentionally tiny distribution node:

```text
+S 1:1
+SDcpu 1:1
+SDio 1
-hidden
```

File descriptor 3 is reserved for protocol JSON. Ordinary Mix/ERTS/Logger output is redirected to `~/.local/state/beam-deck/beam-deckd.log`, preventing distribution diagnostics from corrupting the QML JSON stream.

## Local OS census

`BeamDeck.Procfs` scans numeric `/proc` entries whose `comm` starts with `beam`, excluding the helper's own OS PID. It records PID, command, cwd, state, RSS/virtual memory, threads, and sampled CPU usage.

Command-line capture redacts cookie values in both separated and inline `-setcookie` / `--cookie` forms before the data enters a snapshot.

For attached local distributed nodes, `os:getpid/0` is queried remotely and correlated back to `/proc`; this marks the exact local runtime row as deeply attached rather than trying to infer identity from names or command lines.

## Discovery and authentication

`BeamDeck.Discovery` combines:

- local EPMD registrations;
- explicitly configured node names;
- visible/hidden peers learned from attached nodes.

There is no LAN sweep. Candidate node strings are syntax-validated before atom conversion. The helper is excluded by its `beam_deck_` prefix.

A configured node may specify:

- `cookie_env`: environment-variable **name** containing its cookie;
- `required`: whether unavailability is critical;
- `expected_peers`: directional adjacency contracts used for missing-link warnings.

The secret itself is not stored in plugin configuration.

Short-name mode is the default. `BEAM_DECK_LONGNAMES=1` switches the helper to long-name mode; a single v0.1 helper intentionally does not bridge unrelated short- and long-name universes simultaneously.

## Deep inspection

`BeamDeck.Remote.inspect_node/2` connects using normal Erlang distribution. It prefers `observer_backend:sys_info/0` for coherent limits/runtime/memory data, with public `erlang:system_info`, `erlang:statistics`, and `erlang:memory` fallbacks.

Process enumeration runs only on the independent deep cadence while the panel is open. `observer_backend:procs_info/1` streams `etop_proc_info` chunks to the helper; BEAM Deck computes a bounded union of top mailbox, memory, and reduction consumers plus a bounded registered-name/PID fingerprint set used for churn detection. A configured process-count cap prevents accidental huge scans.

Light polls preserve the most recent process sample instead of rescanning the process table.

## Host scheduler budget

Host pressure and recommendations include **only attached local nodes**. Remote cluster schedulers never contribute to the workstation denominator/numerator.

If online local schedulers do not exceed logical host CPUs, recommendations preserve current values. If oversubscribed, `BeamDeck.Budget` computes a bounded recommendation weighted by current run-queue demand, never raises a node above its current online count, and preserves at least one normal scheduler per local attached node when feasible.

The recommendation is advisory until the user explicitly applies it.

## Scheduler utilization and controls

While the panel is open, BEAM Deck enables `scheduler_wall_time` on nodes that permit it, retains the old setting, and computes per-scheduler utilization from active/total counter deltas. Closing the panel restores nodes that previously had the instrumentation disabled; nodes that already had it enabled remain enabled.

The only normal live VM controls are:

- `schedulers_online`;
- `dirty_cpu_schedulers_online`.

`erlang:system_flag/2` returns each pre-mutation value, which is retained for explicit **Restore** and best-effort normal helper shutdown. SIGKILL is explicitly outside that cleanup guarantee.

Process/port/atom limits remain startup-profile concerns; BEAM Deck never silently raises them.

## Pathology alerts and restart churn

The alert layer derives transparent warnings from current/raw values and retained samples:

- local scheduler oversubscription;
- process table utilization;
- atom table utilization;
- run queue per online scheduler;
- mailbox absolute size and growth rate;
- required configured node unavailable;
- configured expected peer missing;
- repeated registered-name PID replacement within the rolling churn window.

BEAM Deck does not scrape private Supervisor state and therefore does not claim an exact `max_restarts/max_seconds` countdown.

## Node lifecycle and topology

The helper subscribes to `net_kernel:monitor_nodes/2` for all node types and requests node-down reasons. `nodeup`/`nodedown` events are retained in the bounded recent-event list and trigger an immediate reconciliation poll.

The topology snapshot contains each node's reported `sees` peers plus configured `expected` and computed `missing` lists. Only explicitly expected-but-missing links generate partition-like warnings.

## Deep Events

OTP 28+ Deep Events are opt-in. The helper loads its own namespaced `nshkr_beam_deck_probe` object code into the target node, starts a target-local process, creates an isolated `trace:system/3` session, enables the configured long-GC/long-schedule/mailbox/large-heap/busy-port monitors, and forwards normalized events.

Startup uses a readiness handshake: the UI marks events active only after the remote trace session has initialized. Disable/panel-close synchronously stops the probe, then deletes and soft-purges its module. The probe also monitors the helper PID so loss of its parent tears down the trace session.

OTP 27 keeps all ordinary inspection functionality but does not expose this Deep Events mode.

## History

`BeamDeck.History` retains a bounded newest-first window in memory. The snapshot exports a chronological, endpoint-preserving downsample (maximum 120 points by default) spanning that **whole retained window**, keeping the QML payload bounded without making the graph represent only the newest tail.

No database or persistent telemetry store is used.
