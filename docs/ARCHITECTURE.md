# BEAM Deck 1.1 architecture

## Scope and ownership

The Omarchy plugin stays `nshkr.beam-deck`, with one service, one fixed-slot bar widget and one panel. This is a local development control surface, not an in-app APM agent, permanent target service, cluster federation layer or generic arbitrary-RPC console.

```text
Omarchy shell / Quickshell
  Service.qml -> beam-deckd -> private JSONL FIFO bridge + stdin commands
    BarWidget.qml             BeamDeck supervision tree
    Panel.qml                 |-- DiagnosticTasks / CollectionTasks
      Investigation.qml       |-- Diagnostics (bounded job queue)
      TrialBar.qml            |-- BudgetTrial (control + recovery owner)
      DeckState.js            |-- Daemon (snapshot/evidence/protocol owner)
                              `-- Input (bounded command parser)

read-only collection workers -> /proc + trusted OTP erpc
explicit focused workers    -> process metadata / ETS metadata / bounded dump prefix
explicit Deep Events        -> temporary isolated target trace-session probe
BudgetTrial                 -> conditional scheduler flag changes and restoration
explicit local persistence  -> watchlist / diagnostic ZIP / existing helper log
```

`rest_for_one` orders task supervisors, queue, control owner, daemon and input. Failure of a lower-level owner restarts dependents; normal shutdown stops input/daemon before the budget owner. Budget control uses a longer supervised shutdown allowance to attempt restoration. No guarantee is made for untrappable helper/host loss.

## Transport and lifecycle

The Bash launcher applies `umask 077`, selects the direct or Mise toolchain, compiles into XDG cache and starts a small hidden distribution node. Normal VM/Mix output goes to the private state log; protocol output uses inherited fd 3. A missing toolchain emits an additive protocol-v1 onboarding envelope without Erlang. The minimum helper baseline is OTP 27 / Elixir 1.18 because JSON is implemented by OTP's built-in `json` module.

`Input` limits a command before parsing, accepts string keys, and never atomizes external commands, PIDs or fields. EOF requests normal application shutdown. `Daemon` emits sanitized structured messages. Quickshell owns one helper, keeps last successful state on errors and retries an exited helper with bounded backoff. A session identifier prevents old jobs/frame selections from being treated as results of a new helper.

## Collection is not input handling

`Daemon` dispatches a single collection task instead of calling remote APIs inside its poll callback. Collection has a 15-second owner deadline, a shared six-second remote candidate budget, four concurrent candidate workers and bounded remote calls. Candidate admission rotates so an unreachable prefix cannot permanently monopolize the budget. One completed collection feeds the new snapshot; timeout retains the last successful snapshot and produces an error instead of invented healthy zeros.

Discovery considers local EPMD, configured names and observed peers, not address ranges. Configuration/candidate sets are capped; newly admitted node-name atoms are lifetime-bounded. Command targets use existing atoms and must be observed attached/fresh where required. Local budget eligibility additionally requires corroborating the target's OS PID in the local census. Exact hostname aliases avoid treating a matching first DNS component as proof of locality. Tunnels and PID namespaces remain operator considerations.

Light collection captures VM capacity/memory/topology and local PID/start-time identities. Deep process scans occur at the open-panel cadence. Old process evidence is preserved between deep scans only within a matching VM incarnation/uptime sequence. Closing the panel never initiates a new full process/ETS/stack/binary scan solely for 1.1; pins use targeted lookups.

The old one-shot RPC wall-time toggle is not used for utilization. `scheduler:utilization(1)` owns measurement in a single remote caller lifetime, with capability failure shown as unavailable. This avoids relying on a system-flag reference that dies when its RPC process exits. The legacy API wrapper remains for compatibility/tests, not as a cross-poll measurement lease.

## Pure evidence pipeline

`History` stores bounded newest-first light samples. `Forecast` examines only the latest continuous per-node/per-metric segment, applies exponentially weighted linear regression and reports the exact sample/span/slope/fit/stability evidence. Hard-limit ETA exists only for process/atom/port limits; binary/ETS signals are growth-only. Confidence is a fit-quality summary, not calibrated probability.

`RestartChurn` tracks registered-name PID changes without guessing Supervisor intensity. `FlightRecorder` stores allowlisted compact frames, not the whole recursive snapshot. Frame sequence is independent of wall-clock ordering; selected export ranges follow sequence even after time adjustments. Frame IDs are session-local. Diffs suppress node counter comparisons across incarnation changes and mark missing comparable deep samples.

`Incidents` combines raw alerts, forecasts, selected events, nearby recorder process/scheduler observations, pin problems, budget failures and local exit/dump evidence. Incident identity deduplicates the same symptom family/node/metric or subject. Observed/correlated/heuristic labels are preserved at evidence level. Two quiet completed polls resolve an incident; bounded resolved retention supports context without storing history forever. Notification intent derives from critical transitions, not every repeated critical sample.

The recorder is pushed before incident correlation so a referenced nearest frame actually exists. A last-frame ID is captured for runtime disappearance before the next frame is written. Full recorder frames and job history are never embedded in routine snapshots.

## Focused diagnostics

`Diagnostics` has bounded active/queued work, one remote diagnostic per node, caller ownership, per-job deadlines, duplicate-ID rejection and cancellation. Its tasks return data to the daemon; they never write protocol output directly. Panel close cancels interactive process/ETS/frame/diff work. Exports and safety-relevant work are not discarded merely because a panel hides. Runtime control owns its journal outside cancelable diagnostic workers.

`Diagnostics.Process` queries a field allowlist, a bounded argument-free stack and only the single `$ancestors` dictionary key. There is no `sys:get_state`, mailbox extraction or full-dictionary fallback. Supervisor enrichment uses `which_child/2` when available; older releases use a bounded `count_children`/`which_children` fallback only for a small child set. Binary summaries aggregate reference metadata; identifiers, addresses and contents are discarded before presentation.

`Diagnostics.Ets` enumerates table identifiers, then reads a capped/concurrent metadata set. It converts words with the target's word size and reports scan/cap/unavailable counts. No table contents operation is called. Native `ets:all`, process binary-reference lists and observer process enumeration may allocate/transfer their native list before a helper-side cap applies. A worker deadline/cap is not a hard target-memory allocation limit; sensitive or extremely large VMs need operator judgment.

`Watchlist` persists normalized node/name identity, not PID, via `PrivateFile`. Adding a process pin performs asynchronous existing-name resolution; the daemon mailbox is not held by a remote lookup. Closed-panel observations use existing-atom lookup, `whereis`, and a small metadata list. Missing, unavailable and deferred remain distinct. Rotation plus a shared targeted-poll budget bounds steady-state cost.

## Control state machine

`BudgetTrial` is the single owner of scheduler changes, first-original values, trial timer and rollback failures. A trial must match the entire current local proposal, panel epoch and per-node incarnation/current value. Apply and rollback progress one node at a time, allowing the control mailbox to service close/Keep/Revert between bounded remote steps. The journal is written before requesting a mutation because timeout does not prove no side effect.

States: `applying -> active -> kept`, or `applying/active -> reverting -> reverted|rollback_failed`. Explicit recovery retries a failed journal. Kept values are still in the first-original map. A conflicting external value is not overwritten; failed entries remain recoverable. Keep/Revert bypass the generic diagnostics queue. Normal shutdown, panel close for an unkept trial, lease expiry, partial apply and daemon-owner loss trigger the documented restoration behavior.

A caller-visible timeout does not destroy the control owner's knowledge. GC is separate, explicit, and process-incarnation-gated by the UI and daemon. There is no automatic workload throttling or automatic GC remediation.

## Deep Events and crash triage

The namespaced Erlang probe is the only BEAM Deck bytecode intentionally loaded into a target. It checks module collision, uses an isolated OTP 28 trace session, monitors the daemon owner, rate-limits forwarded metadata and stops on overload. Stop acknowledgement precedes delete/soft-purge on normal teardown. Abrupt helper loss destroys the session via parent monitoring but can leave inert module code; see Security/Handoff rather than promising impossible remote unload guarantees.

`CrashDump` compares local PID plus start-time identity, then checks only that runtime's cached cwd. Fingerprints include device/inode/size/mtime/ctime. File descriptor identity is rechecked, read size is capped, and only selected header/scheduler/memory fields survive parsing. At most one delayed retry handles missing/unchanged/unmatched files. Disappearance is observed; the nearby dump match is correlation, not causal proof.

## Persistence and presentation

Only normalized watchlist state and explicit exports are new disk data. Export uses OTP ZIP, a fixed entry allowlist, per-frame redaction and a 16-MiB size ceiling. `PrivateFile` uses private directories, exclusive temporary files, file sync and atomic rename; an owner monitor removes temporaries on task death where the helper remains alive. Parent-directory races by a same-UID attacker are outside the trust model.

`DeckState.js` contains tested pure UI state rules, formatting and fixed notification argv construction. `Investigation.qml` uses bounded rows, progressive evidence disclosure, selectable plaintext and explicit requests. A visible historical/live boundary, stale-data age, job-specific results, process identity checks and sticky trial controls matter more than decorative animation. All theme/geometry/import/render acceptance remains a real-desktop gate, not established by delimiter or embedded-JavaScript checks.

## Upstream contracts used

Official OTP documentation: `erlang:process_info/2`, `erlang:system_info/1`, `erpc`, `scheduler`, `supervisor`, `trace`, `ets`, `json`, `zip`. Sources consulted are catalogued in [the implementation review](IMPLEMENTATION-1.1.md). Their runtime behavior is covered by authored peer tests but was not executable in the implementation container.
