#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

jq -e '.schemaVersion == 1 and .id == "nshkr.beam-deck" and (.kinds | sort == ["bar-widget","panel","service"])' manifest.json >/dev/null

for file in qml/Service.qml qml/BarWidget.qml qml/Panel.qml; do
  test -s "$file"
done

for script in bin/beam-deckd bin/beam-deck-onboard bin/beam-deck-remsh bin/beam-deck-profile test/scripts.sh; do
  bash -n "$script"
  test -x "$script"
done

for file in qml/Service.qml qml/BarWidget.qml qml/Panel.qml; do
  grep -q 'property string omarchyPath' "$file"
  grep -q 'property var shell' "$file"
  grep -q 'property var manifest' "$file"
done

grep -q 'target: "nshkr.beam-deck"' qml/Service.qml
grep -q 'function open(payloadJson)' qml/Panel.qml
grep -q 'function close()' qml/Panel.qml
grep -q 'property var bar' qml/BarWidget.qml
grep -q 'serviceFor("nshkr.beam-deck")' qml/BarWidget.qml
grep -q 'serviceFor("nshkr.beam-deck")' qml/Panel.qml

grep -q 'selectByMouse: true' qml/Panel.qml
grep -q 'selectByKeyboard: true' qml/Panel.qml
grep -q 'Quickshell.clipboardText' qml/Panel.qml

# Validate the runtime-missing protocol without Erlang/Elixir installed in this
# build environment. timeout is expected to stop the daemon's retry loop.
if ! command -v erl >/dev/null 2>&1 || ! command -v elixir >/dev/null 2>&1 || ! command -v mix >/dev/null 2>&1; then
  first_line="$(BEAM_DECK_MISSING_POLL_SECONDS=60 timeout 1 "$ROOT/bin/beam-deckd" 2>/dev/null | head -n 1 || true)"
  printf '%s\n' "$first_line" | jq -e '.type == "snapshot" and .onboarding.state == "runtime_missing"' >/dev/null
fi

# Basic delimiter balance catches accidental truncation in generated QML.
node "$ROOT/test/qml-balance.mjs" qml/Service.qml qml/BarWidget.qml qml/Panel.qml
"$ROOT/test/scripts.sh"

echo "static checks: ok"
