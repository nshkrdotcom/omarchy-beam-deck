#!/usr/bin/env bash
# Real production components with isolated host window/style/clipboard inputs.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
runner="${QML_TEST_RUNNER:-/usr/lib/qt6/bin/qmltestrunner}"
host="${OMARCHY_SHELL_SOURCE:-/usr/share/omarchy/shell}"
imports="$(mktemp -d /tmp/beam-deck-qt-imports.XXXXXX)"
trap 'rm -rf "$imports"' EXIT
cp -R "$root/test/support/." "$imports/"
for file in Button BorderSurface BorderOverlay OpticalGlyph PanelKeyCatcher PanelSectionHeader PanelSeparator; do
  ln -s "$host/Ui/$file.qml" "$imports/qs/Ui/$file.qml"
  printf '%s 1.0 %s.qml\n' "$file" "$file" >> "$imports/qs/Ui/qmldir"
done
for file in Border.qml BorderGeometry.js; do ln -s "$host/Commons/$file" "$imports/qs/Commons/$file"; done
printf 'singleton Border 1.0 Border.qml\n' >> "$imports/qs/Commons/qmldir"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software "$runner" -import "$imports" -input "$root/test/qt" "$@"
