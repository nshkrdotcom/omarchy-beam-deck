# BEAM Deck 1.1 implementation handoff

**Status: implementation candidate, not release-validated.** All mandatory 1.1 capability paths have source/UI implementations and authored tests. Erlang/Elixir compilation, formatting, ExUnit, real-peer integrations, Credo, Dialyzer, actual-launcher runtime verification and Omarchy rendering were not executable here. No claim of production readiness, 100% visual polish or a green full release gate is made.

## Inputs and delivered form

Authority: attached `beam-deck-v1.1-implementation-docset(1).zip`. Actual base: attached `repomix-output(20260906-015959).xml`, not the older timestamp referenced inside the specification. The implementation review is [docs/IMPLEMENTATION-1.1.md](docs/IMPLEMENTATION-1.1.md). This is a changed/added-files overlay with repository-relative paths, no wrapper directory, deletions, unchanged base files, dependency artifacts or fabricated lockfile. The original binary preview was absent from Repomix and remains untouched.

## Exact implementation status

Production paths are implemented for forecasts, incident correlation, compact recorder/diffs/export, focused process/ancestry/binary-reference metadata, metadata-only ETS, persistent exact pins with closed-panel targeted sampling, leased whole-local scheduler trials, bounded matched local crash triage, native critical notification intents and the investigation UI. The original cockpit/scripts and protocol-v1 service/bar-widget identity remain; `Panel.qml` is now a bar-owned nested popup rather than a standalone manifest `panel` kind. Feature-to-code/test mapping is in the reviewed design document.

Safety refinements include asynchronous collection and pin resolution, bounded owned jobs, JSON input/depth/duplicate-key checks, private writes, export allowlists, exact-cookie scrubbing, VM-incarnation identity, stale/historical action gates, owned wall-time measurement, pre-effect control journaling and conditional retryable rollback. Existing original scheduler values survive Keep and subsequent changes.

These statements describe source paths, not successful runtime acceptance. The next agent must exercise and fix the actual code, not stop at this status list.

## Executed evidence

See the finalized [validation record](docs/validation-results.json). Production JavaScript state tests were run red/green for initial behavior and the later process-incarnation action guard. All 13 final cases passed. QML delimiter and embedded-JavaScript parsing checks were run, but no QML import/type/runtime or rendered-layout check was possible. Python syntax of the real-protocol harness was checked without executing its BEAM-dependent path. Bash/manifest/config/default/privacy/command-wiring structural checks are included in `make static`.

The container had Debian 13, Node 22.16, Python 3, Bash and jq. No Erlang, Elixir, Mix, Mise, Qt QML toolchain, Quickshell, Omarchy or ShellCheck was found. A package repository attempt did not provide access; runtime tests were not replaced by mocks or silently called passed. A lexical source audit found balanced Elixir do/fn/end blocks; this is explicitly **not** an Elixir parser/compiler result.

Actual source inventory: **97 ExUnit test declarations, 15 marked integration, 67 more declarations than the supplied base**. None were executed in this container. `make static` passed; `make check` exited 2 because its missing-Mix guard exits 127. The real-protocol harness exited 1 with an explicit missing-runtime message. `git diff --check` passed against the reconstructed base. Evidence files are under `docs/validation/`; Python/JavaScript/QML-source checks are not BEAM or desktop acceptance.

## First full-environment work

1. Apply the overlay to the exact base checkout and preserve local changes. Confirm `manifest.json`, `daemon/mix.exs` and bundle metadata say 1.1.0. Run `git diff --check` and `make static` before changing code.
2. Select a real supported OTP/Elixir pair through the workstation's existing Mise environment. Run `mise exec -- make deps`, `mise exec -- make format`, then `mise exec -- make check`. Formatting was not executable here and **is expected to require changes**. Fix compile/API issues and every ExUnit/strict-analysis failure; do not suppress warnings, weaken safety tests or replace remote paths with stubs. Preserve the actual generated dependency lockfile.
3. Run all three supported CI pairs and `python3 test/live-protocol.py` through that environment. Debug failures in the actual launcher/OTP path. The source includes 15 real-peer integration test declarations (12 new and 3 retained); their execution counts are currently unknown. Inspect default exclusions rather than claiming a default ExUnit run exercised them.
4. Validate and load on real Omarchy. Run the complete scenarios in [docs/VALIDATION.md](docs/VALIDATION.md), fix the QML against installed imports/APIs and capture actual screenshots. Test small panels, long labels, theme changes, scale, keyboard navigation and sticky safety controls; no visual acceptance has yet occurred.
5. Measure closed/open overhead, snapshot size, large process/ETS native enumeration behavior, overloaded/unreachable nodes, diagnostic queue saturation, notification cooldown and repeated lifecycle. Confirm normal cleanup, trace module/session behavior, actual target values and failure/recovery visibility. Replace pending acceptance with observed evidence only.
6. Review export/dump/privacy behavior using fixture canaries, then update README/validation/this handoff, commit the verified implementation and report any remaining host-specific issue precisely. Do not publish/tag as release-ready until the full gate is green and the target desktop scenarios are actually complete.

