#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

jq -e '.schemaVersion == 1 and .id == "com.nshkr.beam-deck" and (.kinds | sort == ["bar-widget","service"])' manifest.json >/dev/null

for file in qml/Service.qml qml/BarWidget.qml qml/Panel.qml; do
  test -s "$file"
done

for script in bin/beam-deckd bin/beam-deck-onboard bin/beam-deck-remsh bin/beam-deck-profile test/scripts.sh test/static.sh; do
  bash -n "$script"
  test -x "$script"
done

for file in qml/Service.qml qml/BarWidget.qml; do
  grep -q 'property string omarchyPath' "$file"
  grep -q 'property var shell' "$file"
  grep -q 'property var manifest' "$file"
done

grep -q 'target: "com.nshkr.beam-deck"' qml/Service.qml
grep -q 'function open(payloadJson)' qml/BarWidget.qml
grep -q 'function open(payloadJson)' qml/Panel.qml
grep -q 'function close()' qml/Panel.qml
grep -q 'property var bar' qml/BarWidget.qml
grep -q 'serviceFor("com.nshkr.beam-deck")' qml/BarWidget.qml
grep -q 'source: Qt.resolvedUrl("Panel.qml")' qml/BarWidget.qml
grep -q 'panelLoader.item.anchorItem = button' qml/BarWidget.qml
grep -q 'panelLoader.item.hostWidget = root' qml/BarWidget.qml
grep -q 'panelLoader.item.service = root.beamService' qml/BarWidget.qml
grep -q '^Panel {' qml/Panel.qml
grep -q 'KeyboardPanel {' qml/Panel.qml
grep -q 'PanelKeyCatcher {' qml/Panel.qml
grep -q 'Keys.priority: Keys.AfterItem' qml/Panel.qml
grep -q 'contentWidth: panel.fittedContentWidth' qml/Panel.qml
grep -q 'contentHeight: panel.cappedContentHeight' qml/Panel.qml
for forbidden in 'PanelWindow {' 'WlrLayershell' 'Style.space(48)'; do
  if grep -q "$forbidden" qml/Panel.qml; then
    printf 'forbidden legacy panel pattern found: %s\n' "$forbidden" >&2
    exit 1
  fi
done

grep -q 'selectByMouse: true' qml/Panel.qml
grep -q 'selectByKeyboard: true' qml/Panel.qml
grep -q 'Quickshell.clipboardText = installCmd.text' qml/Panel.qml

# Force the no-toolchain path, including on runtime-enabled CI. Only harmless
# OS utilities are admitted to PATH; all writable state is temporary.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
for utility in bash dirname mkdir sleep; do
  ln -s "$(command -v "$utility")" "$tmp/bin/$utility"
done
first_line="$(PATH="$tmp/bin" HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" BEAM_DECK_MISSING_POLL_SECONDS=60 /usr/bin/timeout 1 "$ROOT/bin/beam-deckd" 2>/dev/null | head -n 1 || true)"
printf '%s\n' "$first_line" | jq -e '.type == "snapshot" and .protocol == 1 and .onboarding.state == "runtime_missing" and (.forecasts | type == "array") and (.incidents | type == "array") and (.flight_recorder | type == "object") and (.watchlist | type == "object") and (.crash_triage | type == "array")' >/dev/null

# Basic delimiter balance catches accidental truncation in generated QML.
node "$ROOT/test/qml-balance.mjs" qml/*.qml
node "$ROOT/test/qml-functions.mjs" qml/*.qml
node --test "$ROOT/test/ui-state.test.mjs"
node "$ROOT/test/source-contracts.mjs"
python3 -B -m unittest discover -s "$ROOT/test" -p 'test_native_tools.py'
"$ROOT/test/scripts.sh"

echo "static checks: ok"