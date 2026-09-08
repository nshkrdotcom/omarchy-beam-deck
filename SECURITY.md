# BEAM Deck 1.1 security and reversibility

## Trust boundary

BEAM Deck connects to Erlang distribution, which grants powerful remote execution capability to a party with the correct cookie and connectivity. An agentless client is not a sandbox or a read-only authorization role. Use it only with nodes you are authorized to control and on trusted distribution networks. Keep development cookies/ports private; normal transport is not asserted to be encrypted. Harden the deployment's distribution/TLS/network boundary separately.

The OS user running Omarchy, its plugin directory, the XDG configuration/state ancestors and monitored local development directories are trusted. A hostile same-UID process, root, compromised target VM or malicious peer with the cookie can defeat assumptions beyond this plugin's API. Local PID/hostname corroboration is not cryptographic physical-host attestation. Protect paths and investigate tunnel/namespace ambiguity before local scheduler trials.

## Data minimization precedes redaction

Production diagnostic code does **not** collect arbitrary process state, process messages, full dictionaries, ETS keys/values, binary contents/addresses or environment variables. Process ancestry reads only `$ancestors` and `$initial_call`; stack entries omit arguments. Supervisor child IDs are projected as metadata rather than arbitrary terms. ETS output is a metadata allowlist. Crash triage does not expose the raw file/prefix or heap/process sections.

Outgoing metadata is sanitized with depth/map/list/string bounds, sensitive-key filtering and exact known-cookie replacement, including atom keys/values. Export additionally excludes cwd/argv/command/config/config_path/cookie_env. Redaction is defense in depth, not proof that arbitrary data is safe. A previously unknown secret in a module name, label, source metadata or crash slogan cannot always be recognized. Review every export before sharing; names and counts can reveal internal architecture even without credentials.

The `/proc` census reads command arguments only to exclude BEAM Deck-owned clients; arbitrary arguments and command strings are not retained in runtime snapshots or emitted to the UI. Local cwd metadata remains for runtime labels and capped crash-header matching; exports remove it. Only configured/default known cookies are exactly scrubbed; cookies supplied solely to another unrelated process are not a universal redaction dictionary.

## Cookies and files

Config uses `cookie_env` names, not cookie values. The variable must exist in the actual shell/helper environment. Cookie value creation remains capped to validated config entries. Commands use existing observed node atoms; discovery has capped name admission and no subnet scan.

The legacy `beam-deck-remsh` helper passes a selected cookie to IEx with `--cookie`. OS process-list readers with sufficient permission may see it. Do not interpret UI/export redaction as a guarantee that this legacy path, third-party logger messages or the OS environment hides credentials. Prefer the user's normal protected Erlang cookie mechanism for sensitive deployments, and keep helper logs private.

The launcher uses umask 077. Watchlist/export directories are chmod 0700 and files 0600. Writes use exclusive temporary files, sync and atomic replacement after regular-file checks. Symlink/oversize config/watchlist leaves are rejected; failure preserves prior in-memory watchlist state. This is not an adversarial same-UID race-proof filesystem sandbox or a guarantee of directory durability after power loss.

Exports use generated filenames in the plugin's private exports directory, never a caller-supplied output path. The archive entry set is fixed; selected frame IDs cannot become filenames. Failed/canceled worker writes attempt temporary cleanup. Helper SIGKILL/power loss can leave temporary files; inspect and remove only plugin-owned `.tmp-*` files after ensuring the helper is stopped.

## Remote operation bounds

A dedicated collection worker and capped diagnostic queue protect the input owner. Commands are capped at 16 KiB before JSON parsing; JSON nesting is capped at 32. Duplicate keys are rejected. Request IDs are capped and deduplicated; frontend jobs have count/age retention. Notifications execute a fixed argument vector, not a shell-generated string.

Target APIs such as native ETS enumeration, process binary-reference enumeration and observer process collection can materialize native lists before helper-side truncation. Configurable output/processing/deadline limits do not make those target allocations disappear. Canceling a client worker does not guarantee cancellation of a BIF already running remotely. Run focused diagnostics deliberately on very large/sensitive nodes; partial/unavailable output is not a clean bill of health.

No UI field selects an arbitrary module/function/eval expression or arbitrary filesystem read/write path. IEx remains a separately launched trusted operator shell; it is intentionally powerful. The terminal helper quotes node/path strings and accepts validated node names.

