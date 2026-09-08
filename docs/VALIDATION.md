# Validation evidence

The later community-feature checkpoint adds process/ETS interval surveys and stack sampling. Its complete local gate and remaining native acceptance are recorded in [CONTINUATION.md](CONTINUATION.md) and [COMMUNITY-FEATURE-PLAN.md](COMMUNITY-FEATURE-PLAN.md). The native captures and endurance record below belong to the preceding mission-control implementation.

## Operator mission-control tranche

Implementation branch: `feat/operator-mission-control`; untouched baseline `987ffb4`; tested implementation `a2578548629581d3745c69eb7d1ec3c204e97687`. This is feature-branch validation, not a release or a claim that every desktop configuration was exercised. The [execution plan](OPERATOR-PLAN.md) records research, individual red/green regressions, intermediate failures and commits. [Operator workflows](OPERATOR-WORKFLOWS.md) describes the resulting behavior.

The original September 6 container record remains in [validation-results.json](validation-results.json) and `docs/validation/` as historical evidence. Its missing-toolchain and unexecuted-BEAM statements do not describe this later installed-host run. Current structured results are in [operator-validation.json](operator-validation.json).

## Executed gates

Local environment: Omarchy `4.0.0.r2026.gf1b065c-1`, Quickshell `0.3.1-1`, Qt `6.11.2`, OTP `29.0.6` / ERTS `17.0.6`, Elixir `1.20.4` built for OTP 29. Existing resolved toolchains were used; no runtime/package upgrade was performed. Mix build/dependency caches stayed outside the plugin tree.

| Check | Actual result |
|---|---|
| `make check` | Passed: dependency resolution, strict formatting, warnings-as-errors compilation, 100 default ExUnit tests with 19 integration exclusions, then all 119 with disposable peers; strict Credo, Dialyzer zero errors, actual-launcher protocol |
| `make static` within that gate | 27 JavaScript tests, 5 Python native-tool tests, shell/manifest/source/privacy contracts passed |
| Actual-launcher protocol | Passed, 27 JSONL messages; real peer, process/ETS jobs, pins, exact frames/diff, historical/incarnation rejection, Deep Events teardown, private ZIP and normal EOF |
| `make qt` | 24 passing results including setup/cleanup, at scale 1 and `QT_SCALE_FACTOR=1.5` |
| `make native-lint` | Passed with the actual installed `qs` import root; a real missing-import negative test also passes |
| `omarchy plugin validate .` / `git diff --check` | Passed |
| CI on `a257854` | All jobs passed: static, lint, OTP27/Elixir1.18, OTP28/Elixir1.19 and OTP29/Elixir1.20 |

