import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "DeckState.js" as DeckState

Item {
  id: root
  property var service: null
  property string targetNode: ""
  property string targetPid: ""
  property string tab: "triage"
  readonly property var tabDefinitions: [{id:"triage",label:"Triage"},{id:"recorder",label:"Flight recorder"},{id:"process",label:"Process"},{id:"ets",label:"ETS lens"},{id:"pins",label:"Watchlist"},{id:"budget",label:"Budget trial"}]
  property string query: ""
  property bool showResolved: false
  property var expandedIncidents: ({})
  property bool gcConfirmed: false
  property double nowMs: Date.now()
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }
  property bool budgetConfirmed: false
  property string processRequest: ""
  property string etsRequest: ""
  property string frameRequest: ""
  property string diffRequest: ""
  property string exportRequest: ""
  property string fromFrame: ""
  property string toFrame: ""
  property string etsSort: "memory"
  readonly property var snapshot: service ? service.snapshot : DeckState.emptySnapshot()
  readonly property var jobs: service ? service.jobs : ({})
  readonly property var nodes: snapshot.nodes || []
  readonly property var timeline: (snapshot.flight_recorder || {}).timeline || []
  readonly property var processJob: DeckState.jobFor(jobs, processRequest, "inspect_process", targetNode)
  readonly property var etsJob: DeckState.jobFor(jobs, etsRequest, "inspect_ets", targetNode)
  readonly property var frameJob: DeckState.jobFor(jobs, frameRequest, "recorder_frame")
  readonly property var diffJob: DeckState.jobFor(jobs, diffRequest, "compare_frames")
  readonly property var exportJob: DeckState.jobFor(jobs, exportRequest, "export_bundle")
  readonly property var processResult: result(processJob)
  readonly property bool processActionable: service && service.panelOpen && DeckState.canActOnProcess(snapshot, processResult, service.historicalMode, service.daemonRunning, nowMs)
  onProcessActionableChanged: if (!processActionable) gcConfirmed = false
  onProcessResultChanged: gcConfirmed = false
  readonly property var etsResult: result(etsJob)
  readonly property var frameResult: result(frameJob)
  readonly property string budgetSignature: JSON.stringify(snapshot.budget || [])
  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(fg, 0.65)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  onBudgetSignatureChanged: budgetConfirmed = false
  onSnapshotChanged: {
    var next = {}
    ;(snapshot.incidents || []).forEach(function(i) { if (root.expandedIncidents[i.id]) next[i.id] = true })
    expandedIncidents = next
  }
  onTargetNodeChanged: { processRequest = ""; etsRequest = ""; targetPid = ""; gcConfirmed = false }
  onFrameResultChanged: if (frameResult && service) service.historicalMode = true
  Component.onCompleted: if (!targetNode && nodes.length) targetNode = nodes[0].name

  function result(job) { return job && job.status === "complete" ? job.result : null }
  function jobText(job, idle) {
    if (!job) return idle
    if (job.status === "error") return "Unavailable: " + String(job.error || "request failed").split("_").join(" ")
    if (job.status === "canceled") return "Canceled. Request again from a live view."
    return job.status === "complete" ? "Captured result; refresh deliberately to inspect again." : "Inspecting\u2026 the cockpit remains live."
  }
  function activate(nextTab, node, pid) {
    if (node) targetNode = node
    tab = nextTab || "triage"
    if (pid && tab === "process") {
      targetPid = pid
      gcConfirmed = false
      if (service && !service.historicalMode) processRequest = service.inspectProcess(targetNode, targetPid)
    }
  }
  function returnLive() {
    frameRequest = ""
    diffRequest = ""
    if (service) service.returnLive()
  }
  function cycleTab(direction) {
    if (!direction) return
    var index = 0
    for (var i = 0; i < tabDefinitions.length; i++) if (tabDefinitions[i].id === tab) { index = i; break }
    index = (index + (direction > 0 ? 1 : -1) + tabDefinitions.length) % tabDefinitions.length
    activate(tabDefinitions[index].id, "", "")
  }
  function currentScroll() {
    return viewLoader.item
  }
  function keyboardMove(dx, dy) {
    if (dx !== 0) {
      cycleTab(dx)
      return
    }
    if (dy === 0) return
    var view = currentScroll()
    if (!view) return
    var limit = Math.max(0, view.contentHeight - view.height)
    var step = Math.max(Style.space(64), view.height * 0.16)
    view.contentY = Math.max(0, Math.min(limit, view.contentY + (dy > 0 ? step : -step)))
  }
  function handleShortcut(text) {
    var nextTab = DeckState.investigationTabShortcut(text)
    if (!nextTab) return false
    activate(nextTab, "", "")
    return true
  }
  function options() { return timeline.map(function(f) { return {id:f.frame_id, label:DeckState.time(f.at_ms)+"  |  "+f.alert_count+" alerts  |  "+DeckState.bytes(f.beam_rss_bytes)} }) }
  function optionIndex(id) { var list = options(); for (var i=0;i<list.length;i++) if (list[i].id===id) return i; return -1 }
  function selectedFrom() { return fromFrame || (timeline.length ? timeline[0].frame_id : "") }
  function selectedTo() { return toFrame || (timeline.length ? timeline[timeline.length-1].frame_id : "") }
  function runExport(range) { if (service) exportRequest = service.exportBundle(range ? selectedFrom() : null, range ? selectedTo() : null) }
  function actionLabel(action) {
    if (action.label) return String(action.label).slice(0,60)
    var labels={view_frame:"View evidence frame", gc_process:"Review process GC", pin_process:"Pin process", apply_budget_trial:"Review budget trial", inspect_process:"Inspect process", inspect_ets:"ETS lens", remsh:"IEx remsh", pin_node:"Pin node", export_bundle:"Export", budget_trial_revert:"Retry rollback"}
    return labels[action.kind] || "Inspect"
  }
  function runAction(action) {
    if (!service) return
    switch (action.kind) {
      case "view_frame": tab="recorder"; frameRequest=service.recorderFrame(action.frame_id); break;
      case "gc_process": activate("process", action.node, action.pid); break
      case "pin_process": service.pinProcess(action.node, action.name); break
      case "apply_budget_trial": activate("budget", "", ""); break
      case "inspect_process": activate("process", action.node, action.pid); break
      case "inspect_ets": activate("ets", action.node, ""); etsRequest = service.inspectEts(action.node, etsSort); break
      case "remsh": service.remsh(action.node); break
      case "pin_node": service.pinNode(action.node); break
      case "budget_trial_revert": service.revertBudget(action.trial_id); break
      case "export_bundle": runExport(false); break
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(6)
      Repeater {
        model: root.tabDefinitions
        Button { required property var modelData; text: modelData.label; selected: root.tab===modelData.id; onClicked: root.tab=modelData.id }
      }
    }
    RowLayout {
      Layout.fillWidth: true
      visible: ["process","ets","pins"].indexOf(root.tab)>=0
      Label { text: "NODE" }
      Controls.ComboBox {
        Layout.fillWidth: true
        model: root.nodes.map(function(n) { return n.name })
        currentIndex: model.indexOf(root.targetNode)
        onActivated: function(index) { root.targetNode = model[index] }
        Accessible.name: "Target node for focused diagnostics"
      }
      Label { text: "Explicit inspection only" }
    }
    RowLayout {
      visible: root.service && root.service.historicalMode
      Layout.fillWidth: true
      Label { Layout.fillWidth: true; color: root.accent; text: "HISTORICAL SELECTION / ACTIONS LOCKED  " + (root.frameResult ? DeckState.time(root.frameResult.at_ms) : "Selected frame loading or expired") }
      Button { text: "Return to live"; onClicked: root.returnLive() }
    }
    Loader {
      id: viewLoader
      Layout.fillWidth: true
      Layout.fillHeight: true
      sourceComponent: root.tab==="triage" ? triageView : root.tab==="recorder" ? recorderView : root.tab==="process" ? processView : root.tab==="ets" ? etsView : root.tab==="pins" ? pinsView : budgetView
    }
    RowLayout {
      Layout.fillWidth: true
      visible: root.exportJob !== null
      Label { Layout.fillWidth: true; text: root.exportJob && root.exportJob.status==="complete" ? "Exported " + DeckState.bytes(root.exportJob.result.bytes) + " - review operational metadata before sharing." : root.jobText(root.exportJob, "") }
      Button { text: "Copy ZIP path"; enabled: root.exportJob && root.exportJob.status==="complete"; onClicked: Quickshell.clipboardText=root.exportJob.result.path }
    }
  }

  Component {
    id: triageView
    Flickable {
      id: triageScroll
      contentWidth: width; contentHeight: triageColumn.implicitHeight; clip: true
      Controls.ScrollBar.vertical: Controls.ScrollBar {}
      Column {
        id: triageColumn
        width: triageScroll.width
        spacing: Style.space(12)
        RowLayout {
          width: parent.width
          Heading { text: "Signals, not guesses"; Layout.fillWidth: true }
          Controls.CheckBox { text: "Resolved"; checked: root.showResolved; onToggled: root.showResolved=checked }
          Button { text: "Export diagnostics"; onClicked: root.runExport(false) }
        }
        Label { visible:root.service && root.service.historicalMode; width:parent.width; text:"These incident cards continue to show live telemetry. Return to live to unlock runtime actions." }
        Label { width: parent.width; text: "Observed facts, nearby correlations and trend heuristics stay visibly distinct. Correlation does not establish a cause." }
        Controls.TextField { width: parent.width; placeholderText: "Filter incidents by node or symptom"; text: root.query; onTextEdited: root.query=text; Accessible.name: "Filter incidents" }
        Label { visible: !(root.snapshot.incidents || []).some(function(i) { return i.status==="active" }); width: parent.width; text: "No active incidents. The live cockpit and retained frames remain available." }
        Repeater {
          model: DeckState.filterRows((root.snapshot.incidents || []).filter(function(i) { return root.showResolved || i.status==="active" }), root.query)
          InfoCard {
            id: incidentCard
            required property var modelData
            width: triageColumn.width
            critical: modelData.severity==="critical" && modelData.status==="active"
            Heading { width: parent.width; text: incidentCard.modelData.title; color: incidentCard.critical ? root.urgent : root.fg }
            Label { width: parent.width; text: String(incidentCard.modelData.severity).toUpperCase()+"  /  "+incidentCard.modelData.status+"  /  "+incidentCard.modelData.evidence_class+"  /  "+String(incidentCard.modelData.node || "host") }
            Label { width: parent.width; text: incidentCard.modelData.summary; color: root.fg }
            Repeater {
              model: (incidentCard.modelData.evidence || []).slice(0, root.expandedIncidents[incidentCard.modelData.id] ? 12 : 2)
              Label { required property var modelData; width: parent.width; text: "["+modelData.class+"] "+String(modelData.text || "Observed operational metadata")+(modelData.eta_ms ? "  ETA "+DeckState.duration(modelData.eta_ms) : "") }
            }
            Button {
              visible: (incidentCard.modelData.evidence || []).length > 2
              text: root.expandedIncidents[incidentCard.modelData.id] ? "Collapse evidence" : "Show all evidence ("+(incidentCard.modelData.evidence || []).length+")"
              onClicked: {
                var next = Object.assign({}, root.expandedIncidents)
                next[incidentCard.modelData.id] = !next[incidentCard.modelData.id]
                root.expandedIncidents = next
              }
            }
            Flow {
              width: parent.width; spacing: Style.space(6)
              Repeater {
                model: incidentCard.modelData.actions || []
                Button {
                  required property var modelData
                  text: root.actionLabel(modelData)
                  enabled: modelData.kind==="view_frame" || modelData.kind==="export_bundle" || modelData.kind==="budget_trial_revert" || (root.service && !root.service.historicalMode && incidentCard.modelData.status==="active")
                  onClicked: root.runAction(modelData)
                }
              }
            }
            Label { width: parent.width; text: "First "+DeckState.time(incidentCard.modelData.first_seen_ms)+"  |  Last evidence "+DeckState.time(incidentCard.modelData.last_seen_ms) }
          }
        }
        Heading { text: "Resource outlook" }
        Label { width: parent.width; visible: !(root.snapshot.forecasts || []).length; text: "No qualified trend. Forecasts need a sustained, consistent sample window and reset across VM restarts. This is not a guarantee of future health." }
        Repeater {
          model: root.snapshot.forecasts || []
          InfoCard {
            id: forecastCard
            required property var modelData
            width: triageColumn.width
            critical: modelData.severity==="critical"
            Heading { width: parent.width; text: forecastCard.modelData.metric+"  /  "+forecastCard.modelData.node }
            Label { width: parent.width; color: root.fg; text: forecastCard.modelData.kind==="capacity" ? "Estimated headroom: "+DeckState.duration(forecastCard.modelData.eta_ms)+" at the observed growth rate" : "Sustained growth - no hard exhaustion ETA" }
            Label { width:parent.width; text:"Current "+forecastCard.modelData.current+(forecastCard.modelData.limit ? " / "+forecastCard.modelData.limit : "")+"  |  Growth "+Number(forecastCard.modelData.rate_per_second).toFixed(2)+" units/s" }
            Label { width: parent.width; text: "Heuristic  |  Fit quality "+Math.round(forecastCard.modelData.confidence*100)+"% (not probability)  |  "+forecastCard.modelData.sample_count+" samples over "+DeckState.duration(forecastCard.modelData.span_ms) }
          }
        }
        Heading { visible: (root.snapshot.crash_triage || []).length>0; text: "Local runtime exits" }
        Repeater {
          model: root.snapshot.crash_triage || []
          InfoCard {
            id: exitCard
            required property var modelData
            width: triageColumn.width
            critical: modelData.status==="matched"
            Heading { text: "PID "+exitCard.modelData.pid+"  /  "+DeckState.time(exitCard.modelData.at_ms) }
            Label { width: parent.width; text: "Dump evidence: "+exitCard.modelData.status+". An exit without matched evidence may be a normal shutdown." }
            CopyText { visible: !!exitCard.modelData.slogan; width: parent.width; text: exitCard.modelData.slogan || "" }
            Flow {
              width: parent.width; spacing: Style.space(6)
              Button { visible: !!exitCard.modelData.slogan; text: "Copy slogan"; onClicked: Quickshell.clipboardText=exitCard.modelData.slogan }
              Button { text: "Export header evidence"; onClicked: root.runExport(false) }
            }
          }
        }
      }
    }
  }

  Component {
    id: processView
    Flickable {
      id: processScroll
      contentWidth: width; contentHeight: processColumn.implicitHeight; clip: true
      Controls.ScrollBar.vertical: Controls.ScrollBar {}
      Column {
        id: processColumn
        width: processScroll.width; spacing: Style.space(12)
        Heading { text: "Focused process inspection" }
        Label { width: parent.width; text: "Open a process from Hot Processes or the Watchlist. Snapshot metadata is bounded; application state and message contents are never collected." }
        RowLayout {
          width: parent.width
          CopyText { Layout.fillWidth: true; text: root.targetPid || "No process selected" }
          Button { text: "Refresh"; enabled: !!root.targetPid && root.service && !root.service.historicalMode; onClicked: root.processRequest=root.service.inspectProcess(root.targetNode,root.targetPid) }
        }
        Label { width: parent.width; color: root.processJob && root.processJob.status==="error" ? root.urgent : root.dim; text: root.jobText(root.processJob,"Select Inspect on a live process to begin.") }
        CopyText { width: parent.width; visible: !!root.processResult; text: root.processResult ? DeckState.processText(root.processResult) : "" }
        Flow {
          width: parent.width; spacing: Style.space(6)
          Button { text: "Copy report"; enabled: !!root.processResult; onClicked: Quickshell.clipboardText=DeckState.processText(root.processResult) }
          Button { text: "Pin registered name"; enabled: root.processResult && !!root.processResult.registered_name && root.service && !root.service.historicalMode; onClicked: root.service.pinProcess(root.targetNode,root.processResult.registered_name) }
          Button { text: "IEx remsh"; enabled: root.service && !root.service.historicalMode && !!root.targetNode; onClicked: root.service.remsh(root.targetNode) }
        }
        InfoCard {
          width: parent.width
          visible: !!root.processResult
          Heading { text: "Deliberate action: process GC" }
          Label { width: parent.width; text: "GC can pause the selected process and may not reduce its retained data. This acts on the live PID, not a historical frame." }
          Label { width: parent.width; visible: root.processResult && !root.processActionable; text: "Captured metadata is read-only. Reinspect this process from a fresh live VM before collecting garbage." }
          Controls.CheckBox { enabled: root.processActionable; width: parent.width; text: "I understand the pause risk for this process"; checked: root.gcConfirmed; onToggled: root.gcConfirmed=checked }
          Button { text: "Collect this process"; enabled: root.gcConfirmed && root.processActionable; onClicked: { root.service.collectGc(root.targetNode,root.targetPid,root.processResult.creation); root.gcConfirmed=false } }
        }
      }
    }
  }

  Component {
    id: etsView
    Flickable {
      id: etsScroll
      contentWidth: width; contentHeight: etsColumn.implicitHeight; clip: true
      Controls.ScrollBar.vertical: Controls.ScrollBar {}
      Column {
        id: etsColumn
        width: etsScroll.width; spacing: Style.space(12)
        RowLayout {
          width: parent.width
          Heading { text: "ETS metadata lens"; Layout.fillWidth: true }
          Controls.ComboBox { model:["Memory","Elements"]; currentIndex:root.etsSort==="memory"?0:1; onActivated:function(index) { root.etsSort=index===0?"memory":"size" }; Accessible.name:"ETS sort order" }
          Button { text: "Inspect tables"; enabled: root.service && !!root.targetNode && !root.service.historicalMode; onClicked: root.etsRequest=root.service.inspectEts(root.targetNode,root.etsSort) }
        }
        Label { width: parent.width; text: root.jobText(root.etsJob,"No tables have been enumerated. Inspection is explicit and metadata-only.") }
        Label { width: parent.width; visible: !!root.etsResult; color: root.accent; text: root.etsResult ? root.etsResult.scanned_tables+" / "+root.etsResult.total_tables+" tables sampled  |  "+(root.etsResult.partial?"PARTIAL":"complete enumeration")+"  |  sorted by "+root.etsResult.sort+"  |  target word size "+root.etsResult.wordsize+" bytes" : "" }
        Label { width: parent.width; visible: !!root.etsResult; text: "Table metadata may change during collection. Scanned memory: "+DeckState.bytes(root.etsResult ? root.etsResult.sampled_memory_bytes : null)+". ETS counts have no hard-capacity forecast." }
        Repeater {
          model: root.etsResult ? root.etsResult.top || [] : []
          InfoCard {
            id: tableCard
            required property var modelData
            width: etsColumn.width
            RowLayout {
              width: parent.width
              Heading { Layout.fillWidth: true; text: tableCard.modelData.name; elide:Text.ElideMiddle }
              Heading { text: DeckState.bytes(tableCard.modelData.memory_bytes) }
            }
            Label { width: parent.width; text: tableCard.modelData.size+" elements  |  "+tableCard.modelData.type+"  |  "+tableCard.modelData.protection+"  |  "+(tableCard.modelData.named_table?"named":"unnamed") }
            Label { width: parent.width; text: "Owner "+(tableCard.modelData.owner_name || "")+" "+tableCard.modelData.owner+"  |  read concurrency "+tableCard.modelData.read_concurrency+"  |  write concurrency "+tableCard.modelData.write_concurrency }
            Button { text: "Inspect owner"; enabled: !!tableCard.modelData.owner && root.service && !root.service.historicalMode; onClicked: root.activate("process",root.targetNode,tableCard.modelData.owner) }
          }
        }
      }
    }
  }

  Component {
    id: recorderView
    Flickable {
      id: recorderScroll
      contentWidth: width; contentHeight: recorderColumn.implicitHeight; clip: true
      Controls.ScrollBar.vertical: Controls.ScrollBar {}
      Column {
        id: recorderColumn
        width: recorderScroll.width; spacing: Style.space(12)
        Heading { text: "Flight recorder" }
        Label { width: parent.width; text: (root.snapshot.flight_recorder || {}).frame_count+" retained frames. Retention is in memory; no recording is written unless you export. A historical selection is read-only." }
        RowLayout {
          width: parent.width
          Label { text: "FROM" }
          Controls.ComboBox { Layout.fillWidth:true; model:root.options(); textRole:"label"; currentIndex:root.optionIndex(root.selectedFrom()); onActivated:function(index) { root.fromFrame=model[index].id }; Accessible.name:"Earlier recorder frame" }
        }
        RowLayout {
          width: parent.width
          Label { text: "TO" }
          Controls.ComboBox { Layout.fillWidth:true; model:root.options(); textRole:"label"; currentIndex:root.optionIndex(root.selectedTo()); onActivated:function(index) { root.toFrame=model[index].id }; Accessible.name:"Later recorder frame" }
        }
        Flow {
          width: parent.width; spacing: Style.space(6)
          Button { text:"View earlier frame"; enabled:root.timeline.length>0; onClicked:{ root.service.historicalMode=true; root.frameRequest=root.service.recorderFrame(root.selectedFrom()) } }
          Button { text:"Compare selected frames"; enabled:root.timeline.length>1; onClicked:root.diffRequest=root.service.compareFrames(root.selectedFrom(),root.selectedTo()) }
          Button { text:"Export selected range"; enabled:root.timeline.length>0; onClicked:root.runExport(true) }
          Button { text:"Return to live"; onClicked:root.returnLive() }
        }
        Label { width:parent.width; text:root.jobText(root.frameJob,"Choose an explicit retained timestamp. Expired frames return an error, never a replacement frame.") }
        InfoCard {
          width:parent.width; visible:!!root.frameResult
          Heading { text:"THEN / "+(root.frameResult?DeckState.time(root.frameResult.at_ms):"") }
          Label { width:parent.width; text:root.frameResult?"BEAM RSS "+DeckState.bytes(root.frameResult.summary.beam_rss_bytes)+"  |  Processes "+root.frameResult.summary.process_count+"  |  Schedulers "+root.frameResult.summary.schedulers_online:"" }
          Repeater {
            model:root.frameResult?root.frameResult.nodes || []:[]
            Column {
              id: historicalNode
              required property var modelData
              width:parent.width; spacing:Style.space(5)
              Label { width:parent.width; font.bold:true; text:historicalNode.modelData.name+"  |  "+(historicalNode.modelData.attached?"attached":"unattached")+"  |  run queue "+String(historicalNode.modelData.run_queue===undefined?"unavailable":historicalNode.modelData.run_queue)+"  |  memory "+DeckState.bytes((historicalNode.modelData.memory || {}).total) }
              Label { width:parent.width; text:"Sampled then / "+DeckState.time(historicalNode.modelData.hot_processes_at_ms)+". Reductions are work counters, not per-process CPU percentages." }
              Flow {
                width:parent.width; spacing:Style.space(4)
                Repeater {
                  model:historicalNode.modelData.scheduler_utilization || []
                  Label { required property var modelData; text:"S"+modelData.id+" "+Math.round(modelData.utilization*100)+"%"; color:root.accent }
                }
              }
              Repeater {
                model:(historicalNode.modelData.hot_processes || []).slice(0,6)
                Label { required property var modelData; width:parent.width; text:modelData.pid+" "+modelData.name+" | mailbox "+modelData.mailbox+" | "+DeckState.bytes(modelData.memory_bytes)+" | reductions "+modelData.reductions }
              }
              Label { width:parent.width; visible:!(historicalNode.modelData.hot_processes || []).length; text:"No deep process sample in this frame. No historical mutation is available." }
            }
          }
        }
        Label { width:parent.width; text:root.jobText(root.diffJob,"Compare frames to see exact resource deltas, node transitions and sampled hot-set changes.") }
        CopyText { width:parent.width; visible:!!root.result(root.diffJob); text:root.result(root.diffJob)?DeckState.diffText(root.diffJob.result):"" }
      }
    }
  }

  Component {
    id: pinsView
    Flickable {
      id:pinsScroll
      contentWidth:width; contentHeight:pinsColumn.implicitHeight; clip:true
      Controls.ScrollBar.vertical:Controls.ScrollBar {}
      Column {
        id:pinsColumn
        width:pinsScroll.width; spacing:Style.space(12)
        Heading { text:"Your working set" }
        Label { width:parent.width; text:"Pin nodes or observed registered process names. Process pins follow PID replacements; only these targeted checks continue while the panel is closed." }
        Button { text:"Pin selected node"; enabled:!!root.targetNode && root.service && !root.service.historicalMode; onClicked:root.service.pinNode(root.targetNode) }
        Label { width:parent.width; color:root.urgent; visible:!!(root.snapshot.watchlist || {}).error; text:String((root.snapshot.watchlist || {}).error || "") }
        Label { width:parent.width; visible:!((root.snapshot.watchlist || {}).entries || []).length; text:"No pins yet. Pin a node here or a registered name from the process inspector." }
        Repeater {
          model:(root.snapshot.watchlist || {}).entries || []
          InfoCard {
            id:pinCard
            required property var modelData
            width:pinsColumn.width
            Heading { width:parent.width; text:pinCard.modelData.label || pinCard.modelData.name || pinCard.modelData.node }
            Label { width:parent.width; text:pinCard.modelData.node+"  /  "+pinCard.modelData.kind+"  /  "+pinCard.modelData.status; color:pinCard.modelData.status==="present"?root.accent:root.dim }
            Label { width:parent.width; visible:!!pinCard.modelData.pid; text:String(pinCard.modelData.pid || "")+"  |  Mailbox "+String(pinCard.modelData.mailbox || 0)+"  |  "+DeckState.bytes(pinCard.modelData.memory_bytes) }
            Flow {
              width:parent.width; spacing:Style.space(6)
              Button { text:"Inspect"; visible:pinCard.modelData.kind==="registered_process"; enabled:pinCard.modelData.status==="present" && root.service && !root.service.historicalMode; onClicked:root.activate("process",pinCard.modelData.node,pinCard.modelData.pid) }
              Button { text:"Remove pin"; onClicked:root.service.removePin(pinCard.modelData.id) }
            }
          }
        }
      }
    }
  }

  Component {
    id:budgetView
    Flickable {
      id:budgetScroll
      contentWidth:width; contentHeight:budgetColumn.implicitHeight; clip:true
      Controls.ScrollBar.vertical:Controls.ScrollBar {}
      Column {
        id:budgetColumn
        width:budgetScroll.width; spacing:Style.space(12)
        Heading { text:"Try the host budget, reversibly" }
        Label { width:parent.width; text:"Only attached local VMs participate. Review the entire proposal; the helper revalidates live scheduler values and VM identity before changing anything." }
        Repeater {
          model:root.snapshot.budget || []
          InfoCard {
            id:budgetCard
            required property var modelData
            width:budgetColumn.width
            Heading { width:parent.width; text:budgetCard.modelData.node }
            Label { width:parent.width; color:root.fg; text:budgetCard.modelData.current+" online  ->  "+budgetCard.modelData.suggested+" proposed" }
          }
        }
        Label { width:parent.width; text:"Without Keep, the trial expires after at most 30 seconds. Closing the panel also reverts. Keep ends the lease, not the original-value Restore capability. No helper can guarantee cleanup after SIGKILL, power loss or a partition." }
        Controls.CheckBox { width:parent.width; text:"I reviewed all proposed local scheduler changes"; checked:root.budgetConfirmed; onToggled:root.budgetConfirmed=checked }
        Button {
          text:"Begin 30-second trial"
          enabled:root.budgetConfirmed && root.service && !root.service.historicalMode && (root.snapshot.budget || []).some(function(r) { return r.current!==r.suggested }) && (!root.snapshot.budget_trial || ["kept","reverted"].indexOf(root.snapshot.budget_trial.status)>=0)
          onClicked:{ root.service.beginBudget(root.snapshot.budget); root.budgetConfirmed=false }
        }
        Label { width:parent.width; visible:!(root.snapshot.budget || []).length; text:"No eligible local nodes. Remote scheduler counts never consume this host's CPU budget." }
      }
    }
  }

  component Label: Text { color:root.dim; font.family:Style.font.family; font.pixelSize:Style.font.caption; wrapMode:Text.Wrap; textFormat:Text.PlainText }
  component Heading: Text { color:root.fg; font.family:Style.font.family; font.pixelSize:Style.font.body; font.bold:true; wrapMode:Text.Wrap; textFormat:Text.PlainText }
  component CopyText: TextEdit {
    color:root.fg; font.family:Style.font.family; font.pixelSize:Style.font.bodySmall
    readOnly:true; selectByMouse:true; selectByKeyboard:true; persistentSelection:true; activeFocusOnTab:true
    wrapMode:TextEdit.Wrap; textFormat:TextEdit.PlainText
    selectionColor:root.accent; selectedTextColor:Color.popups.background
    // TextEdit owns a read-only implicitHeight derived from its content.
    // Assigning it makes the entire Investigation type fail to load in Quickshell.
    Accessible.name:"Selectable diagnostic metadata"
  }
  component InfoCard: BorderSurface {
    id:surface
    default property alias content:body.data
    property bool critical:false
    implicitHeight:body.implicitHeight+Style.space(24)
    color:Util.alpha(surface.critical?root.urgent:root.fg,surface.critical?0.075:0.035)
    borderSpec:Border.flat(Util.alpha(surface.critical?root.urgent:root.fg,surface.critical?0.4:0.12),1)
    radius:Style.cornerRadius
    Column { id:body; x:Style.space(12); y:Style.space(12); width:surface.width-Style.space(24); spacing:Style.space(7) }
  }
}
