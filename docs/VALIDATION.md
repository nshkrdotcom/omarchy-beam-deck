# Validation and acceptance - 1.1 implementation candidate

## Meaning of this record

Static checks and JavaScript behavior tests were run in a Debian 13 container with Node 22, Python 3, Bash and jq. Erlang/Elixir/Mix, Mise, Omarchy, Quickshell/Qt QML tools, Credo, Dialyzer and ShellCheck were unavailable. Package repository access failed; no runtime was installed. **No BEAM compilation, ExUnit/real OTP integration or UI rendering is claimed.** Exact final executed counts/results are recorded in [HANDOFF.md](../HANDOFF.md) and [the machine-readable check record](validation-results.json).

`make check` is intentionally fail-closed when Mix is missing. A static success must never be relabeled release acceptance. Source test declarations are not passed-test counts. Embedded JavaScript parsing does not validate QML imports, properties, layout, styling or runtime behavior.

## Reproducible gates

```bash
make static
mise exec -- make check
git diff --check
omarchy plugin validate .
```

`make static` runs manifest/service contracts, Bash syntax, a forced no-toolchain onboarding envelope in temporary HOME/XDG/PATH, QML delimiter balance, embedded QML JavaScript body parsing, the production `DeckState.js` test suite, configuration/default/version/command/privacy/documentation structural checks and existing shell-helper tests.

The complete release gate fetches dev dependencies, checks formatting, compiles tests with warnings as errors, runs default ExUnit, then all real-peer tests with `BEAM_DECK_INTEGRATION=1`, Credo strict, Dialyzer and the actual-launcher protocol harness. Formatting and static analysis have not been executed in this container; expect to fix issues, not to waive them. Preserve the real generated `mix.lock` after successful resolution; none was invented offline.

Target matrix: OTP 27 / Elixir 1.18; OTP 28 / Elixir 1.19; OTP 29 / Elixir 1.20. Deep Events is unavailable below OTP 28. Every line must exercise optional API loss gracefully, not skip all relevant integration coverage because one feature is absent. CI is configured for the matrix; no CI run result is included in this delivery.

## Real test environments, not production substitutes

`daemon/test/support/real_peer.ex` starts controlled disposable actual OTP peers. Two small test-owned Erlang modules produce a registered supervised worker, private dictionary/binary/table canaries and optional wall-time ownership. They are test fixtures only, never a production backend or a dependency to add to monitored apps. All runtime integrations remain direct OTP calls.

The original shell test records IEx argv with a tiny executable stub to verify quoting/forwarding; that is a shell-unit boundary, not remote-integration evidence. Pure projection/config/history/incident/forecast tests use deterministic data because those algorithms have no external side effect.

`python3 test/live-protocol.py` is a standard-library-only end-to-end harness. It creates a private EPMD port/HOME/XDG tree, starts a real Erlang peer and the actual launcher, checks JSON-only protocol and fake-cookie absence, open-panel process/ETS jobs, pin persistence/current resolution, frame/diff, exact/private ZIP contents, malformed-command recovery and normal stdin EOF. It does not mutate a user's node and fails rather than silently skipping absent runtimes. It has only been Python-syntax checked here.

## Mandatory real-desktop acceptance

**Onboarding and lifecycle:** check missing toolchain, no workload, OS-only workload, attached node, wrong cookie and unreachable required node. Repeatedly open/close/restart the shell; confirm exactly one helper, no protocol noise, no stuck job/probe/trial and clear capture ages. Confirm the shell, not an unrelated terminal, inherits the intended configuration/cookie environment.

**Forecast and evidence:** use disposable workloads plus deterministic tests for stable growth, noisy/flat/reversed samples, changed limits and VM restart. Confirm no premature ETA, no ETS hard-limit countdown, correct units/sample count/span, fit-quality wording, observed/correlated/heuristic labels and no deadlock/causality claim. Verify mailbox/churn/run-queue evidence links to an actual retained frame when nearby evidence exists.

**Historical investigation:** create a resource change, select and compare frames, copy the report, return Live and expire a selection. Confirm mutations are disabled in historical mode, old results cannot overwrite a new target and helper restart clears old jobs/frame context. Check frame range selection after clock changes through the regression tests, not only ordinary monotonic wall time.

**Process and ETS:** inspect real worker/supervisor ancestry under OTP 27 fallback and OTP 28 optimized API. Confirm private dictionary canary, message/state contents, binary IDs and table values never appear. Trigger process exit during inspection and registered-name restart; pins must follow the new PID. Verify partial/capped binary/ETS reports, target word conversion, owner navigation, explicit refresh and creation/freshness-gated GC confirmation.

**Scheduler controls:** on disposable local nodes verify whole-proposal matching, actual flag values, partial second-node failure, panel-close rollback, lease expiry, Keep, first-original Restore, normal helper shutdown, owner death and conflicting external change. The last must remain rollback_failed, not clobber the external value or lose recovery. Test retries and a restarted node; no cross-incarnation restore. Kill/partition tests must describe observed recovery limits, not assume guaranteed rollback.

**Deep Events:** validate isolated system events without replacing another system monitor, rate/queue overload, parent death, repeated enable/disable and normal code unload. Verify there is no wall-time measurement reference left behind. Test bytecode compatibility with the actual helper/target OTP pair. A resident inert module after abrupt loss needs ownership-aware cleanup, not blind overwrite.

**Crash triage/export/notification:** use only the disposable fixture crash, not a production dump. Confirm fresh prefix matching, unchanged/stale/unmatched/symlink refusal, delayed retry, last-frame context and no raw dump persistence/export. Inspect seven ZIP entries and permissions; search for fake cookies and private canaries. Trigger a real critical notification, repeat polls and resolve/retrigger inside cooldown; verify one transition notification and nonfatal missing-helper behavior.

**Visual and accessibility:** test the actual theme imports and native controls at 1366x768, 1920x1080, a smaller usable panel and 125%/150% scale. Exercise long node/module names, empty states, error states, 100 incidents, capped ETS rows and 150 timeline metadata points. Check scroll reachability, no overlap/clipping, readable contrast, keyboard focus/selection, copy actions, toolbar wrapping, historical badge, sticky trial countdown and fixed-width horizontal/vertical bar slot. Capture screenshots and correct the QML; do not infer a rendered result from syntax checks.

## Performance and privacy gates

Compare closed/open helper CPU/RSS, target overhead and snapshot size against the baseline under the same disposable workloads. Closed panel must not cause full process/ETS/stack/binary scans; only light collection and bounded pinned observations continue. Measure pathological node count, long names, unreachable peers, process/table population and job-queue saturation. Native enumeration costs are documented limits, not assumed fixed by a displayed top-N cap.

Record typical and capped snapshot/export size, deadline responsiveness and recovery latency. Verify collections do not accumulate, requests stay bounded and Keep/Revert remain serviceable while ordinary jobs are saturated. No numeric performance pass is claimed in this container.

## Full-environment evidence to retain

Record exact OTP/Elixir/Quickshell/Omarchy versions, each command and exit status, ExUnit counts including exclusions, matrix results, real harness output, strict-analysis logs, rendered screenshots with dimensions/theme, before/after target scheduler values and privacy-canary search results. Update this file and HANDOFF with observed evidence and remaining issues; do not convert unrun checks into passes by editing a checkbox.
