# Changelog

All notable changes to BEAM Deck are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-09-08

### Added

* Process activity and ETS growth surveys with signed interval deltas, paging, filtering, and inspection pivots.
* Exact-PID stack sampling with frequency bars, expandable stacks, and report copying.
* Fair reduction-leader admission into the captured hot-process set.
* Dated provider quality, filtered activity, and recorder pivots in Triage.
* Retained-frame intervention baselines with comparison and report export.
* Additional recorder graphs for memory, queues, utilization, and capacity.
* Production Qt coverage, real-peer regressions, native import lint, and soak tooling.

### Changed

* Renamed the plugin ID from `nshkr.beam-deck` to `com.nshkr.beam-deck`.
* Resolved the telemetry helper from the installed QML component location.
* Added target incarnation and duration requirements to interval commands.
* Preserved investigation context, keyed rows, filters, focus, and scroll position.
* Kept unavailable measurements null and retained dated failed-node and watch evidence.
* Applied explicit nested allowlists to private ZIP export contents.
* Labeled historical action receipts separately from current control state.

### Fixed

* Confirmed normal and dirty CPU scheduler counts after mutation and during rollback.
* Prevented transient scheduler counts from appearing as external rollback changes.
* Rejected stale view epochs and VM identities before runtime control execution.
* Stopped Deep Events independently from diagnostic admission and verified cleanup separately.
* Prevented repeated or unavailable samples from falsely resolving incidents.
* Limited optional supervisor queries and preserved binary metadata.
* Excluded internal remsh clients from runtime resource budgets.
* Removed arbitrary OS command arguments from diagnostic output.
* Improved recorder selection, marker limits, missing segments, legends, and scale labels.

## [1.1.0] - 2026-09-06

### Added

* Investigate workspace with Triage, Flight Recorder, Process, ETS Lens, Watchlist, and Budget Trial views.
* Capacity and resource-growth forecasting with evidence and confidence reporting.
* Incident tracking with recorder context, notifications, and follow-up actions.
* In-memory Flight Recorder with historical ranges, A/B comparison, presets, and private ZIP export.
* Focused process inspection with ancestry, stack, binary metadata, and registered-process pinning.
* Metadata-only ETS inspection with capped sorting and owner information.
* Persistent node and registered-process watchlists.
* Leased scheduler budget trials with automatic rollback, Keep, and Restore.
* Capped local `erl_crash.dump` triage for disappeared runtimes.
* OTP 28+ opt-in Deep Events tracing.
* Omarchy-native keyboard navigation and shortcut guide.
* Real OTP integration and launcher protocol coverage.

### Changed

* Rebuilt the native panel header as a compact two-line identity/status block with a dedicated right-aligned action group, tighter frame inset, compact timestamp, and explicit Close boundary.
* Moved the cockpit to Omarchy's native `Panel` and `KeyboardPanel` architecture.
* Separated telemetry collection, diagnostics, and runtime-control ownership.
* Hardened protocol parsing, private writes, cookie redaction, and export filtering.
* Raised the helper baseline to OTP 27 / Elixir 1.18.
* Expanded the release gate with compilation, integration, Credo, Dialyzer, and protocol validation.

### Fixed

* Fixed Flight Recorder View A/View B and Compare result switching.
* Fixed keyboard handling for focused native controls.
* Fixed panel geometry, focus, and dismissal regressions.
* Fixed the Investigation `TextEdit` implicit-height failure.
* Replaced unstable Flight Recorder timestamp selectors with retained frame ranges.
* Preserved historical A/B selections while live collection continues.
* Preserved recorder ordering across wall-clock changes.
* Capped desktop status IPC responses.
* Restored dirty CPU scheduler state alongside normal scheduler rollback.

## [1.0.0] - 2026-09-05

### Added

- Omarchy Quattro service/bar-widget/panel plugin under `nshkr.beam-deck`.
- Graceful missing-BEAM, no-workload, OS-only, attached, and auth/unreachable states.
- Mise-first onboarding and stale-shell-PATH `mise exec` recovery.
- Local `/proc` BEAM census with command-line cookie redaction and deep-node OS PID correlation.
- EPMD, explicit-node, and learned-peer discovery with per-node cookie env references.
- Deep VM limits/memory/scheduler/run-queue inspection and capped hot-process sampling.
- Local-only scheduler density, demand-weighted recommendations, live reversible normal/dirty scheduler controls.
- Per-scheduler wall-time utilization while the panel is open with restoration on close.
- Mailbox/rate, run queue, VM-limit, required-node, expected-link, and registered-process churn alerts.
- Node-up/down event capture and configured directional topology contracts.
- OTP 28+ opt-in isolated-trace Deep Events through a transient namespaced Erlang probe.
- Capped in-memory history with full-window downsampling.
- Real OTP peer integration tests and multi-version GitHub Actions matrix.

[1.2.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/releases/tag/v1.0.0
