# Changelog

All notable changes to BEAM Deck are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/nshkrdotcom/omarchy-beam-deck/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/nshkrdotcom/omarchy-beam-deck/releases/tag/v1.0.0
