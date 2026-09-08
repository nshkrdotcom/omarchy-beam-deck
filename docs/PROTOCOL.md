# Local JSONL protocol, version 1 (BEAM Deck 1.1 additions)

One JSON object per line. UI -> helper uses stdin; helper -> UI uses a dedicated inherited descriptor configured by `BEAM_DECK_PROTOCOL_PATH`. Ordinary VM output is not this protocol. Strings are string keys, not user-created atoms. EOF requests normal shutdown. Maximum inbound command size is 16384 bytes, enforced before JSON decode; nesting depth 32, duplicate keys and invalid syntax are rejected. No TCP/HTTP listener is introduced.

Version remains **1**. Clients must tolerate absent optional fields, unknown fields and explicit unavailable/partial results. The missing-runtime Bash envelope includes the new empty collection fields; it does not require a working BEAM.

## Snapshot

```json
{"type":"snapshot","protocol":1,"session_id":"session-...","at_ms":0,
 "onboarding":{"state":"ready"},"host":{"logical_cpus":0,"runtimes":[],"memory":{}},
 "nodes":[],"topology":[],"summary":{},"alerts":[],"budget":[],"history":[],"events":[],
 "forecasts":[],"incidents":[],"flight_recorder":{"frame_count":0,"timeline":[]},
 "watchlist":{"entries":[],"error":null},"budget_trial":null,"crash_triage":[]}
```

`at_ms` is wall time in milliseconds, used for presentation/evidence; lease/deadline enforcement uses monotonic time internally. `session_id` changes on helper restart. Missing-runtime snapshots may omit it. Node `creation` plus `uptime_ms` separates VM incarnations. A node's `attached:false`/`error` is not a healthy observation. `local` additionally requires OS PID corroboration before budget inclusion.

Legacy fields remain: host census, VM memory/limits, applications/peers, raw alerts, directional expected topology, budget suggestions, history and sampled hot/registered processes. `hot_processes_at_ms` identifies deep evidence age; a repeated hot array is not a new sample. Capability/unavailable fields are additive. New summary counts are `active_incident_count`, `critical_incident_count`, `forecast_warning_count`, `watched_problem_count`.

A forecast contains `id,node,metric,kind,severity,current,rate_per_second,fit_r2,stability,confidence,sample_count,span_ms,evidence_class,at_ms,summary`. Capacity kind adds finite `limit,eta_ms`; growth kind uses null `limit,eta_ms` and a `growth` delta. `confidence` is not a probability. Metric names are `processes`, `atoms`, `ports`, `binary_memory`, `ets_memory`, `ets_count`.

An incident is stable across repeated observations and has identity, title/summary, severity, active/resolved lifecycle timestamps, evidence and allowlisted proposed actions. Evidence records explicitly identify `observed`, `correlated` or `heuristic`; recorder references are session-local. Exact optional evidence payloads are metadata and may be absent. The client must not execute an action just because an incident includes it.

`flight_recorder` gives metadata only: `frame_count`, oldest/newest frame IDs and at most 150 timeline entries (frame/time, alert/event counts, RSS). Frames are fetched explicitly. `watchlist.entries` combines normalized persistent identity (`id,kind,node,name,label`) with current status and optional targeted process metadata. Status can be present, missing, node_unavailable, unavailable or deferred. A persistent entry never stores a transient PID on disk.

`budget_trial` is null or a public projection with `trial_id,status,rows,failures,reason,started_at_ms,expires_at_ms,remaining_ms,before_metrics`. Status is applying, active, kept, reverting, reverted or rollback_failed. Countdown display does not override the server's monotonic lease. `crash_triage` rows include disappearance identity/status and only matched capped header metadata when available.

## Request identity and async lifecycle

The following commands require a unique `request_id` of 1-64 ASCII letters/digits/period/underscore/colon/hyphen: `inspect_process`, `inspect_ets`, `recorder_frame`, `compare_frames`, `export_bundle`, `budget_trial_begin`. Queued/active IDs plus 128 recently finished IDs are rejected on reuse. Use a new ID after restart or retry; do not depend on an infinite durable dedup ledger.

