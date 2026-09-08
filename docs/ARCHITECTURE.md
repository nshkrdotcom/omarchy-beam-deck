# BEAM Deck 1.1 architecture

## Scope and ownership

The Omarchy plugin stays `com.nshkr.beam-deck`, with one service, one fixed-slot bar widget and one panel. This is a local development control surface, not an in-app APM agent, permanent target service, cluster federation layer or generic arbitrary-RPC console.

```text
Omarchy shell / Quickshell
  Service.qml -> beam-deckd -> dedicated JSONL fd + stdin commands
    BarWidget.qml             BeamDeck supervision tree
    Panel.qml                 |-- DiagnosticTasks / CollectionTasks
      Investigation.qml       |-- Diagnostics (capped job queue)
      TrialBar.qml            |-- BudgetTrial (control + recovery owner)
      DeckState.js            |-- Daemon (snapshot/evidence/protocol owner)
                              `-- Input (capped command parser)

read-only collection workers -> /proc + trusted OTP erpc
explicit focused workers    -> process metadata / ETS metadata / capped dump prefix
explicit Deep Events        -> temporary isolated target trace-session probe
BudgetTrial                 -> conditional scheduler flag changes and restoration
explicit local persistence  -> watchlist / diagnostic ZIP / existing helper log
```

`rest_for_one` orders task supervisors, queue, control owner, daemon and input. Failure of a lower-level owner restarts dependents; normal shutdown stops input/daemon before the budget owner. Budget control uses a longer supervised shutdown allowance to attempt restoration. No guarantee is made for untrappable helper/host loss.

## Transport and lifecycle

The Bash launcher applies `umask 077`, selects the direct or Mise toolchain, compiles into XDG cache and starts a small hidden distribution node. Normal VM/Mix output goes to the private state log; protocol output uses inherited fd 3. A missing toolchain emits an additive protocol-v1 onboarding envelope without Erlang. The minimum helper baseline is OTP 27 / Elixir 1.18 because JSON is implemented by OTP's built-in `json` module.

`Input` limits a command before parsing, accepts string keys, and never atomizes external commands, PIDs or fields. EOF requests normal application shutdown. `Daemon` emits sanitized structured messages. Quickshell owns one helper, keeps last successful state on errors and retries an exited helper with capped backoff. A session identifier prevents old jobs/frame selections from being treated as results of a new helper.

## Collection is not input handling

`Daemon` dispatches a single collection task instead of calling remote APIs inside its poll callback. Collection has a 15-second owner deadline, a shared six-second remote candidate budget, four concurrent candidate workers and capped remote calls. Candidate admission rotates so an unreachable prefix cannot permanently monopolize the budget. One completed collection feeds the new snapshot; timeout retains the last successful snapshot and produces an error instead of invented healthy zeros.

Discovery considers local EPMD, configured names and observed peers, not address ranges. Configuration/candidate sets are capped; newly admitted node-name atoms are lifetime-capped. Command targets use existing atoms and must be observed attached/fresh where required. Local budget eligibility additionally requires corroborating the target's OS PID in the local census. Exact hostname aliases avoid treating a matching first DNS component as proof of locality. Tunnels and PID namespaces remain operator considerations.

Light collection captures VM capacity/memory/topology and local PID/start-time identities. Deep process scans occur at the open-panel cadence. Old process evidence is preserved between deep scans only within a matching VM incarnation/uptime sequence. Closing the panel never initiates a new full process/ETS/stack/binary scan solely for 1.1; pins use targeted lookups.

The old one-shot RPC wall-time toggle is not used for utilization. `scheduler:utilization(1)` owns measurement in a single remote caller lifetime, with capability failure shown as unavailable. This avoids relying on a system-flag reference that dies when its RPC process exits. The legacy API wrapper remains for compatibility/tests, not as a cross-poll measurement lease.

## Pure evidence pipeline

`History` stores capped newest-first light samples. `Forecast` examines only the latest continuous per-node/per-metric segment, applies exponentially weighted linear regression and reports the exact sample/span/slope/fit/stability evidence. Hard-limit ETA exists only for process/atom/port limits; binary/ETS signals are growth-only. Confidence is a fit-quality summary, not calibrated probability.

`RestartChurn` tracks registered-name PID changes without guessing Supervisor intensity. `FlightRecorder` stores allowlisted compact frames, not the whole recursive snapshot. Frame sequence is independent of wall-clock ordering; selected export ranges follow sequence even after time adjustments. Frame IDs are session-local. Diffs suppress node counter comparisons across incarnation changes and mark missing comparable deep samples.

`Incidents` combines raw alerts, forecasts, selected events, nearby recorder process/scheduler observations, pin problems, budget failures and local exit/dump evidence. Incident identity deduplicates the same symptom family/node/metric or subject. Observed/correlated/heuristic labels are preserved at evidence level. Two quiet completed polls resolve an incident; capped resolved retention supports context without storing history forever. Notification intent derives from critical transitions, not every repeated critical sample.

The recorder is pushed before incident correlation so a referenced nearest frame actually exists. A last-frame ID is captured for runtime disappearance before the next frame is written. Full recorder frames and job history are never embedded in routine snapshots.

## Focused diagnostics

`Diagnostics` has capped active/queued work, one remote diagnostic per node, caller ownership, per-job deadlines, duplicate-ID rejection and cancellation. Its tasks return data to the daemon; they never write protocol output directly. Panel close cancels interactive process/ETS/frame/diff work. Exports and safety-relevant work are not discarded merely because a panel hides. Runtime control owns its journal outside cancelable diagnostic workers.

`Diagnostics.Process` queries a field allowlist, a capped argument-free stack and only the focused `$ancestors` and `$initial_call` dictionary keys. There is no `sys:get_state`, mailbox extraction or full-dictionary fallback. Supervisor enrichment uses `which_child/2` when available; older releases use a capped `count_children`/`which_children` fallback only for a small child set. Binary summaries aggregate reference metadata; identifiers, addresses and contents are discarded before presentation.

`Diagnostics.Ets` enumerates table identifiers, then reads a capped/concurrent metadata set. It converts words with the target's word size and reports scan/cap/unavailable counts. No table contents operation is called. Native `ets:all`, process binary-reference lists and observer process enumeration may allocate/transfer their native list before a helper-side cap applies. A worker deadline/cap is not a hard target-memory allocation limit; sensitive or extremely large VMs need operator judgment.

`Watchlist` persists normalized node/name identity, not PID, via `PrivateFile`. Adding a process pin performs asynchronous existing-name resolution; the daemon mailbox is not held by a remote lookup. Closed-panel observations use existing-atom lookup, `whereis`, and a small metadata list. Missing, unavailable and deferred remain distinct. Rotation plus a shared targeted-poll budget bounds steady-state cost.

## Control state machine

`BudgetTrial` is the single owner of scheduler changes, first-original values, trial timer and rollback failures. A trial must match the entire current local proposal, panel epoch and per-node incarnation/current value. Apply and rollback progress one node at a time, allowing the control mailbox to service close/Keep/Revert between capped remote steps. The journal is written before requesting a mutation because timeout does not prove no side effect.

States: `applying -> active -> kept`, or `applying/active -> reverting -> reverted|rollback_failed`. Explicit recovery retries a failed journal. Kept values are still in the first-original map. A conflicting external value is not overwritten; failed entries remain recoverable. Keep/Revert bypass the generic diagnostics queue. Normal shutdown, panel close for an unkept trial, lease expiry, partial apply and daemon-owner loss trigger the documented restoration behavior.

A caller-visible timeout does not destroy the control owner's knowledge. GC is separate, explicit, and process-incarnation-gated by the UI and daemon. There is no automatic workload throttling or automatic GC remediation.

## Deep Events and crash triage

The namespaced Erlang probe is the only BEAM Deck bytecode intentionally loaded into a target. It checks module collision, uses an isolated OTP 28 trace session, monitors the daemon owner, rate-limits forwarded metadata and stops on overload. Stop acknowledgement precedes delete/soft-purge on normal teardown. Abrupt helper loss destroys the session via parent monitoring but can leave inert module code; see Security/Handoff rather than promising impossible remote unload guarantees.

`CrashDump` compares local PID plus start-time identity, then checks only that runtime's cached cwd. Fingerprints include device/inode/size/mtime/ctime. File descriptor identity is rechecked, read size is capped, and only selected header/scheduler/memory fields survive parsing. At most one delayed retry handles missing/unchanged/unmatched files. Disappearance is observed; the nearby dump match is correlation, not causal proof.

## Native cockpit presentation

The bar surface uses Omarchy's native `Panel`/`KeyboardPanel` contract rather than owning monitor geometry. `KeyboardPanel` is explicitly set to `padding: Style.space(8)` so BEAM Deck and Tactical Display share the same compact outer inset while Omarchy continues to own bar-edge gaps, clamping, and output placement. Inside that frame the chrome contract is: a two-line `identityBlock` at left, an elastic spacer, a right-aligned `headerActions` row with a persistent bordered Close affordance, then a themed `PanelSeparator` before workspace content. Major chrome gaps use Omarchy semantic spacing roles (`xxs`, `xxl`, `huge`) so shell spacing-scale preferences can change density coherently without changing the hierarchy.

The source-level contracts assert that structure, but they are not visual proof. Native acceptance must still cover clamped widths, theme/font/spacing scale changes, focus traversal, and real Quickshell rendering. Layout constants inside plots remain visualization geometry rather than desktop-chrome spacing and are intentionally not forced through the cockpit token scale.

## Persistence and presentation

Only normalized watchlist state and explicit exports are new disk data. Export uses OTP ZIP, a fixed entry allowlist, per-frame redaction and a 16-MiB size ceiling. `PrivateFile` uses private directories, exclusive temporary files, file sync and atomic rename; an owner monitor removes temporaries on task death where the helper remains alive. Parent-directory races by a same-UID attacker are outside the trust model.

`DeckState.js` contains tested pure UI state rules, formatting and fixed notification argv construction. `Investigation.qml` uses capped rows, progressive evidence disclosure, selectable plaintext and explicit requests. A visible historical/live boundary, stale-data age, job-specific results, process identity checks and sticky trial controls matter more than decorative animation. All theme/geometry/import/render acceptance remains a real-desktop gate, not established by delimiter or embedded-JavaScript checks.

## Upstream contracts used

Official OTP documentation: `erlang:process_info/2`, `erlang:system_info/1`, `erpc`, `scheduler`, `supervisor`, `trace`, `ets`, `json`, `zip`. Sources consulted are catalogued in [the implementation review](IMPLEMENTATION-1.1.md). Their runtime behavior is covered by authored peer tests but was not executable in the implementation container.
## Operator context and evidence ownership

`Service.qml` remains the one persistent shell-owned helper owner. Panel-close cancels interactive diagnostics and deep acquisition; capped light discovery and durable registered-name watches continue. `Investigation.qml` is retained across Cockpit transitions, with its clock/Canvas inactive when hidden. Cockpit stays live; returning to Investigate restores its frozen range and daemon read-only mode. Helper-session changes invalidate jobs and ephemeral inspection history. One baseline stores only frame/session/time/node/quality metadata in the service, never a second snapshot engine or a new disk preference.

FlightRecorder owns sequence identity, activity derivation, immutable frame context and A/B comparison. Activity stores safe changed-field names instead of sensitive before/after values. Missing/expired endpoints never rebound. KeyedRows updates existing delegate objects; ActionButton uses installed native focus styling and reveals focus in the actual ancestor Flickable. The protected header continues to use installed host title tokens, native buttons and KeyboardPanel geometry.

ControlAccess checks live panel, epoch, known incarnation and capture age immediately before execution; BudgetTrial independently checks scheduler-control epochs and target identity. Its memory journal still precedes mutation, and failed rollback remains evidence rather than success. Deep Events receives an immediate nonblocking stop request outside ordinary diagnostic admission; normal teardown separately confirms exit and unloads code. The existing `rest_for_one` supervision strategy is retained.

Projection defines nested retained/exported field allowlists. Generic redaction remains a second defense. Provider diagnostics expose capped counts and lifecycle reasons, not raw job payloads or credentials. Native acceptance records process start identities before cleanup and distinguishes panel loss from helper death; no cause is inferred from an empty log.

Focused process reports acquire binary metadata before optional ancestry. Each ancestor receives at most 200ms for supervisor-specific queries within the overall diagnostic deadline; an ancestor may be a live process with no supervisor API. Its unavailable child metadata must not starve the rest of the report.

Numeric `beam_deck_shell_<pid>` remsh clients are excluded with the persistent helper from automatic runtime discovery and host-budget participation. Arbitrary application command arguments are no longer retained by the OS census. Supervisor ancestry checks use only the OTP `$initial_call` key before sending supervisor requests.

## Interval diagnostic ownership

`Diagnostics.Window` performs two explicit captures separated by the requested interval; `Diagnostics.Interval` projects fields and compares exact identities using helper monotonic time. Process survey admission uses the lower of configured `max_process_scan` and 10000. It reuses the installed OTP Observer metadata census, retains at most that many rows per endpoint, and reports scan counts/races. ETS survey reuses the metadata collector with at most 256 rows per endpoint. These temporary endpoint sets are owned by a Diagnostics worker, not retained as another history engine.

`Diagnostics.StackSample` requests only status, current stack, memory, message-queue length and reductions for one exact PID. It stops after up to 20 observations and projects argument-free frames before output. All three workflows share the existing job queue, one active remote job per node, deadlines, epoch validation and owner cleanup. Single-request cancellation selects by owner and ID and only matches interactive jobs.

`DiagnosticWindow.qml` is reused inside Process and ETS. Its result rows are keyed, sorted/filtered locally and paged five at a time; a process/owner pivot reveals the real inspector in its Flickable. Stack bars update from captured results, with numeric counts and expandable stacks. Service jobs retain their existing 32-job/120-second limit. Target, session and historical-context changes clear request correlation handles. Copying uses a field projection capped at 64 KiB; no raw result serialization or automatic disk persistence is added. The protected main header and panel routes are unchanged.

The shell service resolves the helper relative to its own installed QML URL. It does not depend on private manifest source-path fields, which current Omarchy removes from the public plugin manifest.
