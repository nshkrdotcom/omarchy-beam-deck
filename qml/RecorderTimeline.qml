import QtQuick
import qs.Commons
import qs.Ui
import "DeckState.js" as DeckState

FocusScope {
  id: root

  property var timeline: []
  property string fromFrame: ""
  property string toFrame: ""
  property bool live: true
  property color fg: Color.popups.text
  property color dim: Util.alpha(fg, 0.58)
  property color accent: Color.accent
  property color urgent: Color.urgent

  signal rangeRequested(string fromFrame, string toFrame)

  readonly property real plotLeft: Style.space(12)
  readonly property real plotRight: width - Style.space(12)
  readonly property real plotTop: Style.space(28)
  readonly property real plotBottom: height - Style.space(30)
  readonly property real plotWidth: Math.max(1, plotRight - plotLeft)
  readonly property real plotHeight: Math.max(1, plotBottom - plotTop)
  readonly property bool hasSelection: !live && !!fromFrame && !!toFrame
  readonly property real fromX: xForFrame(fromFrame)
  readonly property real toX: xForFrame(toFrame)
  readonly property real selectionLeft: Math.min(fromX, toX)
  readonly property real selectionRight: Math.max(fromX, toX)

  property string dragMode: ""
  property string dragAnchor: ""
  property int hoverIndex: -1

  implicitHeight: Style.space(188)
  activeFocusOnTab: timeline.length > 0
  Accessible.role: Accessible.Slider
  Accessible.name: live
    ? "Live flight recorder timeline. Drag to pause and select a historical range."
    : "Paused flight recorder timeline. Drag either range handle or drag a new range."
  Accessible.description: "When paused, Left and Right move endpoint B. Shift plus Left or Right moves endpoint A."

  function indexForFrame(id) {
    return DeckState.recorderIndexById(timeline, id)
  }

  function xForIndex(index) {
    if (!timeline.length || index < 0) return plotLeft
    if (timeline.length === 1) return plotLeft + plotWidth / 2
    return plotLeft + (index / (timeline.length - 1)) * plotWidth
  }

  function xForFrame(id) {
    return xForIndex(indexForFrame(id))
  }

  function frameAtX(x) {
    var fraction = Math.max(0, Math.min(1, (x - plotLeft) / plotWidth))
    return DeckState.recorderFrameAtFraction(timeline, fraction)
  }

  function requestOrdered(a, b) {
    var ordered = DeckState.recorderOrderedRange(timeline, a, b)
    if (ordered.from && ordered.to) rangeRequested(ordered.from, ordered.to)
  }

  function moveEndpoint(which, delta) {
    if (!hasSelection || !delta) return
    var fromIndex = indexForFrame(fromFrame)
    var toIndex = indexForFrame(toFrame)
    if (fromIndex < 0 || toIndex < 0) return

    if (which === "from") {
      fromIndex = Math.max(0, Math.min(toIndex, fromIndex + delta))
    } else {
      toIndex = Math.min(timeline.length - 1, Math.max(fromIndex, toIndex + delta))
    }

    requestOrdered(timeline[fromIndex].frame_id, timeline[toIndex].frame_id)
  }

  onTimelineChanged: plot.requestPaint()
  onFromFrameChanged: plot.requestPaint()
  onToFrameChanged: plot.requestPaint()
  onLiveChanged: plot.requestPaint()
  onAccentChanged: plot.requestPaint()
  onUrgentChanged: plot.requestPaint()
  onWidthChanged: plot.requestPaint()
  onHeightChanged: plot.requestPaint()

  Keys.onPressed: function(event) {
    if (!root.hasSelection) return
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
      var delta = event.key === Qt.Key_Right ? 1 : -1
      root.moveEndpoint((event.modifiers & Qt.ShiftModifier) ? "from" : "to", delta)
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(root.fg, 0.035)
    border.width: root.activeFocus ? 2 : 1
    border.color: root.activeFocus ? root.accent : Util.alpha(root.fg, 0.14)
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.top: parent.top
    anchors.topMargin: Style.space(8)
    text: "BEAM RSS"
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.top: parent.top
    anchors.topMargin: Style.space(8)
    spacing: Style.space(10)

    Row {
      spacing: Style.space(4)
      Rectangle { width: Style.space(7); height: width; radius: width / 2; color: root.urgent }
      Text { text: "alert"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
    }
    Row {
      spacing: Style.space(4)
      Rectangle { width: Style.space(7); height: width; radius: width / 2; color: root.accent }
      Text { text: "event"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
    }
  }

  Canvas {
    id: plot
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)

      var rows = root.timeline || []
      if (!rows.length) return

      ctx.lineWidth = 1
      ctx.strokeStyle = Util.alpha(root.fg, 0.09)
      for (var grid = 0; grid < 3; grid++) {
        var gy = root.plotTop + (grid / 2) * root.plotHeight
        ctx.beginPath()
        ctx.moveTo(root.plotLeft, gy)
        ctx.lineTo(root.plotRight, gy)
        ctx.stroke()
      }

      var minRss = Number(rows[0].beam_rss_bytes || 0)
      var maxRss = minRss
      for (var i = 1; i < rows.length; i++) {
        var rss = Number(rows[i].beam_rss_bytes || 0)
        minRss = Math.min(minRss, rss)
        maxRss = Math.max(maxRss, rss)
      }
      var span = Math.max(1, maxRss - minRss)

      ctx.beginPath()
      for (var p = 0; p < rows.length; p++) {
        var x = root.xForIndex(p)
        var value = Number(rows[p].beam_rss_bytes || 0)
        var normalized = (value - minRss) / span
        var y = root.plotBottom - normalized * root.plotHeight
        if (p === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.strokeStyle = root.accent
      ctx.lineWidth = 2
      ctx.stroke()

      for (var m = 0; m < rows.length; m++) {
        var marker = rows[m]
        var mx = root.xForIndex(m)
        var critical = Number(marker.critical_count || 0)
        var warning = Number(marker.warning_count || 0)
        var events = Number(marker.event_count || 0)

        if (critical > 0 || warning > 0) {
          ctx.beginPath()
          ctx.arc(mx, root.plotTop + Style.space(7), critical > 0 ? 4 : 3, 0, Math.PI * 2)
          ctx.fillStyle = root.urgent
          ctx.fill()
        }

        if (events > 0) {
          ctx.beginPath()
          ctx.arc(mx, root.plotBottom - Style.space(7), 3, 0, Math.PI * 2)
          ctx.fillStyle = root.accent
          ctx.fill()
        }
      }
    }
  }

  Rectangle {
    visible: root.hasSelection
    x: root.selectionLeft
    y: root.plotTop
    width: Math.max(2, root.selectionRight - root.selectionLeft)
    height: root.plotHeight
    color: Util.alpha(root.accent, 0.10)
    border.width: Style.spacing.hairline
    border.color: Util.alpha(root.accent, 0.55)
  }

  Rectangle {
    visible: root.hasSelection
    x: root.fromX - width / 2
    y: root.plotTop - Style.space(3)
    width: Style.space(6)
    height: root.plotHeight + Style.space(6)
    radius: width / 2
    color: root.accent
  }

  Rectangle {
    visible: root.hasSelection
    x: root.toX - width / 2
    y: root.plotTop - Style.space(3)
    width: Style.space(6)
    height: root.plotHeight + Style.space(6)
    radius: width / 2
    color: root.accent
  }

  Rectangle {
    visible: interaction.containsMouse && root.hoverIndex >= 0 && root.hoverIndex < root.timeline.length
    x: Math.max(Style.space(6), Math.min(parent.width - width - Style.space(6), root.xForIndex(root.hoverIndex) - width / 2))
    y: root.plotTop + Style.space(6)
    width: Style.space(230)
    height: hoverText.implicitHeight + Style.space(12)
    radius: (Style.cornerRadius / 2)
    color: Color.popups.background
    border.width: Style.spacing.hairline
    border.color: Util.alpha(root.fg, 0.18)
    z: 20

    Text {
      id: hoverText
      anchors.fill: parent
      anchors.margins: Style.space(6)
      text: {
        if (root.hoverIndex < 0 || root.hoverIndex >= root.timeline.length) return ""
        var frame = root.timeline[root.hoverIndex]
        return DeckState.time(frame.at_ms)
          + "  ·  " + DeckState.bytes(frame.beam_rss_bytes)
          + "\n" + Number(frame.alert_count || 0) + " alerts  ·  " + Number(frame.event_count || 0) + " events"
      }
      color: root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }
  }

  MouseArea {
    id: interaction
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: root.plotTop
    anchors.bottomMargin: parent.height - root.plotBottom
    hoverEnabled: true
    cursorShape: Qt.CrossCursor

    onPositionChanged: function(mouse) {
      if (root.timeline.length) {
        var fraction = Math.max(0, Math.min(1, (mouse.x - root.plotLeft) / root.plotWidth))
        root.hoverIndex = Math.round(fraction * (root.timeline.length - 1))
      }

      if (!pressed || !root.dragMode) return
      var frame = root.frameAtX(mouse.x)
      if (!frame) return

      if (root.dragMode === "from") root.requestOrdered(frame, root.toFrame)
      else if (root.dragMode === "to") root.requestOrdered(root.fromFrame, frame)
      else root.requestOrdered(root.dragAnchor, frame)
    }

    onExited: if (!pressed) root.hoverIndex = -1

    onPressed: function(mouse) {
      if (!root.timeline.length) return
      root.forceActiveFocus()

      var frame = root.frameAtX(mouse.x)
      if (!frame) return

      var handleRadius = Style.space(16)
      if (root.hasSelection && Math.abs(mouse.x - root.fromX) <= handleRadius) {
        root.dragMode = "from"
        root.requestOrdered(frame, root.toFrame)
      } else if (root.hasSelection && Math.abs(mouse.x - root.toX) <= handleRadius) {
        root.dragMode = "to"
        root.requestOrdered(root.fromFrame, frame)
      } else {
        root.dragMode = "new"
        root.dragAnchor = frame
        root.requestOrdered(frame, frame)
      }
    }

    onReleased: {
      root.dragMode = ""
      root.dragAnchor = ""
    }

    onCanceled: {
      root.dragMode = ""
      root.dragAnchor = ""
    }
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(7)
    text: root.timeline.length ? DeckState.time(root.timeline[0].at_ms) : "No retained history yet"
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(7)
    text: root.timeline.length ? (root.live ? "NOW  ·  " : "PAUSED  ·  ") + DeckState.time(root.timeline[root.timeline.length - 1].at_ms) : ""
    color: root.live ? root.accent : root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: root.live
  }
}