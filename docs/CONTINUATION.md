# BEAM Deck 1.2.0 delivery record

Date: 2026-09-08. Repository: `/home/home/.config/omarchy/plugins/com.nshkr.beam-deck`. Origin: `git@github.com:nshkrdotcom/omarchy-beam-deck.git`. Version 1.2.0 includes all changes since 1.1.0, including the identifier migration in `ff2956a`. The user authorized main merge, push and local/remote feature-branch removal. Resolve final commits from git history; no release tag/publication was requested.

## Delivered scope

The original operator mission-control tranche is documented in OPERATOR-PLAN.md. The community tranche in COMMUNITY-FEATURE-PLAN.md delivers explicit process activity windows, ETS growth windows and exact-PID stack sampling, with cancellation, filtering, paging, measured units, exact inspection pivots and safe copy projections. These are on-demand diagnostics, not additional continuous samplers. The broader topology/socket/application-telemetry ideas remain alternatives outside this release.

## Milestone 3 evidence

Release artifacts are in private `/tmp/beam-deck-release-evidence`, outside the watched source. `final-check.log` passes 109 default ExUnit (23 excluded), 132 including disposable real peers, 30 JavaScript and 5 Python tests; strict format, warnings-as-errors compilation, Credo and Dialyzer; actual launcher protocol passes with 45 JSONL messages. Message count varies with interleaved snapshots. `final-qt.log` passes 29 results; `final-qt15.log` passes 29 at 1.5 scale. Actual-import lint, manifest validation and whitespace checks pass. Only OTP29 was executed locally. CI for release preparation fc1dbfb passed all OTP27/Elixir1.18, OTP28/1.19 and OTP29/1.20 jobs: https://github.com/nshkrdotcom/omarchy-beam-deck/actions/runs/34288375371 . The final startup fix `1d734d0` passed every CI job, including all three OTP versions and strict lint/Dialyzer: https://github.com/nshkrdotcom/omarchy-beam-deck/actions/runs/34289184821 .

Native acceptance found a real installed-host compatibility failure: `publicPluginManifest` in `/usr/share/omarchy/shell/shell.qml` removes `__sourceDir`. Service.qml used it to launch the helper, leaving the panel without samples. Production now resolves its own component location. `helper-path-red.log` fails for the missing path function; `helper-path-green.log` passes, including encoded spaces and invalid/non-local URLs. A shell restart proved that the actual corrected service starts and receives fresh telemetry. The main title and action rail were not edited.

Actual 1280x800, scale-1 Wayland screenshots inspected at full size:

* `screenshot-2026-09-08_13-02-45.png`: actual icon opening and populated Cockpit.
* `screenshot-2026-09-08_13-03-19.png`: process window, 51 matched processes over 5004ms, signed values and five-row paging. Filtered bd_test_worker and fresh exact PID pivot revealed its inspector (`13-03-59`). An older report correctly disabled its pivot until measured again.
* `screenshot-2026-09-08_13-04-36.png` and `13-04-46`: 20/20 waiting samples, frequency bar and expanded argument-free stack. Frequency is not CPU attribution.
* `screenshot-2026-09-08_13-05-05.png`: ETS window, 22 matched tables, test-owned table grew by 96 bytes and one element through its owner. No table content was collected.
* `screenshot-2026-09-08_13-05-26.png`: explicit cancellation. Closing during a subsequent request left zero active/queued jobs or probes (`closed.json`).
* `screenshot-2026-09-08_13-05-43.png` and `13-05-55`: pointer/IPC shared native panel; title-region pixel difference is zero (`title-difference.txt`), same container dimensions and five-action order/placement. Existing Qt tests cover protected geometry and keyboard ownership.