[CI run 34174115653](https://github.com/nshkrdotcom/omarchy-beam-deck/actions/runs/34174115653) includes default and real-peer ExUnit plus launcher protocol on every matrix row. Only OTP29/Elixir1.20 ran locally. Deep Events remains unavailable below OTP28.

Qt tests instantiate production components and installed native controls, isolating only host inputs/window/style dependencies. They test header metrics and alignment at 900/1270/1900 logical widths, larger font tokens, native editor/modifier ownership, selected-control focus, real Flickable reveal, stable delegates, exact historical continuity, recorder pointer/keyboard selection, expiry, caption reflow and inactive rendering. These are component tests; they do not establish native fractional-Wayland or multi-monitor rendering.

Latest full logs are private external artifacts under `/tmp/beam-deck-operator-evidence`: `m6-action-check.log`, `m6-action-qt.log`, `m6-action-qt15.log`, `m6-action-lint.log`. Earlier failing logs were retained separately; formatting/source-contract/test-adapter errors were corrected without relaxing the gates.

## Native evidence and interruption

Native host: one Virtual-1 output, 1280×800, scale 1, horizontal top bar. The actual clicked panel is the visual reference. Title comparison against the untouched baseline has zero differing pixels in the measured title region. Pointer and IPC use the same native panel, title, rail and eight-unit content padding. Rail captures have incidental cursor/hover/antialias differences; geometry was checked separately. No workstation fonts, themes, bar, keybindings, monitor configuration or sibling source was changed.

| Native workflow | Observed outcome |
|---|---|
| Pointer / shell IPC / configured physical bar shortcut | Passed; all open the shared native panel |
| 50 meaningful cycles on `a257854` | Passed: 17 pointer, 17 IPC, 16 physical-shortcut opens; each enters Investigate → Recorder. Dismissals: 13 Close, 13 Escape, 12 outside clicks, 12 bar clicks. Same shell/helper/target start identities |
| Neighbor popout switching | Actual pointer switched to the neighboring popout and back |
| Baseline / recorder | Capture, exact comparison, clear, private range export, memory traces, pointer/keyboard range selection, historical View A and G Go live observed |
| Process / ETS / watch | Corrected binary-reference report, 22/22 table metadata with target word size, owned-table pivot, native keyboard scroll and editor Ctrl+A, fresh GC and stale-action refusal observed |
| Exact identity / name following | Old PID explicitly reported process exited after a test-owned supervised replacement; registered-name watch followed the new PID |
| Scheduler trial | Disposable Elixir peer changed 12→5 online schedulers; visible countdown/Keep/Revert; panel close restored 12. Recovery saturation/conflict/owner-loss cases are real-peer automated coverage, not all native UI cases |
| Deep Events | Explicit start, panel-close stop, zero active/pending probes, and a separate target check confirming module unload |
| Remsh | Actual launcher connected to disposable Elixir node in a PTY; client exited normally |
| Export privacy | Native seven-entry ZIP mode 0600; fixture dictionary/binary/ETS canaries absent. Nested projection and arbitrary argv canaries also pass automated regressions |

Actual-size captures include `accepted-worker-inspection.png`, `accepted-owned-ets-result.png`, `accepted-gc-fresh.png`, `accepted-ended-exact-pid.png`, `accepted-watch-replacement.png`, `final-trial-active.png`, `accepted-probe-active.png`, `accepted-pointer-final.png`, `accepted-ipc-final.png` and `soak-scene-start.png`. Intermediate captures identify the revision under test in the execution plan; the final revision adds dated action receipts without changing layout or these workflows.

**The uninterrupted ten-minute soak did not pass.** After the 50 cycles and warmup, five live samples spanned 21.09 seconds before the panel closed. The runner failed correctly with `panel_closed_during_uninterrupted_soak`. Pre-cleanup evidence retained the same live shell/helper/target identities, fresh samples, no active/queued jobs, no probe and the close timestamp. These observations do not establish a crash or a close initiator. The operator reported closing the popup during testing and subsequently directed that further screen-occupying endurance work be skipped. The rerun and final 60-second closed phase were therefore removed from this tranche's acceptance scope; no long-run resource or leak-free claim is made.

Failure evidence remains in `native-acceptance-1/acceptance-failed.json` and `native-acceptance-1.log`. Earlier `native-smoke-1` through `native-smoke-4` failures remain separate from the passing `native-smoke-5` four-cycle/10-second smoke run. A return code or a mock is never counted as proof that a native click landed.

## Resource evidence and limits

Before implementation, matched 31-second closed/open profiles measured helper CPU 1.74%/1.41% of one core, ending RSS 95.27/95.55 MiB; shell CPU 0.64%/1.61%, ending RSS 671.07/715.91 MiB; target CPU 0.52%/0.23%, ending RSS 56.56/56.68 MiB. Full details and absolute FD/task/child counts are in `baseline-profile.json` and the plan.

The proposed warmed-run ceilings remain helper/shell/target RSS growth 32/128/16 MiB, mean one-core CPU 10/15/5%, and FD/task/child growth 2/4/0. They were not increased after failure and are not claimed passed for a ten-minute run. Passing a short growth ceiling would not prove zero growth or absence of leaks. Status `payload_bytes` currently measures QML string length (UTF-16 code units); it is not a general UTF-8 wire-byte counter. Collection duration is measured acquisition time, separately from IPC response latency.

Native missing-toolchain, dense cap-limit/very-long-name layouts, critical-notification bursts, live theme changes, alternate monitor/bar orientations and fractional-Wayland scales were not comprehensively run. Deterministic/Qt/real-peer tests cover their stated algorithm/control boundaries. No partial presentation-privacy toggle was added: operational identities remain visible; explicit exports use allowlisted projections and need review. No guaranteed rollback is claimed after SIGKILL, partition or host loss.

## Reproduction and cleanup

Use the installed resolved toolchain, or an explicitly selected supported Mise environment when needed:

```sh
make static
make check
make qt
QT_SCALE_FACTOR=1.5 make qt
make native-lint
git diff --check
omarchy plugin validate .
```

Native endurance is opt-in and requires an uninterrupted desktop interval, a test-owned target and supported verified input clients:

```sh
python3 -B scripts/native-acceptance.py \
  --evidence /tmp/beam-deck-native-acceptance-UNIQUE \
  --pointer /path/to/verified/virtual-pointer-client \
  --bar-keyboard /path/to/physical-code-10-keyboard-client \
  --target-pid TEST_OWNED_PID --cycles 50 --soak 600 --closed 60
```

The physical bar binding uses Super+Ctrl+code:10. Named-key `wtype` input assigns temporary keycodes and does not establish that physical binding; the tested client uses a standard XKB map through the supported virtual-keyboard protocol. Ordinary native panel key tests use `wtype`. The runner waits for dismissal to unmap/settle, refuses panel keys without the target surface, preserves failure evidence before cleanup, and never silently reopens a lost soak. No watched-tree writes/builds/commits belong inside such a run.

Both test-owned peers were stopped after restoration checks. The test watch was removed; no trial, probe or pending interactive job remains. The persistent shell helper remains as designed. No clipboard copy action or saved presentation preference was changed. Private test exports and failure/capture evidence were retained; user watches, exports and recovery journals were not deleted. Session-only recorder selection cleanup is recorded in the plan. The sibling Tactical Display checkout remains unchanged.
