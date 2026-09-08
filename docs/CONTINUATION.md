# BEAM Deck continuation checkpoint

Paused at the operator's request on 2026-09-07 after completing the current implementation and its local gate. Resume from this checkout, not from main or an older plan.

## Repository and documents

* Root: `/home/home/.config/omarchy/plugins/com.nshkr.beam-deck`.
* Branch: `feat/operator-mission-control`; origin `git@github.com:nshkrdotcom/omarchy-beam-deck.git`.
* Community research plan: `docs/COMMUNITY-FEATURE-PLAN.md`, mirrored at `~/Documents/BEAM-Deck/community-feature-plan.md`.
* This handoff: `docs/CONTINUATION.md`, mirrored at `~/Documents/BEAM-Deck/CONTINUATION.md`.
* Earlier mission-control plan: `docs/OPERATOR-PLAN.md`, mirrored at `~/Documents/BEAM-Deck/operator-mission-control.md`.
* Prior checkpoint `f5a0351`; community plan `376f8d1`; tested/pushed backend milestone `21d50a7`. This checkpoint is their next implementation descendant. Resolve its exact hash with `git log -1 --format=%H` and verify `git rev-parse HEAD '@{upstream}'`; avoid embedding a self-referential commit hash in its own file.

Read current `AGENTS.md` instructions if any appear, plus the Omarchy skill/plugin guide and capture guide before native captures. Preserve the main title's host font tokens/placement, five-action rail order/padding, native KeyboardPanel geometry, shared pointer/IPC/bar-key route, editor-first PanelKeyCatcher and persistent helper lifecycle. The sibling Tactical Display repository is unchanged. The operator's documentation vocabulary restriction remains in force; describe concrete limits and dimensions.

## Implemented and tested

The research ranks process activity, ETS growth and exact-PID stack observations as the next useful connected workflows. All three now have backend collectors, typed protocol commands, cancellation, native QML controls, measured reports and explicit copying. Other ranked ideas (whole supervision browser, sockets, application telemetry) are alternatives for later work, not partially implemented promises.

* `Diagnostics.Window`: two explicit admitted metadata passes. Process admission uses `min(max_process_scan,10000)`; ETS uses at most 256 rows and honors lower settings. There is no extra continuous sampler or second retained history engine.
* `Diagnostics.Interval`: same-incarnation/exact-identity comparisons; signed memory/mailbox/element deltas; reductions/s from comparable counters; unmatched rows have null deltas, reset counters have no rate. At most 60 ranked rows selected across relevant metrics.
* `Diagnostics.StackSample`: one exact PID, up to 20 observations at 250ms plus RPC time; status counts, argument-free stacks, actual span and resource deltas. Frequency is not CPU time or allocation attribution. No GC, tracing or code installation.
* `process_window`, `ets_window`, `sample_process`: require request ID, node, expected creation and 1000/5000ms duration; stack sampling also requires PID. Collectors recheck identity independently of dispatch authorization.
* `cancel_job`: owner/ID-selected interactive cancellation. Panel close/historical state and owner death retain existing cleanup. It cannot cancel safety recovery or exports.
* `DiagnosticWindow.qml`: reused in Process and ETS, five-row paging, local filter/sort, exact process/owner pivots that reveal the inspector, sample-frequency bars and expandable stacks. Target/session/history changes reject obsolete replies. Existing service job retention remains 32 jobs/120 seconds.
* Existing hot-set admission now includes reduction leaders even when mailbox and memory rankings differ. ETS metadata now carries a digest of the underlying table identifier so name reuse cannot imply continuity.

README, changelog, architecture, protocol, configuration, security and operator workflows document the current behavior. Survey reports can be copied but are not automatically inserted into the recorder or ZIP.

## Actual validation

Final local logs are private external artifacts in `/tmp/beam-deck-community-evidence`:

