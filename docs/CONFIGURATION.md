# Configuration reference - 1.1

Read at helper startup from `$XDG_CONFIG_HOME/beam-deck/config.json` (default `~/.config/beam-deck/config.json`). A missing file uses defaults. Existing 1.0 settings deep-merge with these defaults; no migration script or project changes are needed. Reload by restarting the helper/shell, not by assuming Refresh reloads configuration.

The file must be a regular non-symlink leaf of at most 262144 bytes. Invalid JSON/duplicate keys/wrong root/unsafe read produces a visible configuration warning and bounded defaults. Many wrong field types fall back locally; bounded integer values are clamped. Unknown keys are not application commands and have no defined behavior. The complete example is mechanically checked against `Config.defaults/0` by the static gate.

## Exact default values

| Key | Default |
|---|---|
| `poll_interval_ms` | `2000` |
| `deep_interval_ms` | `5000` |
| `history_points` | `450` |
| `max_process_scan` | `100000` |
| `mailbox_warn` | `5000` |
| `mailbox_critical` | `50000` |
| `mailbox_rate_warn` | `1000` |
| `process_usage_warn` | `0.8` |
| `atom_usage_warn` | `0.8` |
| `run_queue_per_scheduler_warn` | `1.0` |
| `nodes` | `[]` |
| `flight_recorder_points` | `150` |
| `incident_retention_ms` | `300000` |
| `critical_notification_cooldown_ms` | `300000` |
| `budget_trial_lease_ms` | `30000` |
| `watchlist_max_entries` | `64` |
| `watchlist_max_processes_per_node` | `16` |
| `forecast.enabled` | `true` |
| `forecast.min_samples` | `12` |
| `forecast.min_span_ms` | `60000` |
| `forecast.half_life_ms` | `90000` |
| `forecast.min_r2` | `0.8` |
| `forecast.min_stability` | `0.7` |
| `forecast.info_eta_ms` | `21600000` |
| `forecast.warning_eta_ms` | `3600000` |
| `forecast.critical_eta_ms` | `600000` |
| `forecast.binary_growth_min_bytes` | `33554432` |
| `forecast.binary_growth_min_fraction` | `0.2` |
| `forecast.ets_memory_growth_min_bytes` | `33554432` |
| `forecast.ets_memory_growth_min_fraction` | `0.2` |
| `forecast.ets_count_growth_min` | `32` |
| `forecast.ets_count_growth_min_fraction` | `0.2` |
| `diagnostics.max_concurrent_jobs` | `2` |
| `diagnostics.max_queued_jobs` | `16` |
| `diagnostics.per_node_remote_jobs` | `1` |
| `diagnostics.process_timeout_ms` | `1500` |
| `diagnostics.process_stack_frames` | `20` |
| `diagnostics.process_ancestry_depth` | `16` |
| `diagnostics.process_binary_entries` | `5000` |
| `diagnostics.ets_timeout_ms` | `5000` |
| `diagnostics.ets_max_tables` | `256` |
| `diagnostics.ets_concurrency` | `8` |
| `diagnostics.ets_top_rows` | `50` |
| `diagnostics.crash_dump_read_bytes` | `262144` |
| `diagnostics.crash_dump_match_window_ms` | `30000` |
| `diagnostics.crash_dump_retry_ms` | `2000` |
| `event_thresholds.long_gc_ms` | `100` |
| `event_thresholds.long_schedule_ms` | `100` |
| `event_thresholds.mailbox_enable` | `5000` |
| `event_thresholds.mailbox_disable` | `1000` |
| `event_thresholds.large_heap_words` | `8000000` |

## Meaning and safety bounds

**Cadence and history.** Poll is 500-60000 ms and deep cadence 1000-120000 ms. Polling is scheduled after a completed collection, so elapsed sample spacing includes collection cost. Deep scans occur only with the panel open. History is 12-2000 points; the independent compact recorder is 2-2000 frames (default 150). Process count above `max_process_scan` skips the bulk process scan; the safety ceiling is 100000. Native process enumeration races can still make the actual transient population larger than its preceding count.

**Alerts.** Mailbox warning/critical are positive message counts; rate is positive messages/second based on actual deep-sample timestamps. Process/atom warning values are nonnegative capacity fractions, with conventional defaults 0.8; values above 1 intentionally suppress those warnings rather than raising a separate validation error. Port-table warning currently uses the process-capacity fraction. Run-queue warning is a nonnegative queue/scheduler ratio. These are signals, not proof of application unresponsiveness.

