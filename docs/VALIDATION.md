# Validation status for v0.1 handoff

This records what was actually executed while building the first archive. It intentionally separates checks that were run here from real OTP/Omarchy acceptance that must run on the target workstation.

## Build-environment capabilities

Available: `node`, `jq`, `git`, `zip`, Python 3.

Not available: `erl`, `elixir`, `mix`, `qmllint`, `qmlformat`, `shellcheck`, or a live Omarchy/Quickshell session.

## Executed successfully here

```bash
./test/static.sh
```

The static suite covers:

- manifest id/kinds and required entry-point files;
- current plugin id use in QML IPC/service lookup;
- required Omarchy panel `open(payloadJson)` / `close()` lifecycle hooks;
- Bash syntax and executable bits for shipped commands;
- exact `beam-deck-profile` output and invalid-value rejection;
- `beam-deck-remsh` per-node `cookie_env` handling without storing a cookie in config;
- the stale-Omarchy-PATH path where `beam-deckd` discovers a usable Mise toolchain through `mise exec`;
- the no-BEAM `runtime_missing` JSON path, including valid JSON output;
- QML delimiter/string/comment balance.

The archive packaging step also runs whitespace checks, archive integrity checks, and a final static-suite pass.

## Implemented but not executable in this container

`daemon/test/` and GitHub Actions contain tests for:

- custom dependency-free JSON codec and protocol parsing;
- configuration merge, malformed-value normalization, and invalid-JSON fallback;
- `/proc` parsing, CPU deltas, runtime discovery, and command-line cookie redaction;
- local-only host scheduler accounting and weighted scheduler-budget recommendations;
- no-op budget recommendations when the host is not oversubscribed;
- remote-peer exclusion from local scheduler pressure;
- mailbox absolute/rate alerts using real deep-sample timestamps;
- explicit required-node and directional `expected_peers` alerts;
- registered-name/PID replacement churn and expiry;
- bounded history and full-window downsampling;
- hot-process union and registered-process fingerprints;
- scheduler-wall-time utilization math;
- real OTP peer attachment and OS PID inspection;
- actual `observer_backend` process scanning;
- real `schedulers_online` mutation and restoration;
- OTP 28+ remote trace-probe load/start/stop/unload.

GitHub Actions is configured for OTP 27/Elixir 1.18, OTP 28/Elixir 1.19, and OTP 29/Elixir 1.20.

## Required live acceptance

`HANDOFF.md` is the authoritative release checklist. In particular, the first real Omarchy host must run `mix format`, compile with warnings as errors, execute unit + real-peer integration tests, run `omarchy plugin validate .`, restart the Omarchy shell, and complete visual/local/remote-node acceptance.

Until that is done, this archive should be described as **fully implemented with static/no-BEAM validation completed, and BEAM/Quattro live verification pending**, not as a host-certified release.