## Highest-risk checks, not excuses to omit features

**Compile/format/strict analysis:** generated Elixir code is source-reviewed and lexically audited only. Optional OTP APIs and builtin JSON callbacks need the actual compiler/runtime. Run formatting before the check-formatted gate; preserve behavior while refactoring for Credo/Dialyzer. No runtime or lockfile can be inferred from test source.

**Control races and failure paths:** verify original-value correction on a first mutation racing another controller, rollback after partial apply, expired Keep, rapid close/reopen epochs, uncertain RPC outcomes, external changes, owner loss and node reincarnation. First originals/journal failures must never be silently discarded. Restore/Keep do not constitute durable settings across target restart. SIGKILL/power loss is not guaranteed reversible by this agentless architecture.

**Identity and capabilities:** test node-local textual PID conversion against real foreign PIDs; process report freshness/creation checks; OTP 27 single-key `$ancestors` and Supervisor fallback; target word size; scheduler utilization with another reference owner; independently compiled helper/target Deep Events compatibility. Never compensate for a missing ancestry API by fetching the full dictionary.

**Large native lists:** `ets:all`, binary-reference metadata and observer process lists may allocate/transfer before helper truncation. Quantify the accepted operating envelope and improve capability/error wording rather than claiming a hard target-memory cap. If changing implementation, preserve no injected module on the ordinary read-only path.

**Crash identification:** multiple VMs can share cwd; timestamp/fingerprint matching is correlation, not proof. Delayed/incomplete or redirected dumps may be unavailable. Check the real disposable peer crash, fd identity checks and prefix-only parsing. Never read/export a full production dump to validate convenience.

**QML:** type imports, native control style, dimensions and accessibility were unrun. The Node body parser is not qmllint or an actual render. The bar now owns `Panel.qml`, which uses Omarchy `Panel` + `KeyboardPanel` instead of a hand-centered full-output `PanelWindow`; validate that contract on the real desktop, including the documented 1280x800 scrolling/dwindle regression, every bar edge, focus/edit controls and outside-click dismissal. Preserve the single helper service while fixing any target-specific QML issue.

## Operational recovery notes

For an active unkept trial, use Revert and verify actual target scheduler values. If rollback_failed, resolve the named unavailable/external-conflict condition and retry; do not clear the incident as a substitute. For kept/manual changes use Restore. An externally changed target is intentionally not overwritten automatically. Before manual changes, record current/original/applied evidence and ensure no second controller is racing it.

For an abrupt helper loss leaving inert `nshkr_beam_deck_probe` code, inspect the target via an authorized shell and verify no live owned probe/session remains before `code:delete(nshkr_beam_deck_probe)` and `code:soft_purge(nshkr_beam_deck_probe)`. Do not unload someone else's module or force-purge active code. Normal Deep Events off should perform acknowledged cleanup; fix that path if it fails in tests.

Do not share raw helper logs, env values, crash dumps or exports without privacy review. The retained remsh helper can expose an explicitly selected cookie in IEx argv to privileged/same-user OS observers; telemetry redaction is not OS credential isolation. Use normal protected cookie handling for sensitive workstations.

## Next-agent instruction

Implement/debug/harden the supplied code in the full environment until all supported-version runtime gates and actual Omarchy acceptance pass. Use the reviewed design and tests, preserve agentless/no-app-dependency/privacy/reversibility constraints, use TDD for every discovered defect, and update this handoff with exact observed results. Do not treat this file, generated test sources or static successes as proof of a finished release.