# BEAM Deck

**BEAM Deck** is a host-aware BEAM/OTP cockpit for **Omarchy Quattro**. It watches every local `beam.smp` process, attaches to distributed Erlang nodes when it can, correlates runtime behavior with the physical workstation, surfaces OTP pathologies, shows distributed topology, and exposes a deliberately small set of reversible runtime controls.

Repository target: `github.com/nshkrdotcom/omarchy-beam-deck`

Plugin id: `nshkr.beam-deck`
License: MIT

This is not a Phoenix dependency, a Prometheus exporter, or Observer embedded in QML. Core inspection is agentless and uses OTP itself.

## What v0.1 implements

- **Always-on local BEAM census** from `/proc`, including VMs with distribution disabled, with exact OS-PID correlation when a local distributed node attaches.
- **Two visibility levels**: OS-only telemetry for any local BEAM, deep OTP telemetry for attachable distributed nodes.
- **Multiple local VM awareness** with local scheduler-density accounting against host logical CPUs.
- **EPMD discovery**, explicit-node configuration, and peer learning from attached nodes. No LAN scanning.
- **Per-node limits and usage**: processes, atoms, ports, ETS, schedulers, dirty CPU schedulers, run queue, uptime, OTP/ERTS/Elixir versions, applications, peers, and memory composition.
- **Hot-process inspection** using OTP's `observer_backend.procs_info/1`, selecting a bounded union of top mailbox, memory, and reduction consumers.
- **Mailbox pressure alerts** using both absolute queue length and growth rate measured from real deep-sample timestamps.
- **Run-queue, process-table, atom-table, and local scheduler-density alerts**.
- **Registered-process replacement churn detection** from sampled registered-name/PID fingerprints, without pretending to know private Supervisor restart-intensity state.
- **Scheduler utilization sampling** while the panel is open. BEAM Deck enables scheduler wall-time only for the inspection session and restores each node's previous setting when the panel closes.
- **Live scheduler controls** for `schedulers_online` and `dirty_cpu_schedulers_online`, with original values retained for explicit restore and best-effort restore on helper shutdown.
- **OTP 28+ Deep Events** via a temporary, pure-Erlang probe using isolated trace sessions for long GC, long schedules, long message queues, large heaps, busy ports, and busy distribution ports. The probe is stopped and unloaded when the panel closes.
- **Distributed topology**: each attached node reports visible + hidden peers; newly learned peers become inspectable candidates. Explicit `expected_peers` contracts enable honest missing-link warnings instead of assuming every sparse topology is a partition.
- **Node lifecycle events** from `net_kernel:monitor_nodes`, including the OTP-provided `nodedown_reason` when available.
- **Bounded in-memory history** with endpoint-preserving downsampling for the QML payload, so the graph represents the retained window instead of only the newest tail. No database and no external telemetry service to maintain.
- **Friendly Omarchy onboarding** for missing Erlang/Elixir, no BEAM VMs, OS-only VMs, and unreachable/authentication-failed nodes.
- **Mise-first setup helper**. Nothing is installed silently; the launcher can also re-enter through `mise exec` when the long-running Omarchy shell has a stale `PATH` after installation.
- **Floating IEx remsh action** through Omarchy's `xdg-terminal-exec` path.
- **Startup profile helper** for copy/paste `ERL_FLAGS`; it never edits project or shell configuration.
- **Dependency-free helper**: no Hex packages. Build output lives under `~/.cache/beam-deck`, not inside the plugin checkout.
- **Protocol isolation**: helper VM/Mix/Logger output is redirected to the state log while JSONL is emitted on a dedicated inherited file descriptor, so distribution diagnostics cannot corrupt QML state.
- **Credential hygiene**: `/proc` command-line capture redacts `-setcookie`/`--cookie` values before snapshots reach QML, and per-node cookies are referenced indirectly through environment-variable names.

## Architecture

```text
Omarchy / Quickshell

  nshkr.beam-deck service       owns helper lifecycle + state
          │
          ├──────── bar widget  tiny health surface
          │
          └──────── panel       host / node / process / topology controls
          │
          │ JSONL over local stdio
          ▼
  beam-deckd (Elixir/OTP)
  hidden node, intentionally tiny: +S 1:1 +SDcpu 1:1 +SDio 1
          │
          ├── /proc ─────────── every local beam.smp
          │
          ├── EPMD ──────────── local distributed-node discovery
          │
          ├── erpc/observer ─── agentless deep node/process inspection
          │
          └── trace probe ───── opt-in OTP 28+ Deep Events
                     │
                     ├── local nodes
                     └── configured / learned remote nodes
```