No ten-minute soak or new 50-cycle run was performed, per the revised user scope. Physical bar-position shortcut, alternate native scales/themes, native clipboard round trip, ETS owner pivot/replacement and historical cancellation were not repeated in this focused pass; earlier Qt/real-peer/protocol coverage remains explicitly distinct from native evidence. No claim covers all possible desktop configurations. Older boot-local `/tmp/beam-deck-community-evidence` and `/tmp/beam-deck-operator-evidence` artifacts are no longer present; their earlier results remain dated records in the plans.

## Cleanup and continuation

Only the disposable `bd_release_acceptance` VM was changed (one fixture-owned ETS insertion). Its scheduler count was confirmed as 3 before orderly shutdown. The initial asynchronous stop did not establish exit; a synchronous stop and process-absence check subsequently confirmed cleanup (`final-cleanup.json`). The panel was closed; no test watches, probes, trials, clipboard action or saved diagnostic preferences were introduced. The user explicitly authorized replacing the old ID in their existing shell.json entry; its position/settings were preserved. The renamed checkout and host were rescanned/restarted. No sibling code, user workloads, exports or recovery journals were changed. The persistent shell-owned helper remains by design.

The implementation and focused milestone 3 are complete. The implementation passed final CI. The final documentation commit records the authorized fast-forward delivery to main and feature-branch cleanup; continue from main after delivery. Future work should begin from the qualitative research ranking rather than repeat cosmetic work or waived endurance runs. Copies of this record and both plans are synchronized under `~/Documents/BEAM-Deck/`.

## Post-merge scheduler CI correction

Main CI run 34289462481 failed OTP29/Elixir1.20 in coupled scheduler rollback (131/132). The prior green branch CI did not establish freedom from intermittent failures. Repeated local execution reproduced transient dirty counts (2 instead of 1); a new 100-cycle production Remote.set_flag regression reproduced it in under a second. The first attempt overlapped another test controller and failed fixture setup; only `scheduler-red-valid.log` is product red evidence. `rollback-reproduce.log` preserves the initial failure.

OTP29.0.6 `erts/emulator/beam/erl_process.c` distinguishes requested `online` and observed `curr_online`; normal-change completion need not mean dirty threads have finished changing. The same integer coupling calculation was inspected in OTP27.3.4 and OTP28.0 source. Official reference, accessed 2026-09-08: https://www.erlang.org/doc/apps/erts/erlang.html#system_flag/2 . Exact implementation reference: https://github.com/erlang/otp/blob/OTP-29.0.6/erts/emulator/beam/erl_process.c . The integer formula is implementation evidence, not a new public API guarantee. Unsupported behavior fails confirmation rather than authorizing corrective writes.

SchedulerChange now performs one authorized mutation and confirms the requested count plus expected coupled dirty count through at most 50 read passes separated by 10ms. Every RPC retains the existing safety-owner deadline. It does not retry mutations, raise the existing timeout, overwrite external conflicts or treat timeout as proof of no side effect. Existing recovery journals and uncertain outcomes remain owned by BudgetTrial. Test waits now report terminal rollback failures immediately with recovery evidence instead of hiding them behind a generic polling timeout.

Correction local validation: `scheduler-green.log` passes the new 100-cycle regression; `rollback-green.log` passes all 17 recovery tests five times (85 test executions). `rollback-check.log` passes the full gate: 110 default/24 excluded, 134 total ExUnit including real peers, 30 JavaScript, 5 Python, strict formatting/compile/Credo/Dialyzer and 46 actual-launcher JSONL messages. Only disposable peers were mutated; test teardown owns their shutdown. No native appearance changes or screen tests were needed. CI on the correction must be checked separately from the failed main run.

Correction commit `d8e691c` passed all CI jobs (OTP27/1.18, OTP28/1.19, OTP29/1.20, static, strict lint/Dialyzer): https://github.com/nshkrdotcom/omarchy-beam-deck/actions/runs/34290289987 . This supersedes the earlier failed main run as implementation verification. The correction is delivered through a fast-forward to main; main CI is checked again after push.
