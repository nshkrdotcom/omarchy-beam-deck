import QtQuick
import qs.Ui
import "DeckState.js" as DeckState

Button {
  id: root
  focusable: true
  opacity: enabled ? 1 : 0.4
  Accessible.role: Accessible.Button
  Accessible.name: text
  onActiveFocusChanged: if (activeFocus) Qt.callLater(function() { DeckState.revealFocus(root) })
  onYChanged: if (activeFocus) Qt.callLater(function() { DeckState.revealFocus(root) })
}
