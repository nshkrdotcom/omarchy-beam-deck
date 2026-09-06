# BEAM Deck

[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](https://github.com/nshkrdotcom/omarchy-beam-deck)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Omarchy%20Quattro-purple.svg)](https://github.com/nshkrdotcom/omarchy-beam-deck)
[![App Dependencies](https://img.shields.io/badge/app%20dependencies-0-brightgreen.svg)](#requirements-and-external-dependencies)

**Host-aware runtime instrumentation, incident investigation, and diagnostics for Erlang and Elixir on Omarchy Quattro.**

BEAM Deck is a host-aware cockpit and real-time monitoring suite for **Erlang & Elixir (BEAM/OTP)** designed natively for the **Omarchy Quattro** desktop environment. It automatically discovers local BEAM instances, attaches agentlessly to distributed nodes, surfaces runtime health and process bottlenecks, correlates incident evidence, records bounded historical context, visualizes cluster topology, and provides safe, reversible scheduler controls from the desktop status bar.

![BEAM Deck preview](preview.png)

## Features

- **Zero App Dependencies**: No Hex packages to add to your Phoenix or Elixir apps. Core deep telemetry is agentless and uses native OTP distribution.
- **Automatic Host Census**: Detects local `beam.smp` processes via Linux `/proc`, including standard scripts, Phoenix servers, IEx sessions, and Livebooks—even with distribution disabled.
- **Deep Node Telemetry**: Connect to named nodes to inspect process tables, atom usage, ports, ETS, run queues, scheduler state, and granular memory distribution.
- **Incident Triage**: Turns alerts, runtime events, watchlist state, and conservative forecasts into prioritized incidents with evidence labeled as observed, correlated, or heuristic.
- **Flight Recorder**: Keeps a bounded rolling history of compact runtime frames so you can compare state before and during a failure, inspect the last frame before a runtime disappeared, and export selected diagnostics.
- **Focused Process Inspection**: Inspect one PID's status, bounded argument-free stack information, ancestry, and shared-binary reference summaries without collecting process messages or dictionaries.
- **ETS Inspection**: Request bounded metadata-only ETS leaderboards by memory or element count, with explicit partial/capped results and owner inspection.
- **Persistent Watchlist**: Pin exact nodes and registered process names locally. Registered-name pins resolve the current PID instead of assuming a transient PID is stable.
- **Resource Forecasts**: Conservative process, atom, and port capacity projections surface only when the observed trajectory meets minimum evidence and stability requirements.
- **Hot Process Watchdog**: Spot processes with high reductions, memory use, or mailbox growth, with an explicit one-click **Garbage Collection (GC)** action after refreshing live state.
- **Reversible Scheduler Controls**: Adjust online normal and dirty CPU schedulers, restore the originally observed values, or use a bounded scheduler-budget trial that automatically reverts unless explicitly kept.
- **Cluster Topology**: Visualize connected nodes, hidden nodes, and peers. Directional peer contracts help detect real link failures without conflating remote schedulers with local host capacity.
- **Deep Events (OTP 28+)**: Opt-in isolated tracing through temporary namespaced trace sessions for long GCs, scheduling delays, mailbox growth, large heaps, and busy ports.
- **Crash Triage**: When a local runtime disappears, BEAM Deck can perform a bounded local read of a fresh `erl_crash.dump` in the runtime's previously observed working directory.
- **Private Diagnostic Export**: Manually export a bounded local ZIP containing selected recorder frames, incidents, events, current diagnostic state, and a privacy notice.
- **Critical Desktop Notifications**: Critical incident transitions can surface through native desktop notifications with per-incident cooldowns.
- **1-Click Interactive Shell**: Jump into a connected node with a floating `IEx remsh` terminal through Omarchy's terminal executor.
- **Seamless Toolchain Onboarding**: If Erlang/Elixir are not installed, BEAM Deck guides you through Mise-based setup instead of repeatedly failing in the shell.

## What's New in 1.1

BEAM Deck 1.1 keeps the original **Cockpit** and adds a dedicated investigation workflow.

| Workspace | What it is for |
|---|---|
| **Triage** | Prioritized incidents with directly observed alerts, nearby events, watchlist context, and explicitly heuristic forecasts. |
| **Recorder** | Browse retained frames, compare counters/memory/hot sets, inspect the last frame before disappearance, and export selected evidence. |
| **Process** | Inspect one process in depth, refresh its live identity, GC explicitly, or pin a registered name for later observation. |
| **ETS** | Request bounded metadata-only ETS leaderboards and inspect table owners without collecting keys or values. |
| **Watchlist** | Persist nodes and registered process names that matter to you across BEAM Deck restarts. |
| **Budget** | Review the complete current local scheduler recommendation and run a bounded reversible trial before deciding whether to keep it. |

Historical recorder views are intentionally read-only for mutating actions. Return to **Live** and refresh the target before GC or scheduler changes.

## Requirements and External Dependencies

### Required runtime

- **Omarchy Quattro** is the supported desktop environment.
- **Erlang/OTP 27+** and **Elixir 1.18+** are required for the BEAM helper and deep OTP telemetry.
- The intended compatibility matrix covers OTP 27 / Elixir 1.18, OTP 28 / Elixir 1.19, and OTP 29 / Elixir 1.20.
- **Mise** is the recommended Omarchy-native way to install Erlang and Elixir. If the toolchain is missing, BEAM Deck provides guided onboarding with:

```bash
mise use -g erlang@latest elixir@latest
```

### Runtime behavior

- BEAM Deck adds **no dependencies to applications being monitored**.
- Named BEAM applications need standard distribution enabled with `--sname` or `--name` for deep telemetry.
- Non-distributed local BEAM processes are still discovered through Linux `/proc`.
- Standard OTP applications, including `runtime_tools`, are used for supported diagnostics.
- **jq** is optional at runtime and is used by `beam-deck-remsh` to resolve a configured node's `cookie_env` entry from `~/.config/beam-deck/config.json`. Core monitoring does not require it.
- Erlang distribution is a trusted remote-control channel, not a read-only security boundary. Do not expose distribution to untrusted networks.

## Install

Install and enable BEAM Deck directly from its public Git repository:

```bash
omarchy plugin add https://github.com/nshkrdotcom/omarchy-beam-deck.git --enable
omarchy restart shell
```

For local development, keep the checkout directly in Omarchy's plugin directory, for example:

```text
~/.config/omarchy/plugins/nshkr.beam-deck
```

Then rescan, enable, and restart:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable nshkr.beam-deck --section right
omarchy restart shell
```

### Update

Git-managed installations use Omarchy's normal update path:

```bash
omarchy plugin update nshkr.beam-deck
omarchy restart shell
```

### Remove

Before removing the plugin, revert any active scheduler trial and restore any scheduler changes you do not want to keep.

```bash
omarchy plugin remove nshkr.beam-deck
omarchy restart shell
```

BEAM Deck does not modify monitored applications, and Erlang/OTP and Elixir are installed independently and are not removed with the plugin.

Optional BEAM Deck user state can also be removed:

```bash
rm -rf ~/.config/beam-deck ~/.cache/beam-deck ~/.local/state/beam-deck
```

## Usage

### Quick Start

#### 1. Launch a BEAM Application

Start your Elixir or Erlang application with a short name:

```bash
# In your Phoenix project:
iex --sname my_app -S mix phx.server

# Or a standard interactive session:
iex --sname demo
```

#### 2. Open BEAM Deck

Look for the BEAM icon in your Omarchy status bar. Click it, or run:

```bash
omarchy-shell shell toggle nshkr.beam-deck '{}'
```

The top-level UI gives you the original **Cockpit** plus the 1.1 **Investigate** workflow.

### Cockpit Tour

```text
+-------------------------------------------------------------+
| BEAM DECK                      Host: 16 Cores | 3 Runtimes  |
+-------------------------------------------------------------+
| Host Workstation Census                                     |
|   - Local BEAM processes: 3    - Attached OTP Nodes: 2      |
|   - Host Scheduler Load: 12/16 - Total BEAM RSS: 412 MB     |
+-------------------------------------------------------------+
| Nodes                                                       |
|   [ my_app@workstation ]  OTP 29 | Sched: 8 | Procs: 420    |
|   [ worker@workstation ]  OTP 28 | Sched: 4 | Procs: 180    |
|   [ livebook (OS-Only) ]  PID: 34129        | RSS: 110 MB   |
+-------------------------------------------------------------+
| Active Pathology Alerts (0 alerts)                          |
|   All mailboxes healthy - Run queues clear - Tables OK      |
+-------------------------------------------------------------+
| Live Controls (my_app@workstation)                          |
|   Normal Schedulers: [ - ] 8 [ + ]    [ Apply ] [ Restore ] |
|   Dirty CPU:         [ - ] 4 [ + ]    [ Apply ]             |
|   [ IEx remsh ]  [ Deep Events ]  [ Startup Flags ]         |
+-------------------------------------------------------------+
```

### Two Visibility Levels

BEAM Deck automatically categorizes detected BEAM runtimes into two visibility tiers:

1. **OS-Only Telemetry (Automatic)**
   - Works for local `beam.smp` processes even when distribution is disabled.
   - Shows OS PID, redacted command-line context, current working directory, RSS/virtual memory, threads, and sampled host CPU information.

2. **Deep OTP Telemetry (Connected Nodes)**
   - Available for reachable nodes started with `--sname` or `--name`.
   - Surfaces Erlang VM metrics including memory composition, process/atom/port/ETS limits, run queues, schedulers, hot processes, and remote peers.

## Everyday Guides

### Connecting Your Phoenix / Elixir Application

To give BEAM Deck deep access to your development application, start the node with distribution enabled:

```bash
# Elixir / Phoenix
iex --sname web -S mix phx.server

# Plain Elixir script or app
elixir --sname worker -S mix run --no-halt

# Erlang / Rebar3
rebar3 shell --sname erl_node
```

BEAM Deck automatically discovers the node via EPMD and correlates its distributed-node identity with the local OS process when possible.

### Investigating an Incident

When BEAM Deck raises an incident:

1. Open **Investigate → Triage** and review the evidence classification.
2. Use **Recorder** to compare nearby retained frames instead of inferring causality from the latest snapshot alone.
3. Open **Process** or **ETS** only when the incident points to a specific target worth inspecting.
4. Return to **Live** before any mutating action.
5. Export a diagnostics bundle only when you need to preserve or share the selected evidence.

Forecasts are intentionally conservative and conditional. A displayed ETA means roughly **"if the observed trajectory continues"**; it is not a probability of failure. Temporal proximity between an alert and an event is not proof of root cause.

### Diagnosing Hot Processes and One-Click GC

When memory climbs or a process stalls:

1. Open the node detail or the focused **Process** view.
2. Review mailbox size, memory, reductions, and the bounded diagnostic context.
3. Refresh the live process identity immediately before mutation.
4. Click **GC** only when you explicitly want to trigger garbage collection for that process.

Hot reductions are cumulative BEAM work counters, not a CPU percentage. A sampled process stack is evidence about current execution state; it does not by itself establish a deadlock.

### Safe Scheduler Work

BEAM Deck keeps the original direct scheduler controls and adds a safer trial workflow in 1.1.

For a bounded trial:

1. Open **Investigate → Budget**.
2. Review the complete current recommendation for attached local nodes.
3. Start the trial. BEAM Deck records the original values before requesting changes.
4. Observe the workload for the bounded trial window.
5. Choose **Keep** explicitly if the result is desirable; otherwise let the trial revert or choose **Revert**.

Trials are designed to revert on timeout, partial application, panel closure, or owner loss when BEAM Deck can still safely identify and reach the original VM. Rollback is conditional: if a VM restarted or an external actor changed the value, BEAM Deck does not blindly overwrite that newer state.

**Keep** does not erase the first observed original value. The node's normal **Restore** action remains available.

For startup-only flags, use:

```bash
./bin/beam-deck-profile --schedulers 8 --dirty-cpu 4 --dirty-io 2
```

The helper prints `ERL_FLAGS`; it does not edit your project or release configuration.

### Monitoring Remote Clusters and Multi-Machine Nodes

BEAM Deck can monitor explicitly configured remote nodes while keeping cookies out of the config file.

Create or extend `~/.config/beam-deck/config.json`:

```json
{
  "nodes": [
    {
      "name": "api@prod-box",
      "cookie_env": "BEAM_DECK_PROD_COOKIE",
      "required": true,
      "expected_peers": ["worker@prod-box"]
    }
  ]
}
```

Provide the referenced cookie variable to the environment inherited by the **actual Omarchy shell process**. Exporting a variable in an unrelated terminal does not retroactively update a running shell.

- **Credential References**: Node configuration stores the environment-variable name, not the cookie value.
- **Directional Contracts**: `expected_peers` describes links BEAM Deck should expect to exist.
- **Host Isolation**: Remote-node scheduler counts do not contribute to the local host scheduler budget.

### Short Names vs. Long Names

By default, BEAM Deck uses **short names** (`--sname`), which are convenient for local development.

For fully qualified long-name deployments:

```bash
export BEAM_DECK_LONGNAMES=1
export BEAM_DECK_NODE_HOST=workstation.mycorp.internal
```

The node host must be resolvable, and short-name and long-name nodes cannot be mixed within the same distribution naming mode.

### Deep Events Tracing (OTP 28+)

For advanced diagnostics on OTP 28 or newer:

- Click **Deep Events** in the node cockpit to attach a temporary isolated trace probe.
- It can surface events such as:
  - long garbage collections,
  - long scheduler executions,
  - rapid mailbox growth,
  - large process heaps,
  - busy network and distribution ports.
- The trace session is explicitly opt-in and temporary.
- Closing the panel or disconnecting tears down BEAM Deck-owned tracing and unloads the temporary namespaced probe module when cleanup can complete normally.

Ordinary BEAM Deck inspection does not require loading a BEAM Deck module into the target node.

### Watchlist

The 1.1 watchlist persists the identities you care about:

- **Node pins** track exact node names.
- **Registered-name pins** resolve the currently registered PID instead of treating a PID as a permanent identity.
- Cheap targeted observations can continue for pins even when the full panel is closed.

Watchlist state is stored locally in:

```text
~/.config/beam-deck/watchlist.json
```

### Diagnostic Export and Crash Triage

Diagnostic export is manual and local. The bundle is intentionally bounded and excludes raw configuration, raw logs, raw crash dumps, environment variables, process messages/state, full process dictionaries, binary contents/addresses, and ETS contents.

Review a bundle before sharing it: node names, module names, registered names, selected stack metadata, and crash slogans may still be sensitive.

Crash triage is also bounded. BEAM Deck only considers a fresh `erl_crash.dump` associated with a vanished local runtime's previously observed working directory; it does not search the filesystem for crash dumps and does not claim that a matching dump proves why the VM disappeared.

## Desktop IPC and Shell Commands

You can control BEAM Deck programmatically or bind shortcuts through the Omarchy IPC interface:

```bash
# Toggle cockpit panel open/closed
omarchy-shell shell toggle nshkr.beam-deck '{}'

# Open or close explicitly
omarchy-shell shell open nshkr.beam-deck '{}'
omarchy-shell shell close nshkr.beam-deck '{}'

# Force an immediate refresh
omarchy-shell shell refresh nshkr.beam-deck '{}'

# Print latest JSON snapshot
omarchy-shell shell status nshkr.beam-deck '{}'

# Ping the background service
omarchy-shell shell ping nshkr.beam-deck '{}'
```

## Configuration

BEAM Deck works out of the box with zero configuration. Existing 1.0 configuration continues to merge with the 1.1 defaults.

Core settings include:

| Key | Default | Description |
|:---|:---:|:---|
| `poll_interval_ms` | `2000` | Refresh cadence (ms) for light host/node overview |
| `deep_interval_ms` | `5000` | Process scan cadence (ms) while the panel is open |
| `history_points` | `450` | In-memory light-history data points |
| `max_process_scan` | `100000` | Safety cap for full process scans |
| `mailbox_warn` | `5000` | Mailbox queue length warning threshold |
| `mailbox_critical` | `50000` | Mailbox queue length critical threshold |
| `mailbox_rate_warn` | `1000` | Message growth-rate warning threshold |
| `process_usage_warn` | `0.80` | Process table capacity warning threshold |
| `atom_usage_warn` | `0.80` | Atom table capacity warning threshold |
| `run_queue_per_scheduler_warn` | `1.0` | Saturated run queue warning threshold per scheduler |

1.1 adds configuration for recorder retention, forecasts, incidents, watchlist observations, export limits, notifications, crash triage, and scheduler trials. See the complete reference in [docs/CONFIGURATION.md](docs/CONFIGURATION.md) and the full example in [config/config.example.json](config/config.example.json).

If configuration contains invalid JSON or an unexpected type, BEAM Deck falls back to safe defaults and surfaces a non-intrusive configuration warning rather than crashing the desktop shell.

### File Locations

| Purpose | Default path |
|---|---|
| User config | `~/.config/beam-deck/config.json` |
| Persistent watchlist | `~/.config/beam-deck/watchlist.json` |
| Build/dependency cache | `~/.cache/beam-deck/` |
| Helper log | `~/.local/state/beam-deck/beam-deckd.log` |
| Explicit diagnostic exports | `~/.local/state/beam-deck/exports/` |

XDG overrides are honored where supported. Recorder/history state is otherwise in memory and is not restored after helper restart.

## Security and Privacy

BEAM Deck uses security-conscious defaults:

- **Cookie Redaction**: `-setcookie` and `--cookie` values discovered in inspected process arguments are redacted before telemetry reaches the UI.
- **No Literal Cookies in Config**: Explicit nodes reference a `cookie_env` variable name rather than storing a cookie value in `config.json`.
- **No Arbitrary LAN Scanning**: BEAM Deck uses local EPMD and explicitly configured/discovered node relationships; it does not perform arbitrary network scanning.
- **No Permanent Target Agent**: Ordinary inspection does not install a BEAM Deck dependency or resident target agent.
- **Bounded Diagnostics**: Focused process/ETS inspection, recorder retention, crash reads, and exports are deliberately capped.
- **Local-First Evidence**: Watchlists, recorder state, crash triage, and exports remain local unless you explicitly share an exported file.

Erlang distribution is powerful by design. A node that can authenticate over distribution may be capable of far more than read-only inspection. Treat cookies and distribution connectivity as privileged access.

The `beam-deck-remsh` helper may pass an explicitly selected cookie through IEx arguments; other processes with sufficient OS permissions may be able to observe those arguments. Telemetry redaction is not a guarantee that every third-party tool or OS process view will hide credentials.

See [SECURITY.md](SECURITY.md) for the full threat model.

## Development and Testing

Run the static/local contracts:

```bash
make static
```

Run the full available release gates through Mise:

```bash
mise exec -- make check
```

Run the launcher/private-EPMD protocol harness:

```bash
mise exec -- make protocol
```

The test suite includes Elixir unit tests, source/QML contracts, JavaScript UI-state tests, protocol checks, and real disposable OTP-peer integration coverage where the local environment supports it.

For targeted work:

```bash
# Static/QML/shell/JavaScript contracts
./test/static.sh

# Elixir daemon unit tests
cd daemon && mix test

# Real-peer OTP integration tests
cd daemon && BEAM_DECK_INTEGRATION=1 mix test

# Strict code analysis
cd daemon && mix credo --strict

# Dialyzer
cd daemon && mix dialyzer
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Configuration](docs/CONFIGURATION.md)
- [Protocol](docs/PROTOCOL.md)
- [1.1 Implementation Design](docs/IMPLEMENTATION-1.1.md)
- [Validation](docs/VALIDATION.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## License

BEAM Deck is open-source software licensed under the [MIT License](LICENSE).
