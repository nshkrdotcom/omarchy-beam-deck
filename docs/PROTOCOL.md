# Local JSONL protocol

The QML service and `beam-deckd` communicate with one JSON object per line on a dedicated inherited file descriptor.

Protocol version: `1`.

## Snapshot

Representative shape:

```json
{
  "type": "snapshot",
  "protocol": 1,
  "at_ms": 0,
  "onboarding": { "state": "ready" },
  "host": { "logical_cpus": 24, "runtimes": [], "memory": {} },
  "summary": {},
  "nodes": [],
  "topology": [],
  "alerts": [],
  "budget": [],
  "history": [],
  "events": [],
  "config_path": "...",
  "config_error": null
}
```

Onboarding states:

- `runtime_missing`: shell launcher is alive but the Erlang/Elixir/Mix toolchain is unavailable;
- `no_runtimes`: helper is running but no user BEAM OS processes exist;
- `os_only`: local BEAM VMs exist but no candidate is deeply attached;
- `ready`: at least one distributed node is attached.

Local runtime rows may include `node_name` and `os_only: false` when a deep local node's remotely reported OS PID exactly matches that `/proc` PID. Command strings are cookie-redacted before serialization.

Attached node rows include VM counters/limits, scheduler data, topology peers, hot-process samples, registered-process fingerprints/churn, configuration metadata (`configured`, `required`, `expected_peers`), and Deep Event capability/state.

Topology entries have this form:

```json
{
  "node": "api@workstation",
  "sees": ["worker@omen"],
  "expected": ["worker@omen"],
  "missing": [],
  "attached": true,
  "local": true
}
```

`expected` is configuration-backed and directional. The daemon never invents expected cluster membership.

## Commands

QML -> daemon:

```json
{"cmd":"refresh"}
{"cmd":"panel","open":true}
{"cmd":"panel","open":false}
{"cmd":"set_schedulers","node":"app@host","value":8}
{"cmd":"set_dirty_schedulers","node":"app@host","value":4}
{"cmd":"restore","node":"app@host"}
{"cmd":"deep_events","node":"app@host","enabled":true}
{"cmd":"deep_events","node":"app@host","enabled":false}
{"cmd":"gc","node":"app@host","pid":"<0.123.0>"}
```

## Action result

```json
{"type":"action","action":"set_schedulers_online","node":"app@host","result":"{:ok, 24}"}
```

Action results are human-facing acknowledgements; the next snapshot is authoritative.

## Runtime / Deep Event

Deep-event example:

```json
{
  "type": "event",
  "event": {
    "node": "app@host",
    "kind": "long_schedule",
    "subject": "<0.123.0>",
    "info": {},
    "at_ms": 0
  }
}
```

Node lifecycle events share the same event envelope. For example, a `nodedown` event has `kind: "nodedown"`, the node as subject, and preserves the info object returned by OTP, including `nodedown_reason` when supplied.

The daemon retains the newest 200 internal events and exposes the newest 30 in snapshots.

## Error

```json
{"type":"error","error":"protocol","reason":"..."}
```

The shell launcher may also emit a synthetic snapshot with onboarding state `runtime_missing`, or an error-like startup state such as `daemon_compile_failed`, before an Elixir application can start.