The Quickshell service is intentionally thin. Heavy BEAM work is not performed inside the long-lived Omarchy shell process.

## Requirements

- Omarchy with Quattro/Quickshell third-party plugin support.
- Linux `/proc` for host census.
- For deep telemetry: Erlang/OTP and an attachable distributed node.
- Elixir/Mix are required for the current `beam-deckd` helper implementation.
- `xdg-terminal-exec` for floating terminal actions (standard in current Omarchy).
- `mise` is the recommended toolchain path; existing system/asdf/source installations also work if `erl`, `elixir`, and `mix` are on the shell's `PATH`.

BEAM Deck itself has **zero Hex dependencies**.

## Install

Once the repository is public:

```bash
omarchy plugin add https://github.com/nshkrdotcom/omarchy-beam-deck.git --enable
```

For a local checkout:

```bash
omarchy plugin validate /path/to/omarchy-beam-deck
omarchy plugin add /path/to/omarchy-beam-deck --enable
omarchy restart shell
```

Restarting the shell is the deterministic acceptance path after install or QML edits; do not rely on plugin hot-reload behavior while validating a release.

The manifest asks for the right-hand bar section by default. Omarchy may still prompt for placement.

## First run / no BEAM installed

The bar remains functional even when Erlang and Elixir do not exist. The launcher emits a synthetic `runtime_missing` snapshot without starting a VM, and the panel offers a deliberate Mise setup action.

The helper runs:

```bash
mise use -g erlang@latest elixir@latest
```

only after confirmation in the opened terminal. It never installs Mise itself and never invokes `sudo`.

You can run the onboarding helper directly:

```bash
./bin/beam-deck-onboard
```

Once `erl`, `elixir`, and `mix` are available, the launcher notices automatically and starts `beam-deckd`; the plugin does not need reinstalling. If the already-running Omarchy shell has not refreshed its `PATH`, the launcher probes the configured Mise environment and re-enters through `mise exec` instead.

## What appears automatically

Start any ordinary BEAM program:

```bash
iex
mix phx.server
livebook server
./bin/my_release start
```

BEAM Deck sees its OS process even if Erlang distribution is disabled. That level includes PID, command line, working directory, RSS/virtual memory, thread count, process state, and sampled host CPU use.

For deep OTP telemetry, give the VM a node name:

```bash
iex --sname my_app -S mix phx.server
```

or for a release, configure normal Erlang distribution as you already would. The helper uses the current user's normal Erlang cookie unless a per-node cookie is configured.

## Why local-vs-remote matters

Each BEAM VM has its own process table, atom table, ports, scheduler pool, and allocator state. Therefore BEAM Deck never adds remote schedulers to the workstation's host budget and never interprets a process limit as a machine-global limit.

The host card reports:

- number of **local OS BEAM VMs** from `/proc`;
- number of distributed nodes that are deeply attached;
- scheduler count only for **attached local nodes**;
- aggregate local BEAM RSS from `/proc`;
- local deeply observed Erlang process count;
- warnings/critical alerts.

Remote peers still appear in node and topology views, but their scheduler populations do not contaminate local density warnings.

## Hot processes

When the panel opens, BEAM Deck performs a deep process scan at `deep_interval_ms` (default 5 s), independent of the lighter host/node refresh (default 2 s). It uses `observer_backend.procs_info/1` and keeps a bounded union of the highest:

- message queue length;
- process memory;
- reductions.

The default safety cap refuses a process-table scan above 100,000 processes. Raise `max_process_scan` deliberately if that is appropriate for your workload.

Reductions are presented as BEAM work units, not mislabeled as literal CPU percentage.

## Scheduler utilization

Opening the panel enables `scheduler_wall_time` on each attached node that permits it. The daemon samples counters and computes utilization from deltas. Closing the panel restores the preexisting wall-time setting (`false` stays false; an already-enabled node stays enabled).

This is separate from run-queue pressure: both are useful, and neither is treated as a magical health score.

## Runtime controls

BEAM Deck currently mutates only two normal runtime controls:

- `schedulers_online`
- `dirty_cpu_schedulers_online`

The UI records the first value observed before BEAM Deck changes each flag. **Restore** sends those original values back. Values are also restored best-effort when the helper terminates normally.

