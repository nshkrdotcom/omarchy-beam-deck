# Changelog

All notable changes to BEAM Deck are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Omarchy-native keyboard integration for the BEAM Deck panel: mnemonic Cockpit/Investigate workspace shortcuts, arrow/Vim context navigation, editor-safe fallback handling, Go Live, refresh, and an in-panel shortcut guide.

### Changed

- Rewrite the README around the complete 1.1 workflow, clearer install/update/remove guidance, keyboard operation, security boundaries, and concise Cockpit/Investigate documentation.

### Fixed

- Route the bar-launched cockpit through Omarchy's native `Panel` + `KeyboardPanel` contract instead of a hand-centered full-output layer surface, so monitor, bar-edge, gap, focus, dismissal and clamping geometry are shell-owned.


## [1.1.0] - 2026-09-06

Implementation candidate; see HANDOFF for unrun BEAM/desktop acceptance.

### Added

- Conservative process/atom/port capacity forecasts and binary/ETS growth-only signals with explicit fit/sample evidence.
- Deduplicated incident lifecycle, labeled evidence correlation, nearby recorder context, critical transition notification intents and bounded cooldown.
- Compact in-memory flight recorder, sequence-stable range selection, restart-aware diffs and private allowlisted diagnostics ZIP export.
- Focused argument-free process/ancestry/shared-binary metadata, metadata-only ETS inspection, persistent exact node/registered-name pins and closed-panel targeted observations.
- Whole-local-budget leased scheduler trials, sticky Keep/Revert status, conditional rollback and retained failure recovery/first-original Restore.
- Local PID/start-time disappearance tracking and matched bounded crash-header triage with one delayed retry.
- Triage/recorder/process/ETS/watchlist/budget investigation workspace with request-specific jobs, historical read-only mode, capture-age and VM-incarnation action protection.
- New pure/regression/real-peer test sources, production JavaScript state tests and an actual-launcher private-EPMD protocol harness.

### Changed

- Separate collection/diagnostic/control ownership; bounded queues, deadlines, async pin validation and urgent control recovery bypass.
- Additive protocol-v1 envelopes, strict bounded JSON decoding using OTP 27, private writes and stronger export/cookie redaction.
- Scheduler utilization sampled within one remote caller lifetime instead of relying on a transient RPC flag owner.
- Helper minimum is OTP 27 / Elixir 1.18; runtime target application dependencies remain zero. All configuration/default/version and operator/security/validation documentation updated.
- Full release gate fails when required tools are missing instead of implying partial checks are release acceptance.


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

[Unreleased]: https://github.com/nshkrdotcom/omarchy-beam-deck/compare/v1.1.0...HEAD
[1.0.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/releases/tag/v1.0.0

[1.1.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/compare/v1.0.0...v1.1.0