## Runtime changes and rollback

Scheduler changes and GC are explicit. A process report must be fresh and from the same VM incarnation for UI GC. The daemon rechecks the expected creation identity and attached target. PID lifetime can still change between observation and execution; process exit is handled as an error. There is no auto-GC or auto-apply incident playbook.

A scheduler trial validates the complete local proposal and journals before mutation. Defaults give at most 30 seconds unless Keep is explicitly accepted. Panel closure, lease expiry, partial failure and owner loss begin rollback. Applied values and first-original values are retained by a dedicated control owner, not a disposable worker. An RPC timeout is treated as uncertain, not assumed to mean no mutation.
OTP may automatically change `dirty_cpu_schedulers_online` when `schedulers_online` changes. BEAM Deck therefore journals both values before a normal-scheduler mutation and restores normal schedulers first, then dirty CPU schedulers, with the same VM-identity and external-change checks.


Rollback checks VM identity and whether the present value is the one BEAM Deck applied (or already the original). It refuses to clobber an externally changed value. Failures retain recovery state and become visible incidents. Kept/manual values remain restorable; normal shutdown attempts restoration. **SIGKILL, power loss, partitions and helper/target crashes cannot be guaranteed reversible without a resident target guard, which this product intentionally does not install.** Do not use the feature as a production transactional resource manager.

## Deep Events

Explicit activation loads `nshkr_beam_deck_probe` only after collision checks. It creates an isolated OTP 28+ trace session rather than stealing `system_monitor`, monitors the daemon owner, bounds metadata/rate/queue and destroys its session on stop/owner loss/overload. Normal stop acknowledgement precedes code delete/soft-purge. Another module/session is never deliberately replaced.

An abrupt helper failure may leave the unloaded process's module bytecode resident, though its monitored trace session should end. Future activation refuses a pre-existing module rather than blindly replacing it. Verify ownership and the absence of live probe processes before manual delete/soft-purge. Cross-OTP module compatibility and actual overload/parent-loss teardown need matrix testing before release.

## Crash triage

Only the existing `erl_crash.dump` in a disappeared local runtime's cached cwd is considered. No recursive search, arbitrary read path, dump generation in user applications or dump relocation occurs. A new/changed, time-matched regular file is required; descriptor identity is checked and the default/maximum read is 262144 bytes. A partial header, redirected dump, old file or disabled dump may yield no match. A timestamp/cwd match is correlation, not proven runtime causality when multiple VMs share a directory.

A slogan/current-function string is capped and sanitized, but can itself contain sensitive identifiers. Raw bytes are never persisted by triage or included in diagnostics export. The test suite's intentional crash runs only in a disposable test-owned peer/temp directory.

## Reporting

Do not post live cookies, unsanitized dumps, raw helper logs, private node names or production exports in a public issue. Reproduce with a disposable peer and distinctive fake secrets. A private security contact is not declared by this repository; use an available private maintainer channel rather than inventing one. Current validation gates and known deployment limitations are in [docs/VALIDATION.md](docs/VALIDATION.md).

## Operator report and control context

ZIP JSON now passes explicit nested projections before redaction; unrecognized incident/node/frame fields cannot be serialized as an extension escape hatch. Captured activity explains only allowlisted fields and does not retain raw before/after state. The operator baseline is a frame reference with capped metadata, not implicit persistence of a runtime snapshot. Deferred watch observations retain their age and a stale flag; they do not authorize a current PID action.

Both daemon execution and the independent scheduler owner reject stale view epochs and changed/unknown creation. Historical mode cancels interactive work and revokes unkept trial permission. Revert stays callable under saturation. A queued timeout remains an uncertain side-effect outcome; recovery never overwrites an external conflicting value or restores a different VM incarnation. Journals remain helper-memory state: untrappable helper/host loss cannot guarantee rollback.

Deep Events stop delivery is deliberately separate from confirmed teardown: a nonblocking stop request bypasses ordinary job admission, while exit/code unload still require confirmation. Standard agentless inspection does not install that probe. Enumeration APIs may allocate remotely before helper-side cardinality checks; admission caps and deadlines reduce exposure but cannot promise constant target allocation. Do not use production workloads for fault injection.

Focused ancestry may read only the OTP `$ancestors` and `$initial_call` metadata keys. The latter identifies supervisors before supervisor API requests; no full dictionary fallback is permitted.