Changes are deliberately labeled as runtime/session controls. A VM restart naturally returns to its startup configuration.

BEAM Deck does **not** silently raise process, port, or atom limits. Those are startup decisions and often mask the real problem.

### Startup profile helper

Generate copy/paste launch flags without editing anything:

```bash
./bin/beam-deck-profile --schedulers 8 --dirty-cpu 4
```

Example output:

```bash
ERL_FLAGS="+S 8:8 +SDcpu 4:4"
```

Additional startup-only options are supported:

```bash
./bin/beam-deck-profile \
  --schedulers 8 \
  --dirty-cpu 4 \
  --dirty-io 4 \
  --process-limit 1048576 \
  --port-limit 65536 \
  --atom-limit 1048576
```

The panel's **Startup flags** button opens this helper using the currently selected scheduler values.

## Deep Events (OTP 28+)

Deep Events are opt-in from a node card. No probe is permanently installed into the application.

For a capable node BEAM Deck:

1. obtains its own compiled `nshkr_beam_deck_probe` object code;
2. loads that module into the target node with `code:load_binary/3`;
3. starts a local tracer process on the target;
4. creates an isolated `trace` session;
5. enables configured system monitors;
6. forwards only normalized event messages to `beam-deckd`;
7. destroys the trace session and unloads the module when disabled or when the panel closes.

Default monitored conditions:

- long GC >= 100 ms;
- long schedule >= 100 ms;
- message queue crossing 5,000 (disable threshold 1,000);
- large heap >= 8,000,000 words;
- busy port;
- busy distribution port.

Because the tracer monitors the BEAM Deck helper PID, losing the helper/node connection also causes the remote tracing process to clean itself up.

On OTP 27 and older, ordinary inspection remains available but Deep Events are disabled in the UI.

## Multiple machines and clusters

BEAM Deck discovers local EPMD registrations automatically. Attached nodes report their peers, and those peers become additional candidates. For remote nodes that cannot be learned from an attached local node, configure them explicitly.

Create:

```text
~/.config/beam-deck/config.json
```

Example:

```json
{
  "nodes": [
    {
      "name": "worker@omen",
      "cookie_env": "BEAM_DECK_OMEN_COOKIE",
      "required": true,
      "expected_peers": ["api@workstation"]
    }
  ]
}
```

Then provide the cookie to the Omarchy session environment without putting it in `shell.json` or this repo:

```bash
export BEAM_DECK_OMEN_COOKIE='...'
```

BEAM Deck calls `set_cookie` for that specific node. It does not persist the secret. `required: true` raises a critical alert when the configured node is unavailable. `expected_peers` is a **directional** contract: in the example, `worker@omen` is expected to report `api@workstation` as a connected peer. Missing expected links are warned; unconfigured missing edges are never mislabeled as partitions.

### Short names vs. long names

A single Erlang distribution node cannot simultaneously participate in short-name and long-name distributions. BEAM Deck therefore defaults to the common local-development **short-name** mode.

For a long-name cluster, start the helper in long-name mode by exposing this to the Omarchy shell process:

```bash
export BEAM_DECK_LONGNAMES=1
```

Optional override:

```bash
export BEAM_DECK_NODE_HOST=workstation.example.net
```

In long-name mode the helper uses `-name`; local EPMD candidates are reconstructed using `BEAM_DECK_NODE_HOST` or the machine FQDN. Explicit configured node names remain the most deterministic option for remote long-name clusters.

If you routinely use unrelated short-name and long-name clusters at the same time, v0.1 does not spawn two distribution bridge nodes; see `HANDOFF.md` for that deliberate boundary.

## Configuration

Defaults are defined in `daemon/lib/beam_deck/config.ex`; a complete example is in `config/config.example.json`.

Key defaults:

| Key | Default | Purpose |
|---|---:|---|
| `poll_interval_ms` | 2000 | Light host/node refresh |
| `deep_interval_ms` | 5000 | Process-table scan cadence while panel is open |
| `history_points` | 450 | Bounded in-memory samples |
| `max_process_scan` | 100000 | Refuse expensive full process scan beyond this |
| `mailbox_warn` | 5000 | Absolute mailbox warning |
| `mailbox_critical` | 50000 | Critical mailbox warning |
| `mailbox_rate_warn` | 1000/s | Growth-rate warning |
| `process_usage_warn` | 0.80 | Process table utilization warning |
| `atom_usage_warn` | 0.80 | Atom table utilization warning |
| `run_queue_per_scheduler_warn` | 1.0 | Run queue pressure threshold |

