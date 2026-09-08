# Reviewed implementation design and scope traceability

## Authority and provenance

The supplied `beam-deck-v1.1-implementation-docset(1).zip` (product scope, architecture, feature specification, protocol/config, UI/UX, security, TDD, implementation sequence, acceptance and handoff) is the feature authority. Its reference to an earlier Repomix timestamp does not override the actual source attachment: implementation used `repomix-output(20260906-015959).xml`. Changes are packaged against the actual supplied source bytes and repository-relative paths. No claim is made to have separately read the three original idea files named inside the docset; their synthesis was already represented by the supplied specification.

The original source included no binary `preview.png` content. The overlay leaves it untouched. No deletion/manifest/checksum helper is required to install the overlay. This file records the revised implementation approach used in the code, not a substitute feature plan.

## Internal critique resolved in implementation

**Evidence-first, not another crowded dashboard.** Keep the original cockpit and add a separate investigation workspace. Triage progressively reveals evidence; stack/diff reports are selectable plaintext. Target selection, job state, capture age and an explicit live/history boundary are shared interaction concepts. A sticky safety strip makes a leased mutation visible regardless of selected tab. Color is supplementary to status/evidence labels; no continuous ornamental animation or expensive 3D effect is introduced.

**Responsiveness is an ownership property.** The base performed polling inside the daemon mailbox. Collection and diagnostics now run under separate task supervisors with capped concurrency/deadlines. Adding a process pin also resolves remotely outside the mailbox. Jobs are request-identified, panel/owner-aware and safe against late completion. Keep/Revert bypass ordinary work queues.

**A timeout is not rollback.** The scheduler owner journals before each side effect, rechecks incarnation/current value, and preserves uncertain outcomes. It owns first-original values across manual changes and Keep. Failed restoration is visible and retryable, not erased because a worker ended. A raced first mutation corrects its original to the actual value returned by OTP without losing a prior session original.

**Time travel must not target the present accidentally.** Recorder frame IDs and range selection use sequence; wall time is presentation. VM creation resets comparability and process report permissions. Historical mode cannot GC/change a live runtime, stale process reports cannot authorize actions, and helper restart invalidates pending views. Nearby deep evidence points at an actual retained frame, not an invented explanation.

**Forecast confidence must mean what was calculated.** Use explicit exponentially weighted regression, minimum sample/span gates, fit and monotonic-interval stability. Display ETA only for real process/atom/port hard limits. Binary/ETS use absolute plus fractional growth and never ETS exhaustion. Confidence is fit quality, not probability or proof of a leak.

**Privacy needs collection boundaries, not regex alone.** Query only the focused OTP ancestry/initial-call metadata keys; omit argument values, states, messages, ETS contents and binary identities. Project small data models before sanitization. Export only a fixed ZIP entry set to a private generated path, with exact-cookie filtering and explicit residual privacy warning. Crash triage is matched/capped and does not search disks.

**BEAM-specific correctness outranks superficial reuse.** The old transient RPC flag caller is not a lasting scheduler-wall-time owner; the measurement now occurs in one actual caller lifetime. Target process IDs are represented in node-local textual form, with a VM-creation guard on actions. Supervision APIs are capability-gated rather than forcing OTP 28 optimizations on OTP 27. Sampled churn is not declared restart intensity. Shared-binary references are not declared exclusive ownership.

**Do not conceal native enumeration cost.** Helper caps limit processing/output and retained memory but do not prevent every target API from materializing its native list. This is an explicit security/performance limitation, not a claim that on-demand observation is free.

## Feature-to-code/test map

All rows have implemented production paths and authored tests. Only the static/JavaScript portions were executable here; the table does not assert runtime acceptance.

