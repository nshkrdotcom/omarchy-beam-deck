# Changelog

All notable changes to BEAM Deck are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-09-06

### Added

- Dedicated Investigate workspace with Triage, Flight Recorder, Process, ETS Lens, Watchlist, and Budget Trial views.
- Conservative process, atom, and port capacity forecasts plus binary/ETS growth signals with explicit sample, span, fit, stability, and evidence labeling.
- Deduplicated incident lifecycle with observed/correlated/heuristic evidence, nearby recorder context, bounded critical-notification cooldowns, and allowlisted follow-up actions.
- Compact in-memory Flight Recorder with exact frame identity, sequence-stable ranges, restart-aware diffs, and private allowlisted diagnostic ZIP export.
- Flight Recorder range navigator with live RSS trace, alert/event markers, click/drag historical selection, draggable A/B endpoints, Last 1m and All retained presets, keyboard endpoint adjustment, explicit Go Live behavior, and exact frame/range actions.
- Focused process diagnostics with ancestry, stack/current-function metadata, bounded shared-binary metadata, registered-name pinning, explicit refresh, and VM-incarnation-gated actions.
- Metadata-only ETS inspection with bounded leaderboards, owner navigation, word-size-aware memory reporting, partial/capped result handling, and no key/value collection.
- Persistent exact node and registered-process watchlist entries with targeted closed-panel observations and registered-name PID replacement tracking.
- Whole-local-budget leased scheduler trials with sticky Keep/Restore state, first-original restoration, conditional rollback, lease expiry, and retained rollback failure recovery.
- Local runtime disappearance tracking and bounded fresh `erl_crash.dump` header triage with PID/start-time identity checks, symlink refusal, fingerprint matching, and one delayed retry.
- OTP 28+ opt-in Deep Events using isolated trace sessions and transient namespaced probe code with overload protection and ownership-aware cleanup.
- Omarchy-native keyboard integration with Cockpit/Investigate mnemonics, arrow/Vim context navigation, editor-safe fallback handling, refresh, Go Live, close, and an in-panel shortcut guide.
- Real OTP peer integration coverage, production JavaScript state tests, source contracts, and an actual-launcher private-EPMD protocol harness.

### Changed

- Route the bar-launched cockpit through Omarchy's native `Panel` + `KeyboardPanel` contract so monitor, bar-edge, gap, focus, dismissal, and clamping geometry remain shell-owned.
- Separate collection, diagnostics, and control ownership with bounded queues, per-node limits, deadlines, async watchlist validation, and urgent recovery/control serviceability.
- Preserve protocol version 1 while adding bounded diagnostic/job/result envelopes and explicit unavailable/partial states.
- Use strict bounded JSON decoding, private writes, stronger cookie/export redaction, and no arbitrary RPC/eval surface.
- Sample scheduler utilization within one remote caller lifetime instead of relying on transient RPC flag ownership.
- Keep the 2-second light telemetry cadence independent from user interaction; historical Flight Recorder selection is fixed by exact retained frame IDs rather than mutable timestamp dropdowns.
- Rewrite the README around the complete 1.1 workflow, current keyboard controls, installation/update/removal, security boundaries, configuration, and Cockpit/Investigate operation.
- Correct Omarchy IPC documentation so BEAM Deck service methods target `nshkr.beam-deck` directly while shell-level panel routing remains under the shell target.
- Raise the supported helper baseline to OTP 27 / Elixir 1.18 while keeping monitored-application dependencies at zero.
- Make the full release gate fail closed when required validation tools are missing rather than presenting partial static checks as release acceptance.

### Fixed

- Prevent focused text fields, combo boxes, spin boxes, and other native controls from having editing/navigation keys stolen by the panel keyboard wrapper.
- Remove the obsolete hand-centered/full-output panel geometry path and its associated layout/focus regressions.
- Fix the Investigation `TextEdit` implicit-height regression that could break panel interaction/rendering.
- Eliminate unusable Flight Recorder FROM/TO timestamp dropdowns whose contents changed with every live telemetry refresh.
- Keep historical recorder A/B selections stable while live collection continues and clear historical selection when returning to live/helper state changes instead of silently rebinding it to newer frames.
- Preserve exact recorder sequence semantics across wall-clock/NTP changes so range ordering and exports cannot be inverted by timestamp regression.

## [1.0.0] - 2026-09-05

### Added

- Omarchy Quattro service/bar-widget/panel plugin under `nshkr.beam-deck`.
- Graceful missing-BEAM, no-workload, OS-only, attached, and auth/unreachable states.
- Mise-first onboarding and stale-shell-PATH `mise exec` recovery.
- Local `/proc` BEAM census with command-line cookie redaction and deep-node OS PID correlation.
- EPMD, explicit-node, and learned-peer discovery with per-node cookie env references.
- Deep VM limits/memory/scheduler/run-queue inspection and bounded hot-process sampling.
- Local-only scheduler density, demand-weighted recommendations, live reversible normal/dirty scheduler controls.
- Per-scheduler wall-time utilization while the panel is open with restoration on close.
- Mailbox/rate, run queue, VM-limit, required-node, expected-link, and registered-process churn alerts.
- Node-up/down event capture and configured directional topology contracts.
- OTP 28+ opt-in isolated-trace Deep Events through a transient namespaced Erlang probe.
- Bounded in-memory history with full-window downsampling.
- Real OTP peer integration tests and multi-version GitHub Actions matrix.

[1.1.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/releases/tag/v1.0.0
