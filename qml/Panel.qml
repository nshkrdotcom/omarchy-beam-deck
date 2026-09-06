import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "DeckState.js" as DeckState

Panel {
  id: root
  moduleName: "nshkr.beam-deck"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property string workspace: "cockpit"
  property double nowMs: Date.now()
  readonly property bool stale: !service || !service.daemonRunning || !snapshotData.at_ms || nowMs - snapshotData.at_ms > 10000
  Timer { interval: 1000; repeat: true; running: root.opened; onTriggered: root.nowMs = Date.now() }
  property string selectedNode: ""
  readonly property var snapshotData: service ? service.snapshot : ({})
  readonly property var summary: snapshotData.summary || ({})
  readonly property var host: snapshotData.host || ({})
  readonly property var nodes: snapshotData.nodes || []
  readonly property var alerts: snapshotData.alerts || []
  readonly property var budget: snapshotData.budget || []
  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(fg, 0.62)
  readonly property color bg: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property string missingTitle: snapshotData.onboarding && snapshotData.onboarding.erl_available ? "Elixir helper toolchain incomplete" : "BEAM runtime not installed"
  readonly property string missingMessage: snapshotData.onboarding && snapshotData.onboarding.erl_available
    ? "Erlang/OTP is available, but BEAM Deck's Elixir/Mix helper is not. Use the Mise setup action to select a complete Erlang + Elixir toolchain; nothing is installed silently."
    : "BEAM Deck is ready, but Erlang/OTP and Elixir are not on PATH. Omarchy development tooling favors Mise, so setup is one deliberate terminal action — nothing is installed silently."

  function open(payloadJson) {
    root.controller.show()
    if (!selectedNode && nodes.length > 0) selectedNode = String(nodes[0].name || "")
  }
  function close() {
    root.controller.hide()
  }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  onOpenedChanged: {
    if (service) service.setPanelOpen(root.opened)
    if (root.opened && !selectedNode && nodes.length > 0)
      selectedNode = String(nodes[0].name || "")
    if (!root.opened) workspace = "cockpit"
  }

  onServiceChanged: {
    if (service && root.opened) service.setPanelOpen(true)
  }

  Component.onDestruction: {
    if (service && root.opened) service.setPanelOpen(false)
  }
  function openInvestigation(tab, node, pid) {
    workspace = "investigate"
    Qt.callLater(function() { if (contentLoader.item && contentLoader.item.activate) contentLoader.item.activate(tab || "triage", node || "", pid || "") })
  }
  function liveCockpit() {
    if (service) service.returnLive()
    workspace = "cockpit"
  }
  function selected() {
    for (var i = 0; i < nodes.length; i++) if (String(nodes[i].name) === selectedNode) return nodes[i]
    return nodes.length > 0 ? nodes[0] : null
  }
  function bytes(n) {
    if (n === null || n === undefined) return "\u2014"
    n = Number(n)
    if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GiB"
    if (n >= 1048576) return (n / 1048576).toFixed(0) + " MiB"
    if (n >= 1024) return (n / 1024).toFixed(0) + " KiB"
    return n + " B"
  }
  function percent(a, b) { return b > 0 ? ((Number(a || 0) / Number(b)) * 100).toFixed(1) + "%" : "—" }
  function schedulerAverage(n) {
    var rows = n && n.scheduler_utilization ? n.scheduler_utilization : []
    if (!rows.length) return "warming / unavailable"
    var total = 0
    for (var i = 0; i < rows.length; i++) total += Number(rows[i].utilization || 0)
    return ((total / rows.length) * 100).toFixed(0) + "% avg"
  }
  function nodeRunQueueHistory(name) {
    var out = []
    var rows = snapshotData.history || []
    for (var i = 0; i < rows.length; i++) {
      var ns = rows[i].nodes || []
      for (var j = 0; j < ns.length; j++) {
        if (String(ns[j].name || "") === String(name || "")) {
          out.push(Number(ns[j].run_queue || 0))
          break
        }
      }
    }
    return out
  }
  function hostSchedulerHistory() {
    var out = []
    var rows = snapshotData.history || []
    for (var i = 0; i < rows.length; i++) out.push(Number(rows[i].schedulers_online || 0))
    return out
  }
  function eventText(event) {
    if (!event) return "event"
    var text = String(event.kind || "event") + "  ·  " + String(event.node || "")
    if (event.info && event.info.nodedown_reason) text += "  ·  " + String(event.info.nodedown_reason)
    if (event.subject && event.subject !== event.node) text += "\n" + String(event.subject)
    return text
  }
  function localRuntimeForNode(n) {
    if (!n) return null
    var list = host.runtimes || []
    if (Number(n.os_pid || 0) > 0) {
      for (var p = 0; p < list.length; p++) if (Number(list[p].pid || 0) === Number(n.os_pid)) return list[p]
    }
    return null
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    centerOnBar: true

    // Keep the cockpit deliberately large while delegating every real screen,
    // bar-edge, gap, monitor, scale and clamping decision to Omarchy.
    contentWidth: panel.fittedContentWidth(Style.space(1280))
    contentHeight: panel.cappedContentHeight(Style.space(840))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // BEAM Deck contains TextEdit/TextField/ComboBox/SpinBox controls. Make
      // the shell key catcher a fallback so focused editors get first refusal.
      Keys.priority: Keys.AfterItem
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(12)

        RowLayout {
          Layout.fillWidth: true
          Text { textFormat: Text.PlainText; text: "BEAM DECK"; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
          Text { textFormat: Text.PlainText; text: root.stale ? "Waiting for fresh telemetry" : "LIVE  /  " + DeckState.time(root.snapshotData.at_ms); color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
          Button { text: "Cockpit"; selected: root.workspace === "cockpit"; onClicked: root.liveCockpit() }
          Button { text: "Investigate"; selected: root.workspace === "investigate"; onClicked: root.openInvestigation("triage") }
          Button { text: "Refresh"; onClicked: if (root.service) root.service.refresh() }
          Button { text: "Close"; onClicked: root.close() }
        }
        Text { textFormat: Text.PlainText; visible: !!root.snapshotData.config_error || (root.service && root.service.lastError !== ""); Layout.fillWidth: true; text: root.snapshotData.config_error ? ("Config: " + root.snapshotData.config_error) : (root.service ? root.service.lastError : ""); color: root.urgent; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

        Text { textFormat: Text.PlainText; visible: root.service && root.service.lastAction !== ""; Layout.fillWidth: true; text: root.service ? root.service.lastAction : ""; color: root.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap }
        Text { textFormat: Text.PlainText; visible: root.service && root.service.notificationError !== ""; Layout.fillWidth: true; text: root.service ? root.service.notificationError : ""; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap }
        TrialBar { Layout.fillWidth: true; service: root.service }
        Loader {
          id: contentLoader
          Layout.fillWidth: true
          Layout.fillHeight: true
          sourceComponent: root.snapshotData.onboarding && root.snapshotData.onboarding.state === "runtime_missing" ? missingView
            : root.workspace === "investigate" ? investigationView
            : Number(root.summary.runtime_count || 0) === 0 && root.nodes.length === 0 && !(root.snapshotData.incidents || []).length && !((root.snapshotData.watchlist || {}).entries || []).length ? emptyView : dashboardView
        }
      }
    }
  }

  Component { id: investigationView; Investigation { service: root.service; targetNode: root.selectedNode } }

  Component {
    id: missingView
    ColumnLayout {
      spacing: Style.space(16)
      Item { Layout.fillHeight: true }
      Text { textFormat: Text.PlainText; Layout.alignment: Qt.AlignHCenter; text: root.missingTitle; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText; Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: Style.space(560); text: root.missingMessage; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
      BorderSurface {
        Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: Style.space(500); implicitHeight: Math.max(installCmd.implicitHeight, copyInstallCmd.implicitHeight) + Style.space(24)
        color: Util.alpha(root.fg, 0.05); borderSpec: Border.flat(Util.alpha(root.fg, 0.16), 1); radius: Style.cornerRadius
        TextEdit {
          id: installCmd
          anchors.left: parent.left
          anchors.right: copyInstallCmd.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter

          text: "mise use -g erlang@latest elixir@latest"
          readOnly: true
          selectByMouse: true
          selectByKeyboard: true
          persistentSelection: true
          activeFocusOnTab: true
          wrapMode: TextEdit.NoWrap

          color: root.fg
          selectionColor: root.accent
          selectedTextColor: root.bg
          font.family: Style.font.family
          font.pixelSize: Style.font.body

          Keys.onPressed: function(event) {
            var commandModifier =
              event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)

            if (commandModifier && event.key === Qt.Key_A) {
              installCmd.selectAll()
              event.accepted = true
            } else if (commandModifier && event.key === Qt.Key_C) {
              if (installCmd.selectedText.length > 0)
                installCmd.copy()
              else
                Quickshell.clipboardText = installCmd.text

              event.accepted = true
            }
          }
        }

        Button {
          id: copyInstallCmd
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter

          text: "Copy"
          onClicked: Quickshell.clipboardText = installCmd.text
        }
      }
      Button { Layout.alignment: Qt.AlignHCenter; text: "Open Mise setup"; onClicked: if (root.service) root.service.installBeam() }
      Text { textFormat: Text.PlainText; Layout.alignment: Qt.AlignHCenter; text: root.snapshotData.onboarding && root.snapshotData.onboarding.mise_available ? "Mise detected" : "Mise was not detected; the setup helper will explain the Omarchy prerequisite."; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      Item { Layout.fillHeight: true }
    }
  }

  Component {
    id: emptyView
    ColumnLayout {
      Item { Layout.fillHeight: true }
      Text { textFormat: Text.PlainText; Layout.alignment: Qt.AlignHCenter; text: "BEAM Deck is ready"; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText; Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: Style.space(540); text: "No user BEAM VMs are running. Start iex, mix phx.server, Livebook, a release, or any Erlang/Gleam node and it will appear automatically."; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
      Text { textFormat: Text.PlainText; Layout.alignment: Qt.AlignHCenter; text: "For deep telemetry, launch a distributed node (for example: iex --sname my_app -S mix)."; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      Item { Layout.fillHeight: true }
    }
  }

  Component {
    id: dashboardView
    GridLayout {
      id: dashboardGrid
      columns: width >= Style.space(900) ? 3 : 1
      columnSpacing: Style.space(14)
      rowSpacing: Style.space(10)

      Flickable {
        Layout.preferredWidth: dashboardGrid.columns > 1 ? Style.space(320) : -1
        Layout.fillWidth: dashboardGrid.columns === 1
        Layout.preferredHeight: dashboardGrid.columns === 1 ? Style.space(180) : -1
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: hostColumn.implicitHeight
        clip: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
          id: hostColumn
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { width: parent.width; text: "ATTENTION"; foreground: root.fg; fontFamily: Style.font.family }
          Text { textFormat: Text.PlainText; width: parent.width; text: Number(root.summary.active_incident_count || 0) + " incidents  /  " + Number(root.summary.forecast_warning_count || 0) + " trends  /  " + Number(root.summary.watched_problem_count || 0) + " watch issues"; color: Number(root.summary.critical_incident_count || 0) > 0 ? root.urgent : root.fg; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap }
          Text { textFormat: Text.PlainText; width: parent.width; visible: (root.snapshotData.incidents || []).length > 0; text: (root.snapshotData.incidents || []).length ? root.snapshotData.incidents[0].title : ""; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap }
          Flow {
            width: parent.width; spacing: Style.space(6)
            Button { text: "Triage"; onClicked: root.openInvestigation("triage") }
            Button { text: "Recorder"; onClicked: root.openInvestigation("recorder") }
            Button { text: "Watchlist"; onClicked: root.openInvestigation("pins") }
          }
          PanelSeparator { width: parent.width; foreground: root.fg }
          PanelSectionHeader { width: parent.width; text: "HOST"; foreground: root.fg; fontFamily: Style.font.family }
          StatLine { label: "Local BEAM VMs"; value: String(root.summary.runtime_count || 0) }
          StatLine { label: "Deeply attached"; value: String(root.summary.attached_count || 0) }
          StatLine { label: "Schedulers online"; value: String(root.summary.schedulers_online || 0) + " / " + String(root.summary.logical_cpus || root.host.logical_cpus || 0) + " CPUs"; warning: Number(root.summary.schedulers_online || 0) >= Number(root.summary.logical_cpus || 1) * 2 }
          StatLine { label: "BEAM RSS"; value: root.bytes(root.summary.beam_rss_bytes || 0) }
          StatLine { label: "Erlang processes"; value: Number(root.summary.process_count || 0).toLocaleString() }

          MiniSparkline {
            width: parent.width
            height: Style.space(38)
            values: root.hostSchedulerHistory()
            ceiling: Math.max(Number(root.summary.logical_cpus || root.host.logical_cpus || 1), 1)
          }

          PanelSeparator { width: parent.width; foreground: root.fg }
          PanelSectionHeader { width: parent.width; text: "ACTIVE SCHEDULER BUDGET"; foreground: root.fg; fontFamily: Style.font.family }
          Text { textFormat: Text.PlainText; visible: root.budget.length === 0; width: parent.width; text: "No attached local nodes to budget"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Repeater {
            model: root.budget
            RowLayout {
              required property var modelData
              width: hostColumn.width
              Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: String(modelData.node || ""); color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
              Text { textFormat: Text.PlainText; text: String(modelData.current || 0) + " → " + String(modelData.suggested || 0); color: Number(modelData.suggested || 0) < Number(modelData.current || 0) ? root.accent : root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: Number(modelData.suggested || 0) < Number(modelData.current || 0) }
              Button { visible: Number(modelData.suggested || 0) !== Number(modelData.current || 0); text: "Review"; onClicked: root.openInvestigation("budget") }
            }
          }
          Text { textFormat: Text.PlainText; width: parent.width; text: "Review all proposed changes together in a 30-second budget trial. Recommendations are advisory, not automatic throttling."; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

          PanelSeparator { width: parent.width; foreground: root.fg }
          PanelSectionHeader { width: parent.width; text: "LOCAL RUNTIMES"; foreground: root.fg; fontFamily: Style.font.family }
          Repeater {
            model: root.host.runtimes || []
            BorderSurface {
              required property var modelData
              width: hostColumn.width
              implicitHeight: localRow.implicitHeight + Style.space(18)
              color: Util.alpha(root.fg, 0.04); borderSpec: Border.flat(Util.alpha(root.fg, 0.10), 1); radius: Style.cornerRadius
              Column {
                id: localRow; anchors.fill: parent; anchors.margins: Style.space(9); spacing: Style.space(3)
                Text { textFormat: Text.PlainText; width: parent.width; text: modelData.cwd ? String(modelData.cwd).split("/").pop() || ("PID " + modelData.pid) : "PID " + modelData.pid; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideMiddle }
                Text { textFormat: Text.PlainText; width: parent.width; text: "PID " + modelData.pid + "  ·  " + root.bytes(modelData.rss_bytes) + (modelData.cpu_percent === null || modelData.cpu_percent === undefined ? "" : "  ·  " + Number(modelData.cpu_percent).toFixed(1) + "% CPU"); color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                Text { textFormat: Text.PlainText; width: parent.width; text: modelData.os_only ? "OS visibility only" : ("Deep attached · " + String(modelData.node_name || "distributed node")); color: modelData.os_only ? root.dim : root.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.fg }
          PanelSectionHeader { width: parent.width; text: "ALERTS"; foreground: root.fg; fontFamily: Style.font.family }
          Text { textFormat: Text.PlainText; visible: root.alerts.length === 0; width: parent.width; text: "No active alerts"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          Repeater {
            model: root.alerts
            Text { textFormat: Text.PlainText;
              required property var modelData
              width: hostColumn.width
              text: (modelData.severity === "critical" ? "!! " : "! ") + modelData.title + "\n" + modelData.message
              color: modelData.severity === "critical" ? root.urgent : root.fg
              font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { width: parent.width; foreground: root.fg }
          PanelSectionHeader { width: parent.width; text: "RECENT EVENTS"; foreground: root.fg; fontFamily: Style.font.family }
          Text { textFormat: Text.PlainText; visible: !(root.snapshotData.events || []).length; width: parent.width; text: "No recent node or Deep Event signals"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Repeater {
            model: (root.snapshotData.events || []).slice(0, 12)
            Text { textFormat: Text.PlainText;
              required property var modelData
              width: hostColumn.width
              text: root.eventText(modelData)
              color: String(modelData.kind || "") === "nodedown" ? root.urgent : root.dim
              font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
            }
          }
        }
      }

      Rectangle { visible: dashboardGrid.columns > 1; Layout.fillHeight: true; Layout.preferredWidth: 1; color: Util.alpha(root.fg, 0.12) }

      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: detailColumn.implicitHeight
        clip: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
          id: detailColumn
          width: parent.width
          spacing: Style.space(12)

          Flickable {
            width: parent.width
            height: tabsRow.implicitHeight
            contentWidth: tabsRow.implicitWidth
            contentHeight: tabsRow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            Row {
              id: tabsRow
              spacing: Style.space(7)
              Repeater {
                model: root.nodes
                Button {
                  required property var modelData
                  text: String(modelData.name || "")
                  selected: root.selected() && String(modelData.name || "") === String(root.selected().name || "")
                  onClicked: root.selectedNode = String(modelData.name || "")
                }
              }
            }
          }

          Text { textFormat: Text.PlainText;
            visible: root.nodes.length === 0
            width: parent.width
            text: "The local BEAM VMs above are not distributed nodes, so BEAM Deck cannot inspect OTP internals yet. Restart the development VM with a node name, for example:\n\niex --sname my_app -S mix phx.server"
            color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap
          }

          Loader {
            width: parent.width
            active: root.nodes.length > 0
            sourceComponent: nodeDetail
          }
        }
      }
    }
  }

  Component {
    id: nodeDetail
    Column {
      id: nd
      width: parent.width
      spacing: Style.space(10)
      readonly property var node: root.selected()
      visible: node !== null

      Text { textFormat: Text.PlainText; width: parent.width; text: nd.node ? nd.node.name : ""; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideRight }
      Text { textFormat: Text.PlainText; visible: nd.node && !nd.node.attached; width: parent.width; text: "Node discovered but not attached: " + String(nd.node.error || "authentication/unreachable"); color: root.urgent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }

      GridLayout {
        visible: nd.node && nd.node.attached
        width: parent.width; columns: width >= Style.space(580) ? 4 : 2; columnSpacing: Style.space(12); rowSpacing: Style.space(5)
        Metric { title: "OTP"; value: nd.node ? String(nd.node.otp || "—") : "—" }
        Metric { title: "ELIXIR"; value: nd.node && nd.node.elixir ? nd.node.elixir : "BEAM" }
        Metric { title: "PROCESSES"; value: nd.node ? Number(nd.node.processes || 0).toLocaleString() : "0"; meta: nd.node ? root.percent(nd.node.processes, nd.node.process_limit) : "" }
        Metric { title: "ATOMS"; value: nd.node ? Number(nd.node.atoms || 0).toLocaleString() : "0"; meta: nd.node ? root.percent(nd.node.atoms, nd.node.atom_limit) : "" }
        Metric { title: "PORTS"; value: nd.node ? Number(nd.node.ports || 0).toLocaleString() : "0"; meta: nd.node ? root.percent(nd.node.ports, nd.node.port_limit) : "" }
        Metric { title: "ETS"; value: nd.node ? Number(nd.node.ets || 0).toLocaleString() : "0" }
        Metric { title: "SCHEDULERS"; value: nd.node ? String(nd.node.schedulers_online || 0) + " / " + String(nd.node.schedulers || 0) : "—" }
        Metric { title: "RUN QUEUE"; value: nd.node ? String(nd.node.run_queue || 0) : "0" }
        Metric { title: "SCHED UTIL"; value: nd.node ? root.schedulerAverage(nd.node) : "—"; meta: "panel sampling" }
        Metric { title: "HOST PID"; value: nd.node && Number(nd.node.os_pid || 0) > 0 ? String(nd.node.os_pid) : "—"; meta: nd.node && nd.node.local ? "local VM" : "remote" }
      }

      Flow {
        visible: nd.node && nd.node.attached && (nd.node.scheduler_utilization || []).length > 0
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: nd.node && nd.node.scheduler_utilization ? nd.node.scheduler_utilization : []
          Rectangle {
            required property var modelData
            width: Style.space(28); height: Style.space(22); radius: Style.space(3)
            color: Util.alpha(root.accent, 0.10 + Math.min(0.82, Number(modelData.utilization || 0) * 0.82))
            border.width: 1; border.color: Util.alpha(root.fg, 0.10)
            Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: String(modelData.id); color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }
        }
      }
      MiniSparkline {
        visible: nd.node && nd.node.attached
        width: parent.width
        height: Style.space(34)
        values: nd.node ? root.nodeRunQueueHistory(nd.node.name) : []
        ceiling: nd.node ? Math.max(Number(nd.node.schedulers_online || 1), 1) : 1
      }

      Flow {
        visible: nd.node && nd.node.attached
        width: parent.width; spacing: Style.space(6)
        Button { text: "ETS lens"; onClicked: root.openInvestigation("ets", nd.node.name) }
        Button { text: "Pin node"; onClicked: if (root.service) root.service.pinNode(nd.node.name) }
        Button { text: "Budget trial"; onClicked: root.openInvestigation("budget") }
      }
      PanelSeparator { visible: nd.node && nd.node.attached; width: parent.width; foreground: root.fg }
      PanelSectionHeader { visible: nd.node && nd.node.attached; width: parent.width; text: "MEMORY"; foreground: root.fg; fontFamily: Style.font.family }
      Flow {
        visible: nd.node && nd.node.attached
        width: parent.width; spacing: Style.space(8)
        MemoryPill { label: "Processes"; value: nd.node ? root.bytes((nd.node.memory || {}).processes || 0) : "—" }
        MemoryPill { label: "Binary"; value: nd.node ? root.bytes((nd.node.memory || {}).binary || 0) : "—" }
        MemoryPill { label: "ETS"; value: nd.node ? root.bytes((nd.node.memory || {}).ets || 0) : "—" }
        MemoryPill { label: "Code"; value: nd.node ? root.bytes((nd.node.memory || {}).code || 0) : "—" }
        MemoryPill { label: "Atoms"; value: nd.node ? root.bytes((nd.node.memory || {}).atom || 0) : "—" }
      }

      PanelSeparator { visible: nd.node && nd.node.attached; width: parent.width; foreground: root.fg }
      RowLayout {
        visible: nd.node && nd.node.attached
        width: parent.width; spacing: Style.space(8)
        PanelSectionHeader { text: "HOT PROCESSES"; foreground: root.fg; fontFamily: Style.font.family; Layout.fillWidth: true }
        Button { text: "IEx remsh"; onClicked: if (root.service) root.service.remsh(nd.node.name) }
        Button { text: nd.node && nd.node.deep_events_active ? "Stop events" : "Deep events"; enabled: !!nd.node.deep_events_capable; onClicked: if (root.service) root.service.deepEvents(nd.node.name, !nd.node.deep_events_active) }
        Button { text: "Restore"; onClicked: if (root.service) root.service.restore(nd.node.name) }
      }
      Text { textFormat: Text.PlainText; visible: !!(nd.node && nd.node.process_scan_error); width: parent.width; text: "Process scan: " + nd.node.process_scan_error; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
      Repeater {
        model: nd.node && nd.node.hot_processes ? nd.node.hot_processes.slice(0, 12) : []
        BorderSurface {
          required property var modelData
          width: nd.width
          implicitHeight: hotRow.implicitHeight + Style.space(14)
          color: modelData.mailbox >= 5000 ? Util.alpha(root.urgent, 0.08) : Util.alpha(root.fg, 0.035)
          borderSpec: Border.flat(Util.alpha(root.fg, 0.10), 1); radius: Style.cornerRadius
          RowLayout {
            id: hotRow; anchors.fill: parent; anchors.margins: Style.space(7); spacing: Style.space(7)
            Text { textFormat: Text.PlainText;
              id: hotText; Layout.fillWidth: true
              text: (modelData.name || modelData.pid) + "   mailbox " + Number(modelData.mailbox || 0).toLocaleString() + "   mem " + root.bytes(modelData.memory_bytes || 0) + "   reds " + Number(modelData.reductions || 0).toLocaleString() + "\n" + String(modelData.current_function || "") + "   " + modelData.pid
              color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight
            }
            Button { text: "Inspect / GC"; enabled: !root.stale && String(modelData.pid || "").indexOf("<") === 0; onClicked: root.openInvestigation("process", nd.node.name, modelData.pid) }
          }
        }
      }

      Text { textFormat: Text.PlainText;
        visible: nd.node && (nd.node.restart_churn || []).length > 0
        width: parent.width
        text: "Registered-name churn: " + (nd.node ? nd.node.restart_churn.map(function(c) { return c.name + " ×" + c.count }).join("  ·  ") : "")
        color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
      }

      PanelSeparator { visible: nd.node && nd.node.attached; width: parent.width; foreground: root.fg }
      PanelSectionHeader { visible: nd.node && nd.node.attached; width: parent.width; text: "RUNTIME CONTROLS / ORIGINAL-VALUE RESTORE"; foreground: root.fg; fontFamily: Style.font.family }
      Flow {
        visible: nd.node && nd.node.attached
        width: parent.width
        spacing: Style.space(8)
        Text { textFormat: Text.PlainText; text: "Normal schedulers"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        SpinBox { id: schedSpin; from: 1; to: nd.node ? Math.max(1, nd.node.schedulers || 1) : 1; value: nd.node ? Math.max(1, nd.node.schedulers_online || 1) : 1 }
        Button { text: "Apply"; enabled: !root.stale; onClicked: if (root.service) root.service.setSchedulers(nd.node.name, schedSpin.value) }
        Text { textFormat: Text.PlainText; text: "Dirty CPU"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        SpinBox { id: dirtySpin; from: 1; to: nd.node ? Math.max(1, nd.node.dirty_cpu_schedulers || 1) : 1; value: nd.node ? Math.max(1, nd.node.dirty_cpu_schedulers_online || 1) : 1 }
        Button { text: "Apply"; enabled: !root.stale; onClicked: if (root.service) root.service.setDirtySchedulers(nd.node.name, dirtySpin.value) }
        Button { text: "Startup flags"; onClicked: if (root.service) root.service.launchProfile(schedSpin.value, dirtySpin.value) }
      }

      PanelSeparator { visible: nd.node && nd.node.attached; width: parent.width; foreground: root.fg }
      PanelSectionHeader { visible: nd.node && nd.node.attached; width: parent.width; text: "TOPOLOGY"; foreground: root.fg; fontFamily: Style.font.family }
      Text { textFormat: Text.PlainText; visible: nd.node && nd.node.attached; width: parent.width; text: nd.node && nd.node.peers && nd.node.peers.length ? (nd.node.name + " sees  " + nd.node.peers.join("   ·   ")) : "No connected peer nodes reported"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
      Text { textFormat: Text.PlainText; visible: nd.node && nd.node.attached && (nd.node.expected_peers || []).length > 0; width: parent.width; text: "Expected: " + nd.node.expected_peers.join("   ·   "); color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
      Text { textFormat: Text.PlainText; visible: nd.node && nd.node.attached && ((nd.node.expected_peers || []).filter(function(peer) { return (nd.node.peers || []).indexOf(peer) < 0 })).length > 0; width: parent.width; text: "Missing expected: " + (nd.node.expected_peers || []).filter(function(peer) { return (nd.node.peers || []).indexOf(peer) < 0 }).join("   ·   "); color: root.urgent; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; wrapMode: Text.WordWrap }
    }
  }

  component StatLine: Item {
    property string label: ""
    property string value: ""
    property bool warning: false
    width: parent ? parent.width : 100; implicitHeight: Math.max(statLabel.implicitHeight, statValue.implicitHeight)
    Text { textFormat: Text.PlainText; id: statLabel; anchors.left: parent.left; text: parent.label; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
    Text { textFormat: Text.PlainText; id: statValue; anchors.right: parent.right; text: parent.value; color: parent.warning ? root.urgent : root.fg; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: parent.warning }
  }
  component Metric: ColumnLayout {
    property string title: ""; property string value: ""; property string meta: ""
    Layout.fillWidth: true
    Text { textFormat: Text.PlainText; text: parent.title; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
    Text { textFormat: Text.PlainText; text: parent.value; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true }
    Text { textFormat: Text.PlainText; visible: parent.meta !== ""; text: parent.meta; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
  }
  component MemoryPill: BorderSurface {
    id: pill
    property string label: ""; property string value: ""
    width: Math.max(memCol.implicitWidth + Style.space(18), Style.space(92)); implicitHeight: memCol.implicitHeight + Style.space(14)
    color: Util.alpha(root.fg, 0.04); borderSpec: Border.flat(Util.alpha(root.fg, 0.10), 1); radius: Style.cornerRadius
    Column {
      id: memCol
      anchors.centerIn: parent
      spacing: Style.space(2)
      Text { textFormat: Text.PlainText;
        text: pill.label
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text { textFormat: Text.PlainText;
        text: pill.value
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }
  }
  component MiniSparkline: Canvas {
    property var values: []
    property real ceiling: 1
    antialiasing: true
    onValuesChanged: requestPaint()
    onCeilingChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!values || values.length < 2 || width <= 2 || height <= 2) return
      var maxValue = Math.max(Number(ceiling || 1), 1)
      for (var i = 0; i < values.length; i++) maxValue = Math.max(maxValue, Number(values[i] || 0))
      ctx.strokeStyle = root.accent
      ctx.lineWidth = 1.5
      ctx.beginPath()
      for (var j = 0; j < values.length; j++) {
        var x = j * (width - 1) / Math.max(values.length - 1, 1)
        var y = height - 1 - (Number(values[j] || 0) / maxValue) * (height - 2)
        if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
      ctx.stroke()
    }
  }
}