```json
{"cmd":"inspect_process","request_id":"ui-101","node":"demo@host","pid":"<0.123.0>"}
{"type":"job","request_id":"ui-101","kind":"inspect_process","node":"demo@host","status":"started"}
{"type":"job","request_id":"ui-101","kind":"inspect_process","node":"demo@host","status":"complete","result":{}}
```

Terminal status is `complete`, `error` with a symbolic `error`, or `canceled`. `queued` is frontend-local optimistic state; the helper emits started/terminal or immediate rejection. Results can be partial metadata despite complete transport status. Errors do not contain raw exception/stack/credential terms. Late results must match request ID, kind and selected node, and cannot regress a terminal UI state. UI jobs retain at most 32 entries for 120 seconds.

Global active/queue defaults are 2/16; remote diagnostics serialize per node. Interactive diagnostics are canceled on panel close. Export and control/recovery are not canceled like read-only inspection. A timeout is not proof that a remote side effect did not happen; authoritative trial state is separate.

## Commands

| Command | Fields and semantics |
|---|---|
| `refresh` | Request a fresh poll; does not start overlapping collections. |
| `panel` | `open:boolean`; controls deep cadence, interactive cancellation, trace teardown and unkept trial rollback. |
| `inspect_process` | `request_id,node,pid`; fresh observed attached node, open panel. Node-local PID string must be `<0.N.N>`. |
| `inspect_ets` | `request_id,node,sort`; sort is `memory` (default) or `size`; metadata only. |
| `recorder_frame` | `request_id,frame_id`; retained compact frame, otherwise `frame_expired`. |
| `compare_frames` | `request_id,from_frame_id,to_frame_id`; directional diff of two retained frames. |
| `export_bundle` | `request_id`, optional nullable `from_frame_id,to_frame_id`; omitted bounds select all retained frames. No output-path field is honored. |
| `watchlist_add` | `entry:{kind:"node"|"registered_process",node,name?,label?}`; node/name must be observed. Process observation is asynchronous. |
| `watchlist_remove` | `id` of a normalized pin; persistence failure leaves prior state. |
| `budget_trial_begin` | `request_id,rows:[{node,current,suggested}]`; 1-16 rows exactly matching the entire current local recommendation, not a partial proposal. |
| `budget_trial_keep` | `trial_id`; only active unexpired trial with open live panel. Direct control-owner path. |
| `budget_trial_revert` | `trial_id`; direct recovery path, allowed without an open panel; retries rollback_failed. Kept settings use Restore. |
| `set_schedulers` | `node,value` integer 1-1024, subject to target limits; explicit legacy control, first-original retention. |
| `set_dirty_schedulers` | Same, for dirty CPU schedulers online. |
| `restore` | `node`; conditional first-original restoration, with failure detail instead of false success. |
| `gc` | `node,pid`, optional `expected_creation` nonnegative integer; new UI always supplies it after fresh explicit process confirmation. |
| `deep_events` | `node,enabled:boolean`; explicit OTP 28+ probe activation or acknowledged teardown. |

Daemon authorization is independent of string-shape validation. It checks observed attached targets and snapshot age; command names do not admit arbitrary RPC, atoms or shell code. Runtime mutations and focused diagnostics recheck a 10-second snapshot window, view epoch and exact known creation at execution. The scheduler safety owner also validates the epoch/creation before manual application. General node admission retains its 30-second ceiling. Historical mode is a daemon-enforced read-only context; a same-user client can explicitly request live mode, so this is not an authentication boundary.

## Result projections

Process result: `node,creation,pid,at_ms,registered_name,status,current_function,initial_call,stack,ancestry,binaries,warnings`, plus mailbox/memory/reductions/heaps. Functions contain module/function/arity and optional source metadata, never actual arguments. Ancestry has capped PID/name and child-relation metadata. Binaries report sampled/total entries, referenced bytes, partial/status and top byte/reference counts, not identities or contents.

