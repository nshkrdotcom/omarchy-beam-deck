# BEAM Deck

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/nshkrdotcom/omarchy-beam-deck)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Omarchy%20Quattro-purple.svg)](https://github.com/nshkrdotcom/omarchy-beam-deck)
[![App Dependencies](https://img.shields.io/badge/app%20dependencies-0-brightgreen.svg)](#requirements)

**BEAM Deck** is a host-aware cockpit and real-time monitoring suite for **Erlang & Elixir (BEAM/OTP)** designed natively for the **Omarchy Quattro** desktop environment.

It automatically discovers every local BEAM instance running on your machine, attaches agentlessly to distributed nodes, surfaces runtime health and process bottlenecks, visualizes cluster topology, and provides safe, reversible scheduler controls—all right from your desktop status bar.

![BEAM Deck preview](preview.png)

---

## Features at a Glance

- **Zero App Dependencies**: No Hex packages to add to your Phoenix or Elixir apps. Core deep telemetry is agentless and uses native OTP distribution.
- **Automatic Host Census**: Detects all local `beam.smp` processes via Linux `/proc`, including standard scripts, Phoenix servers, IEx sessions, and Livebooks—even with distribution disabled.
- **Deep Node Telemetry**: Connect to named nodes to inspect process tables, atom usage, ports, ETS tables, run queues, and granular memory distribution (binary, atom, code, ETS, process heap).
- **Hot Process Watchdog**: Spot runaway processes consuming high reductions, excessive memory, or clogged mailboxes, complete with a one-click **Garbage Collection (GC)** trigger.
- **Live Reversible Schedulers**: Dynamically scale online normal and dirty CPU schedulers on the fly to tame CPU load. One-click **Restore** resets back to original startup values.
- **Intelligent Alerts**: Proactive warnings for mailbox explosions, message arrival rate spikes, run queue congestion, memory saturation, and process crashes/churn.
- **Cluster Topology**: Visual map of connected nodes, hidden nodes, and peers. Set directional peer contracts to detect real network splits without false alarms.
- **Deep Events (OTP 28+)**: Opt-in, zero-overhead tracing using temporary isolated trace sessions. Diagnoses long GCs, scheduling lags, and busy ports without modifying your codebase.
- **1-Click Interactive Shell**: Jump straight into a connected node with a floating `IEx remsh` terminal via Omarchy's terminal executor.
- **Seamless Toolchain Onboarding**: If Erlang/Elixir aren't installed yet, BEAM Deck guides you through a clean, one-click global setup using Mise.

---

## Requirements

- **Omarchy Quattro** is the supported desktop environment.
- **Erlang/OTP and Elixir** are required for BEAM runtime monitoring and deep OTP telemetry.
- **Mise** is the recommended Omarchy-native way to install Erlang and Elixir. If the toolchain is missing, BEAM Deck provides guided onboarding with:

```bash
mise use -g erlang@latest elixir@latest
```

- BEAM Deck adds **no dependencies to applications being monitored**.
- Named BEAM applications need standard distribution enabled with `--sname` or `--name` for deep telemetry.
- Non-distributed local BEAM processes are still discovered through Linux `/proc`.

---

## Quick Start (60 Seconds)

### 1. Install BEAM Deck

From your terminal on an Omarchy system:

```bash
omarchy plugin add https://github.com/nshkrdotcom/omarchy-beam-deck.git --enable
omarchy restart shell
```

> **Tip for local development:** Keep the checkout directly in Omarchy's plugin directory, for example:
> ```text
> ~/.config/omarchy/plugins/nshkr.beam-deck
> ```
>
> Then rescan, enable, and restart:
> ```bash
> omarchy-shell shell rescanPlugins
> omarchy plugin enable nshkr.beam-deck --section right
> omarchy restart shell
> ```

### 2. Launch Any BEAM Application

Start your Elixir or Erlang application with a short name:

```bash
# In your Phoenix project:
iex --sname my_app -S mix phx.server

# Or a standard interactive session:
iex --sname demo
```

### 3. Open the Cockpit

Look for the BEAM icon in your Omarchy status bar. Click it (or run `omarchy-shell shell toggle nshkr.beam-deck '{}'`) to toggle the cockpit panel!

---

## The Cockpit Tour

```text
+-------------------------------------------------------------+
| BEAM DECK                      Host: 16 Cores | 3 Runtimes  |
+-------------------------------------------------------------+
| Host Workstation Census                                     |
|   - Local BEAM processes: 3    - Attached OTP Nodes: 2      |
|   - Host Scheduler Load: 12/16 - Total BEAM RSS: 412 MB     |
+-------------------------------------------------------------+
| Nodes                                                       |
|   [ my_app@workstation ]  OTP 28 | Sched: 8 | Procs: 420    |
|   [ worker@workstation ]  OTP 27 | Sched: 4 | Procs: 180    |
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

1. **OS-Only Telemetry (Automatic)**:
   - For any local `beam.smp` instance (even with distribution turned off).
   - Shows OS PID, exact command line (with cookies automatically redacted for privacy), current working directory, RSS/virtual memory, threads, and sampled host CPU usage.

2. **Deep OTP Telemetry (Connected Nodes)**:
   - For nodes started with `--sname` or `--name`.
   - Surfaces real-time Erlang VM metrics: memory composition, process/atom/port/ETS limits, run queue latency, scheduler wall-time utilization, hot processes, and remote peers.

---

## Everyday Guides

### Connecting Your Phoenix / Elixir Application

To give BEAM Deck deep access to your development application, start your node with distribution enabled:

```bash
# Elixir / Phoenix
iex --sname web -S mix phx.server

# Plain Elixir script or app
elixir --sname worker -S mix run --no-halt

# Erlang / Rebar3
rebar3 shell --sname erl_node
```

BEAM Deck will automatically discover the node via EPMD and link its OS PID with its OTP runtime state.

---

### Taming Runaway Workloads (Live Schedulers)

When running multiple BEAM applications or intensive background jobs, your system can become oversubscribed if total active schedulers exceed physical CPU cores.

1. Open **BEAM Deck** and select the node.
2. In the **Runtime Controls** section, adjust **Schedulers Online** or **Dirty CPU Schedulers**.
3. Click **Apply**. The change takes effect immediately inside the VM without a restart!
4. When finished, click **Restore** to revert back to your VM's startup values.

> **Need permanent flags?** Click the **Startup flags** button or use the profile CLI helper:
> ```bash
> ./bin/beam-deck-profile --schedulers 8 --dirty-cpu 4
> # Output: ERL_FLAGS="+S 8:8 +SDcpu 4:4"
> ```

---

### Diagnosing Hot Processes & One-Click GC

When memory climbs or a process stalls:

1. Open the node detail view in the panel.
2. The **Hot Processes** table surfaces the highest consumers across three categories:
   - **Mailbox Queue Length**: Identifies message backlogs or blocked processes.
   - **Memory Usage**: Pinpoints memory leaks or bloated state.
   - **Reductions**: Pinpoints high compute activity (work units).
3. Click **GC** next to any process to trigger an immediate garbage collection cycle for that specific process.

---

### Monitoring Remote Clusters & Multi-Machine Nodes

BEAM Deck can monitor remote nodes on your network while keeping secrets safe.

1. Create a configuration file at `~/.config/beam-deck/config.json`:
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

2. Export the cookie environment variable in your Omarchy shell session:
   ```bash
   export BEAM_DECK_PROD_COOKIE='your-secure-erlang-cookie'
   ```

- **Zero Secret Leaks**: Cookies are referenced by environment variable name and never written to plain-text configuration files or logs.
- **Directional Contracts**: `expected_peers` specifies nodes that should be connected. If a link drops, BEAM Deck warns you immediately.
- **Host Isolation**: Remote node schedulers are tracked individually and will never falsely trigger local host CPU oversubscription alerts.

---

### Short Names vs. Long Names

By default, BEAM Deck uses **short names** (`--sname`), standard for local development.

If your cluster uses fully qualified domain names (**long names**, `--name`):
```bash
export BEAM_DECK_LONGNAMES=1
export BEAM_DECK_NODE_HOST=workstation.mycorp.internal   # (optional override)
```

Add these environment variables to your shell profile, and BEAM Deck will interact seamlessly with long-name clusters.

---

### Deep Events Tracing (OTP 28+)

For advanced diagnostics on OTP 28 or newer:
- Click **Deep Events** in the node cockpit to attach a temporary, isolated trace probe.
- Monitors:
  - Long Garbage Collections (≥ 100 ms)
  - Long Scheduler executions (≥ 100 ms)
  - Rapid Mailbox growth (> 5,000 messages)
  - Large process heap allocations (≥ 8M words)
  - Busy network & distribution ports
- **Completely Safe**: The trace probe uses an isolated trace session. Closing the panel or disconnecting immediately tears down the tracer and unloads the probe module from the target VM.

---

## Configuration Reference

BEAM Deck works out of the box with zero configuration. You can customize polling cadences and alert thresholds in `~/.config/beam-deck/config.json`:

| Key | Default | Description |
|:---|:---:|:---|
| `poll_interval_ms` | `2000` | Refresh cadence (ms) for light host/node overview |
| `deep_interval_ms` | `5000` | Process scan cadence (ms) while the panel is open |
| `history_points` | `450` | In-memory time-series history data points |
| `max_process_scan` | `100000` | Safety cap: skips full process scan if node exceeds this count |
| `mailbox_warn` | `5000` | Mailbox queue length warning threshold |
| `mailbox_critical` | `50000` | Mailbox queue length critical threshold |
| `mailbox_rate_warn` | `1000` | Message growth rate warning threshold (messages/sec) |
| `process_usage_warn` | `0.80` | Process table capacity warning threshold (80%) |
| `atom_usage_warn` | `0.80` | Atom table capacity warning threshold (80%) |
| `run_queue_per_scheduler_warn` | `1.0` | Saturated run queue warning threshold per scheduler |

> **Resilient by design:** If you pass invalid JSON or an unexpected type, BEAM Deck gracefully falls back to defaults and displays a non-intrusive warning rather than crashing your desktop shell.

---

## Desktop IPC & Shell Commands

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

---

## Security & Privacy

BEAM Deck is designed with security-conscious defaults:

- **Cookie Redaction**: Any `-setcookie` or `--cookie` flags found when inspecting `/proc` command lines are redacted before data reaches the UI.
- **Credential Safety**: No Erlang cookies are stored in plugin config or repository files.
- **No Arbitrary Scanning**: BEAM Deck only checks local EPMD and explicitly configured nodes—it never scans your local network (LAN).
- **No App Modification**: Never permanently injects code into your production or development applications.

---

## File Locations

- **Build Cache**: `~/.cache/beam-deck/`
- **Daemon Logs**: `~/.local/state/beam-deck/beam-deckd.log`
- **User Config**: `~/.config/beam-deck/config.json`

---

## Uninstall

Remove BEAM Deck through Omarchy:

```bash
omarchy plugin remove nshkr.beam-deck
omarchy restart shell
```

BEAM Deck does not modify monitored applications. Erlang/OTP and Elixir are installed independently and are not removed with the plugin.

Optional BEAM Deck user state can also be removed:

```bash
rm -rf ~/.config/beam-deck ~/.cache/beam-deck ~/.local/state/beam-deck
```

---

## Testing & Development

Run the full local validation suite:

```bash
make check
```

Or run specific check suites:

```bash
# Fast static validation (QML, shell scripts, protocol contracts)
./test/static.sh

# Elixir daemon unit tests
cd daemon && mix test

# Real-peer OTP integration tests
cd daemon && BEAM_DECK_INTEGRATION=1 mix test

# Strict code analysis and linting
cd daemon && mix credo --strict
```

---

## License

BEAM Deck is open-source software licensed under the [MIT License](LICENSE).
