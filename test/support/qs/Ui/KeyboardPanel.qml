import QtQuick
// Host-window input adapter only. Native positioning is a separate acceptance gate.
Item {
  id: root
  objectName: "keyboardPanelAdapter"
  anchors.fill: parent
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: false
  property var focusTarget: null
  property bool centerOnBar: false
  property int padding: 8
  property int contentWidth: 0
  property int contentHeight: 0
  default property alias content: holder.data
  function fittedContentWidth(n) { return Math.min(parent.width,n) }
  function cappedContentHeight(n) { return Math.min(parent.height,n) }
  Item { id: holder; x: root.padding+2; y: root.padding+2; width: root.contentWidth-2*x; height: root.contentHeight-2*y }
}
