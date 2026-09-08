import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "com.nshkr.beam-deck"
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var bar: null

  readonly property var beamService:
    bar?.shell?.serviceFor("com.nshkr.beam-deck")

  readonly property var snapshotData:
    beamService ? beamService.snapshot : ({})

  readonly property var summary:
    snapshotData.summary || ({})

  readonly property int runtimes:
    Number(summary.runtime_count || 0)

  readonly property int warnings:
    Number(summary.warning_count || 0)
    + Number(summary.critical_count || 0)

  readonly property bool critical:
    Number(summary.critical_count || 0) > 0 || Number(summary.critical_incident_count || 0) > 0

  readonly property string incidentTitle: (snapshotData.incidents || []).filter(function(i) { return i.status === "active" }).length ? String(snapshotData.incidents.filter(function(i) { return i.status === "active" })[0].title).slice(0, 100) : ""
  readonly property int watchProblems: Number(summary.watched_problem_count || 0)

  readonly property bool runtimeMissing:
    snapshotData.onboarding
    && snapshotData.onboarding.state === "runtime_missing"

  readonly property bool opened:
    panelLoader.item ? panelLoader.item.opened === true : false

  readonly property bool popoutSwitchClosing:
    panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open(payloadJson) {
    if (panelLoader.item) panelLoader.item.open(payloadJson || "{}")
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.service = root.beamService
    panelLoader.item.settings = root.settings
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onBeamServiceChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    text: String.fromCharCode(0xe7cd)
    labelVisible: false
    horizontalMargin: 0

    fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
    fixedHeight: root.vertical ? Style.bar.statusSlot : -1

    active: root.critical

    tooltipText: root.runtimeMissing ? "BEAM Deck - setup Elixir/OTP"
      : "BEAM Deck - " + root.runtimes + " local runtimes / " + Number(root.summary.attached_count || 0) + " attached"
        + (root.incidentTitle ? "\n" + root.incidentTitle : "")
        + (root.watchProblems ? "\n" + root.watchProblems + " watched identities need attention" : "")

    OpticalGlyph {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: 0

      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas

      text: button.text
      fontFamily: button.fontFamily
      fontSize: Style.bar.iconFont
      color:
        button.active && button.useActiveColor
          ? button.activeColor
          : button.foreground
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }
}