**Forecasts.** `enabled:false` disables new forecast production. Sample count is 3-450; minimum span and half-life are 1000-3600000 ms. Fit/stability/growth fractions are 0-1, otherwise the default replaces them. ETA boundaries are 1000-86400000 ms and must satisfy critical <= warning <= info; an invalid ordering resets the three boundaries together. Byte growth minimums are 1-1099511627776, and ETS count growth minimum is 1-1000000. Both absolute and fractional observed growth gates must be met. Lowering sample/span/fit gates trades caution for noise; defaults are the reviewed conservative configuration. Only process/atom/port metrics have a hard-limit ETA.

**Incidents/notifications.** Resolved incident retention is 1000-3600000 ms; critical cooldown is 1000-86400000 ms. Incident output/retention is capped at 100, notification identity cache at 256. Two quiet completed polls resolve a symptom. Notification configuration does not automatically enable a process profiler, change schedulers or collect private payloads.

**Watchlist.** Entry limit 1-256, registered processes per node 1-64. Existing normalized files are hard-bounded to 256 entries/64 process pins per node even if a lower new-entry limit is configured; reduce existing pins explicitly to enforce a newly lower preference. Defaults allow 64 entries/16 processes per node. Only exact node or observed registered-name pins are supported, no regex/module-wide subscription and no durable PID pin. The separate `watchlist.json` is owned by the UI and carries schema 1. Do not put secrets in labels. Cheap targeted resolution is budgeted/rotated; `deferred` is not missing.

**Jobs.** Active workers 1-4, queued 1-28, remote-per-node exactly 1. This configuration controls the diagnostic queue, not the separate bounded overview collection. Process deadline 100-5000 ms, stack 1-64 frames, ancestry 1-16, binary summary 1-5000 references. ETS deadline 100-10000 ms, tables 1-1024, metadata workers 1-16, top rows 1-100. A smaller displayed set is not a hard allocation bound on the target's native enumeration. Partial states must remain visible.

**Crash triage.** Prefix 1024-262144 bytes; time match 1000-30000 ms; retry 100-5000 ms. Only the disappeared runtime's cached cwd plus `erl_crash.dump` is checked. These settings do not configure the target VM's dump generation/location. No full dump is exported.

**Budget lease.** 5000-30000 ms. Decreasing it can cause a large multi-node proposal to expire before all steps finish; failure then initiates conditional rollback. The maximum proposal is 16 rows. This is not a permanent scheduler policy or a guarantee under untrappable host/helper failure.

**Deep Events.** Long GC/schedule thresholds 1-60000 ms, enable mailbox 2-1000000, disable 1-999999 and forced below enable, large heap 1-1000000000 words. Defaults are 100 ms, 5000/1000 messages, 8000000 words. Actual activation is explicit and OTP 28+-gated; configuration alone never injects the probe.

## Node configuration

Up to 64 unique valid names, 255 bytes/name. Cookie environment references are valid environment identifiers of at most 128 bytes; the value is read only from the helper's inherited environment and must fit the bounded cookie path. Expected peers are at most 64 distinct valid names per node. `required:true` raises an unavailable-node signal; directional expected links are explicit contracts, not a guessed cluster partition map.

```json
{"nodes":[{"name":"worker@omen","cookie_env":"BEAM_DECK_OMEN_COOKIE","required":true,"expected_peers":["api@workstation"]}]}
```

No LAN enumeration is done. Observed peer discovery is capped, and lifetime node-name admission is bounded to 1024 new names until helper restart. Large/churning fleets are outside the intended local-development scope.

## Environment and paths

`XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and `XDG_STATE_HOME` override user paths. `BEAM_DECK_LONGNAMES=1` selects long names; `BEAM_DECK_NODE_HOST` must be an appropriate resolvable local host name. `BEAM_DECK_ERL_FLAGS` is a trusted advanced override for the helper; it is not a target VM profile. The launcher discards inherited `ERL_AFLAGS/ERL_ZFLAGS` and uses small helper scheduler defaults. Do not put cookies/secrets in arbitrary flag strings expecting automatic shell/runtime-log secrecy.

`BEAM_DECK_PROTOCOL_PATH` is launcher-internal inherited-fd routing. `BEAM_DECK_MISSING_POLL_SECONDS` controls the no-runtime retry loop for testing. `BEAM_DECK_INTEGRATION=1` enables real-peer ExUnit tests. Test/development build/cache paths are described by Makefile, separate from user application builds.

Use private directories; do not point XDG roots at shared or adversarial writable paths. Neither a reload nor config changes erase an active control journal; close/revert/restore intentionally before changing environments.