Invalid JSON or a non-object top level does not crash the plugin: the daemon falls back to defaults and reports `config_error` in the snapshot. A valid object with malformed individual values is normalized back to safe defaults for those values.

## Authentication and security model

Erlang distribution is powerful by design. A party with the distribution cookie can execute code on the node. Treat cookies like credentials.

BEAM Deck:

- does not put cookies in `manifest.json` or `shell.json`;
- redacts `-setcookie` and `--cookie` values observed in local BEAM command lines before they enter snapshots;
- supports cookie environment-variable references for explicit nodes;
- performs no arbitrary LAN scan;
- validates node-name syntax before converting names to atoms;
- keeps destructive/runtime actions explicit in the panel;
- loads the Deep Events probe only after an explicit user action;
- unloads the probe on disable/panel close;
- contains no sudo/install hook;
- contains no network client besides Erlang distribution itself.

Read `SECURITY.md` before exposing Erlang distribution beyond trusted development networks.

## Logs and state

Generated helper build files:

```text
~/.cache/beam-deck/
```

Daemon stdout/stderr/logging:

```text
~/.local/state/beam-deck/beam-deckd.log
```

Persistent user config:

```text
~/.config/beam-deck/config.json
```

The repository itself stays clean during normal use.

## IPC

The service exposes a small Omarchy IPC target:

```bash
omarchy-shell nshkr.beam-deck ping
omarchy-shell nshkr.beam-deck status
omarchy-shell nshkr.beam-deck refresh
omarchy-shell nshkr.beam-deck open
```

`status` returns the latest snapshot JSON.

## Development and tests

Static checks (work even on a host with no BEAM toolchain):

```bash
./test/static.sh
```

BEAM unit tests:

```bash
cd daemon
mix test
```

Real distributed-VM integration tests:

```bash
cd daemon
BEAM_DECK_INTEGRATION=1 mix test
```

Full local check:

```bash
make check
```

The integration suite starts a genuine OTP peer node and verifies deep inspection, a real `observer_backend` process scan, scheduler mutation/restore, and the OTP 28+ temporary trace probe. These are not mocks.

GitHub Actions runs the BEAM suite across representative OTP/Elixir generations (OTP 27/Elixir 1.18, OTP 28/Elixir 1.19, OTP 29/Elixir 1.20) plus the no-BEAM static suite.

Before publishing or after an Omarchy shell change, also run on a real Omarchy workstation:

```bash
omarchy plugin validate .
```

Then follow `HANDOFF.md` for graphical and live-node acceptance.

## Repository layout

```text
manifest.json                 Omarchy plugin declaration
qml/Service.qml               helper lifecycle + shared state + IPC
qml/BarWidget.qml             compact bar surface
qml/Panel.qml                 host/node/process/topology/control UI
bin/beam-deckd                toolchain detection + tiny helper launcher
bin/beam-deck-onboard         friendly Mise setup
bin/beam-deck-remsh           floating IEx remsh helper
bin/beam-deck-profile         startup ERL_FLAGS builder
daemon/lib/                   Elixir monitor/control plane
daemon/src/nshkr_beam_deck_probe.erl OTP 28+ transient remote trace probe
daemon/test/                  unit + real-peer integration tests
config/config.example.json    full user configuration example
test/static.sh                shell/manifest/onboarding/static validation
docs/                         architecture/protocol/validation notes
HANDOFF.md                    exact live Omarchy acceptance checklist
```

## v0.1 boundaries

The following are deliberate boundaries rather than silently mocked features:

- There is no automatic LAN scan.
- A single helper distribution mode is either short names or long names; simultaneous unrelated short+long clusters would require a second bridge node.
- Deep Events requires OTP 28+; ordinary inspection works without it.
- The process table is sampled, not continuously traced, and is capped by `max_process_scan`.
- Registered-name replacement churn is sampled and alerted, but v0.1 does not draw a whole supervision tree or present an exact `max_restarts/max_seconds` countdown by scraping private Supervisor state. The UI surfaces observable churn/pathology without making a false claim.
- History is intentionally memory-only and bounded.
- BEAM Deck does not install application agents or Hex dependencies.

For the exact verification status of this archive, see `docs/VALIDATION.md`.