| Required capability | Production entry points | Authored validation |
|---|---|---|
| Capacity and binary/ETS growth | `forecast.ex`, history samples, Triage forecasts | `forecast_test.exs` gates, noise/reset/limit/rate/ETA/growth cases |
| Incident correlation/lifecycle | `incidents.ex`, `daemon.ex`, Triage evidence/actions | `incidents_test.exs`, recorder proximity tests, notification transitions |
| Recorder, diff, private bundle | `flight_recorder.ex`, `diagnostics/bundle.ex`, Flight recorder UI | recorder identity/range/restart tests, real ZIP/private-file tests, live protocol harness |
| Focused process ancestry/binaries | `diagnostics/process.ex`, Process UI, creation-gated GC | projection tests and real OTP worker/supervisor/privacy integration |
| Metadata-only ETS lens | `diagnostics/ets.ex`, ETS UI | shape/word-size tests; real private/named table/cap integration |
| Persistent exact watchlist | `watchlist.ex`, `private_file.ex`, Watchlist UI | persistence/limits/symlink/error cases, actual registered PID replacement, live protocol |
| Whole-local-budget trial | `budget_trial.ex`, Budget UI, `TrialBar.qml` | proposal checks; real apply/Keep/Restore/expiry/owner death/partial apply/conflict recovery |
| Local exit/crash triage | `procfs.ex`, `crash_dump.ex`, incidents/frame links | stat/reuse tests; real local file matching/cap/symlink/retry tests; disposable actual VM crash |
| Native critical notifications | incident transition intent + fixed argv in `DeckState.js`/Service | cooldown/lifecycle unit tests; JS argv safety; live native desktop check pending |
| Safe transport/nonblocking jobs | `json.ex`, `input.ex`, `protocol.ex`, `diagnostics.ex`, Service | framing/depth/duplicate/queue/owner/deadline tests; production JS state tests; actual-launcher harness |
| Preserve 1.0 behavior | original cockpit/scripts/metadata/runtime_tools paths | original tests retained; missing-runtime static test now forced even on BEAM-enabled CI |

## Explicitly not added

No in-application telemetry dependency, daemon installed inside a target, automatic remediation, full supervision tree, mailbox/state browser, ETS data viewer, remote arbitrary eval endpoint, continuous profiler, persistent telemetry database, upload service, unbounded crash search or new whole-repository delivery. No claim of causality is manufactured from a stack, timestamp or fit score.

## Source contracts consulted

Primary documentation informed these implementation refinements; code/desktop acceptance is separate and still required:

- Erlang `erlang` reference: https://www.erlang.org/doc/apps/erts/erlang.html (process metadata/single-key dictionary, VM identity, scheduler flags and native counters).
- OTP `scheduler`: https://www.erlang.org/doc/apps/runtime_tools/scheduler.html (owned scheduler utilization sampling).
- OTP `supervisor`: https://www.erlang.org/doc/apps/stdlib/supervisor.html (optional `which_child/2`, capped older fallback).
- OTP `trace`: https://www.erlang.org/doc/apps/kernel/trace.html (isolated sessions/system events).
- OTP `ets`: https://www.erlang.org/doc/apps/stdlib/ets.html (metadata and word accounting).
- OTP `json`: https://www.erlang.org/doc/apps/stdlib/json.html (OTP 27 encoder/decoder callbacks).
- OTP `zip`: https://www.erlang.org/doc/apps/stdlib/zip.html (in-memory archive creation).
- OTP 27 observer backend source: https://github.com/erlang/otp/blob/OTP-27.3/lib/runtime_tools/src/observer_backend.erl (bulk process message/native enumeration behavior).
- Quickshell Process reference: https://quickshell.org/docs/v0.2.0/types/Quickshell.Io/Process/ (process ownership and I/O; installed Omarchy API remains a live validation requirement).

## Acceptance boundary

This code is not labeled production-ready by passing a syntax-adjacent check. It must compile, be formatted, pass all old/new ExUnit and real-peer cases, Credo, Dialyzer, actual-launcher protocol tests, supported-version CI and real Omarchy UI/lifecycle/performance checks. The exact validation status is maintained in [VALIDATION](VALIDATION.md); do not replace observed evidence with a generic "all features done" checklist.

The operator mission-control extension and its recorded validation are documented in [OPERATOR-PLAN.md](OPERATOR-PLAN.md), [OPERATOR-WORKFLOWS.md](OPERATOR-WORKFLOWS.md) and [VALIDATION.md](VALIDATION.md). Earlier implementation/validation statements above are the original 1.1 design record.
