# Security

BEAM Deck talks to Erlang distribution. That is a trusted-control-plane protocol, not a read-only metrics protocol.

## Distribution cookies

Anyone who obtains a node's Erlang distribution cookie and can reach its distribution port may gain powerful remote code execution capabilities on that node. Do not expose development distribution ports to untrusted networks.

BEAM Deck uses the current user's normal cookie by default. For explicitly configured nodes, `cookie_env` names an environment variable; the cookie value itself is not written into BEAM Deck configuration, Omarchy `shell.json`, logs, or the repository by BEAM Deck.

The local `/proc` census can see BEAM command lines. Before a command line enters a snapshot, BEAM Deck redacts secrets supplied through separated or inline `-setcookie` / `--cookie` arguments. The helper launcher also sets `umask 077`, so its XDG cache/state files are private to the user by default.

## Deep Events probe

Deep Events explicitly loads namespaced `nshkr_beam_deck_probe` bytecode into the selected target node. It is not enabled automatically. The probe:

- contains no file or network I/O;
- creates an isolated OTP trace session;
- forwards selected system-monitor events to the BEAM Deck helper PID;
- monitors that parent PID and destroys the trace session if the parent disappears;
- is synchronously stopped, then deleted/soft-purged when disabled or when the BEAM Deck panel closes normally.

Review `daemon/src/nshkr_beam_deck_probe.erl` before enabling it on a sensitive node.

## Runtime mutations

The panel can change `schedulers_online` and `dirty_cpu_schedulers_online`. These changes affect application scheduling immediately. BEAM Deck stores the first previous value and offers Restore. Normal helper shutdown also attempts restoration, but no userspace process can guarantee cleanup after SIGKILL, power loss, or its own VM crash. A target VM restart returns to its startup settings.

## Reporting a security issue

Until a private security contact is published for the repository, do not include live cookies, private node names, internal addresses, or production crash dumps in a public issue. Reproduce with sanitized data first.