ETS result: word size, attempted/scanned/total/omitted/unavailable counts and partial flag, plus `top` rows. Rows include id/name presentation, type/protection, owner/name, size, memory words/bytes and named-table status. Expired/unreadable tables are unavailable, not fabricated zero-valued healthy rows.

Frame result: frame ID/time, compact host/summary/nodes, selected new events/alerts/forecasts. It never recursively embeds history or another recorder. Diff result: IDs/times, summary deltas, stable node additions/removals/attachment/restart changes, counter/memory deltas, comparable hot-set entry/exit, sampled restart churn/deltas and new/resolved alert IDs. Unknown/cross-incarnation deltas are null, not zero.

Export result: generated private `path,bytes,frame_count,privacy`. The exact seven archive entries are documented in README/Validation. A result path is operational metadata, not a request to open/upload/execute it automatically.

## Other helper messages

`event` contains one capped runtime/Deep Event. `action` contains a legacy/watchlist outcome. Scheduler/GC/recovery commands can also produce terminal `job` messages with helper-generated `action:*` IDs, even though the caller did not request async identity. `budget_trial` carries an immediate public trial update independently of polling. `error` contains a symbolic error and optional safe explanation. `notification` is an intent containing severity/urgency/title/body/incident identity; `Service.qml` executes only a fixed native notification argv.

## Failure behavior

Invalid/oversized JSON is drained through the next newline and rejected; subsequent lines remain usable. Unsupported/partial target capabilities do not crash the shell. Frame expiry, duplicate requests, queue saturation, process exit, remote deadline, private write failure, trace collision and rollback conflict each remain visible failures. A cleared UI error on a later successful snapshot does not prove an earlier mutation was reverted; trial status/Restore evidence is authoritative.

## Operator mission-control additions (protocol 1)

`view` accepts `historical:boolean`. Entering historical mode increments the view epoch, cancels interactive jobs, stops optional probes and revokes the live permission held by unkept trials (which then roll back). Going live does not repeat an intervention. Revert remains independent of ordinary diagnostic saturation.

Focused inspection and scheduler/probe/GC commands accept an optional nonnegative `expected_creation`; the UI supplies it for focused inspections and GC. Legacy callers still undergo daemon target/epoch checks. Request and frame IDs are exact; helper sessions never share frame identity.

Snapshots include `sample_mono_ms`, `collection` (duration/cadence/deep/status) and `provider` (panel/historical epoch, capped job counts/oldest wait, probe counts, prior successful capture and capped lifecycle reasons). Collection metadata describes the last capture, not a promise that a pending RPC succeeded. Status IPC adds visible panel/workspace/tab, snapshot string length (`payload_bytes`, currently UTF-16 code units rather than a general UTF-8 byte count), UI-job/watch counts and these allowlisted health fields.

`flight_recorder.activity` retains 200 observed safe change explanations, at most 64 per sample, with cumulative `omitted_activity`. Each has exact frame/sequence/capture time, node/domain/kind, optional registered name/PID and allowlisted changed field names. Frames retain immutable activity/findings/watch context. The timeline carries at most 150 points and 16 node metric projections each, plus omitted frame/node counts. Missing metrics remain null; process scans report status, scanned/reported/returned counts and admission limit.

Comparison adds `utilization_delta_pp`, `occupancy_delta_pp` and comparable captured `hot_changes` (mailbox/memory deltas and reductions/second). Equal hard limits and known unchanged VM creation are required. `pp` means percentage points. Repeated deep samples cannot produce a new rate. A/B frames remain ordered by sequence even if wall time reverses.

The ZIP's text entry is an operator report. A selected-range report uses its last historical frame; `current-snapshot.json` and the separately named current incident/event/crash companions still describe export-time live evidence. All companion JSON and frames use nested allowlists; unknown extension fields are omitted. The report is capped at 64 KiB and the existing 16 MiB uncompressed/archive limit still applies.
