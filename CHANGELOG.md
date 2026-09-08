# Changelog

All notable changes to BEAM Deck are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased — operator mission control

* Integrate dated provider quality, filtered activity and exact recorder pivots into Triage.
* Add one explicit retained-frame intervention baseline with replace/clear, directional comparison and report export.
* Extend recorder graphs with node memory/queue/utilization/capacity views, measured spacing, honest missing segments, capped markers, precise keyboard/pointer selection and font-responsive legends.
* Preserve investigation context, exact missing targets, keyed rows, selected-control focus and actual scroll reveal. Add captured process/ETS filters and reversible inspection pivots.
* Reject stale view epochs and VM identities at control execution; stop Deep Events independently of diagnostic admission, while confirming cleanup separately.
* Keep missing measurements null, avoid false incident resolution on repeated/unavailable samples, retain dated failed-node/watch evidence, and project private ZIP contents through explicit nested allowlists.
* Add production Qt tests, real-peer/protocol regressions, strict native import lint and native failure-evidence/soak tooling. Preserve the native main title and action rail.
* Bound optional supervisor queries and preserve binary metadata; omit arbitrary OS command arguments and exclude internal remsh clients from runtime budgets.
* Label dated action receipts separately from current control state, and clarify small recorder scale spans.

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

[1.1.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/releases/tag/v1.0.0