| Evidence | Result |
|---|---|
| `checkpoint-check-final.log` | Full `make check` passed: 109 default ExUnit/23 integration exclusions, all 132 with real peers; 29 JS and 5 Python tests; formatting, warnings-as-errors compilation, strict Credo, Dialyzer zero errors; actual launcher protocol, 46 JSONL messages |
| `checkpoint-qt.log`, `checkpoint-qt15.log` | 29 passing results each, including setup/cleanup, normal and 1.5 scale; real production components/native controls with isolated host inputs |
| `checkpoint-native-lint.log` | Actual installed qs import root resolves; real missing-import negative test preserved. Dynamic host-token lint warnings are not native runtime acceptance |
| Manifest / whitespace | `omarchy plugin validate .` and `git diff --check` passed |
| Earlier backend CI | All three OTP27/Elixir1.18, OTP28/1.19, OTP29/1.20 combinations passed on `21d50a7`; inspect the checkpoint's new CI separately |

Local versions: OTP29.0.6 / ERTS17.0.6, Elixir1.20.4, Qt6.11.2, Quickshell0.3.1. External Mix caches remain `/home/home/.cache/beam-deck/dev/_build` and `/home/home/.cache/beam-deck/dev/deps`. Use the resolved toolchain PATH; do not automatically install or upgrade anything.

TDD artifacts include `interval-{red,green}.log`, `peers-{red,green}.log`, `cancel-protocol-{red,green}.log`, `wire-{red,green}.log`, `ui-model-{red,green}.log`, `ui-qt-red.log`, `ui-pivot-red.log`, `ui-results-green.log`, `collector-identity-{red,green}.log`, and `admission-{red,green}.log`. Intended failures covered missing commands/measurements/cancellation, wrong incarnation, omitted reduction leaders, result paging, late replies and missing scroll reveal. A Qt test initially counted button text children as extra controls; that fixture was corrected. A stack-bar selector was added for geometry testing, not claimed as a product bug. Strict formatting caught a temporary missing delimiter during refactoring; it was corrected before the final gate. The first checkpoint gate was interrupted by the session permission transition after static checks; only `checkpoint-check-final.log` is the completed gate.

## Next work when explicitly resumed

1. Recheck root/branch/status/remotes and upstream. Run `gh run list --branch feat/operator-mission-control --limit 3` and inspect this checkpoint's run. Fix any genuine CI regression before further implementation.
2. Perform focused native acceptance of the three new controls on a disposable peer: process window and exact pivot, ETS growth/owner and named replacement, stack frequency/expansion, single cancellation, close/historical cancellation, and copy privacy canaries if clipboard restoration is prepared. Use actual pointer and IPC openings; verify title/rail against the existing reference and actual shared geometry. Production Qt coverage is not a screenshot claim.
3. Verify that the live host actually loaded the new QML/helper. It was not restarted or proven updated during this checkpoint. Before any necessary restart, inspect status for a user-owned trial/probe/operation and announce the restart. Do not change workstation settings. Native evidence from the previous mission-control tranche does not validate these new controls.
4. Keep runtime output, fixture builds and captures under `/tmp` or private state/cache directories outside the watched plugin tree. Prior external input helpers remain `/tmp/tactical-pointer-check.wAn1rl/click` and `/tmp/beam-deck-operator-evidence/input/bar-key`; verify they still exist and their screen coordinates/keycodes still match the host before use. Do not type into an unverified surface.
5. Add regressions only for demonstrated failures, make scoped corrections, then update research plan/validation evidence and synchronize Documents copies before guarded commits/pushes. No long desktop soak or repeated 50-cycle run is requested. The user explicitly prioritized useful feature work and then asked for this pause.

No native acceptance claim is made for the new workflows yet. Optional follow-up runtime coverage could strengthen active-work sampling and mid-window process-exit cases beyond current waiting-stack/ended-PID, census, ETS replacement, protocol cancellation and identity tests; do not silently call those extra cases already tested.

## Cleanup and pause state

Read-only final status showed the panel closed, live mode, zero active/queued/UI jobs, no trial/probe and no watches. Fixture peers were stopped by test teardown; a final process check found none. The existing shell-owned helper remains, as designed. No new native test peer, clipboard action, saved preference change or workstation change was made in this tranche. User workloads, watches, exports and journals were not modified. No test or acceptance runner should remain active after this checkpoint. Pause after the final commit/push; do not begin the next native step automatically.
