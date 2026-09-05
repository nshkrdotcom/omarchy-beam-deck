# Validation

BEAM Deck 1.0.0 uses separate source, BEAM/OTP, Omarchy, and live-behavior gates. A release is ready only when the checks applicable to the target workstation have executed successfully; an unavailable integration is not treated as a pass.

## Automated release checks

With the Mise-managed Erlang/Elixir toolchain available, run the complete local suite from the repository root:

```bash
mise exec -- make check
```

`make check` runs the static plugin/script contracts, fetches the daemon's development dependencies, verifies formatting, compiles the test build with warnings as errors, runs unit tests, runs the real-peer OTP integration suite, runs Credo in strict mode, and runs Dialyzer.

The static suite also verifies the manifest id/kinds and entry points, current plugin-id use in QML IPC/service lookup, panel lifecycle hooks, executable Bash syntax, profile-helper validation, per-node `cookie_env` handling, stale-shell-PATH recovery through `mise exec`, the no-BEAM onboarding protocol, and QML delimiter/string/comment balance.

GitHub Actions exercises the BEAM suite across OTP 27 / Elixir 1.18, OTP 28 / Elixir 1.19, and OTP 29 / Elixir 1.20, and separately runs strict formatting, compile, Credo, and Dialyzer gates.

## Omarchy validation

Run the official native manifest/path validation on the exact release checkout:

```bash
omarchy plugin validate .
omarchy restart shell
journalctl --user -t omarchy-shell --since "30 seconds ago" --no-pager
```

Any plugin-local manifest, QML, service, or panel error is a release failure.

## Live acceptance

Exercise the real plugin on the target Omarchy workstation:

- The bar widget loads in its configured section and opens/closes the panel reliably.
- Missing Erlang/Elixir presents the guided runtime-missing state without crashing the shell.
- Local `beam.smp` processes are discovered and correlated with attached distributed nodes.
- OS-only, attached, authentication failure, unreachable-node, and no-workload states are distinguishable and stable.
- EPMD, explicitly configured nodes, and learned peers behave as documented.
- Process, memory, scheduler, run-queue, mailbox, VM-limit, topology, history, event, and alert data update from real OTP nodes.
- Scheduler changes are bounded to the selected node, are reversible, and original scheduler/wall-time settings are restored when the panel closes or the service exits.
- Garbage collection is sent only to the explicitly selected process on the explicitly selected attached node.
- OTP 28+ Deep Events is opt-in, creates an isolated trace session, and tears down/unloads its transient probe when disabled, disconnected, or closed.
- Remote-node cookie configuration uses environment-variable references; cookie values do not appear in configuration, UI snapshots, logs, or committed files.
- Repeated shell restart, plugin update/reload, panel open/close, and node churn do not leave duplicate helpers, stale controls, or persistent mutations.

## Publication gate

Immediately before tagging and submitting the plugin, run:

```bash
git diff --check
git status --short
mise exec -- make check
omarchy plugin validate .
```

The working tree should be clean after the release commit. Confirm the root `manifest.json`, `README.md`, `CHANGELOG.md`, `LICENSE`, and `preview.png` are committed, and confirm the public GitHub repository resolves at the exact commit being submitted.

Marketplace compatibility and security-baseline results are authoritative for the submitted commit. BEAM Deck intentionally includes Mise-based toolchain onboarding, so any marketplace review capability reported for that behavior should be reviewed as reported rather than suppressed or relabeled.
