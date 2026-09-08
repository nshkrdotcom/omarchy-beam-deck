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
  property bool surfaceActive: visible
  property string targetNode: ""
  property string targetPid: ""
  property string tab: "triage"
  onTabChanged: if (service) service.investigationTab = tab
  readonly property var tabDefinitions: [{id:"triage",label:"Triage"},{id:"recorder",label:"Flight recorder"},{id:"process",label:"Process"},{id:"ets",label:"ETS lens"},{id:"pins",label:"Watchlist"},{id:"budget",label:"Budget trial"}]
  property string query: ""
  property string activityQuery: ""
  property string activityNode: ""
  property string activityDomain: "all"
  property string activityKind: "all"
  property string recorderMetric: "rss"
  property string recorderNode: ""
  property string etsQuery: ""
  property string processQuery: ""
  property string processSort: "mailbox"
  property var navigationStack: []
  readonly property var capturedNode: (viewSnapshot.nodes || []).filter(function(n){return n.name===root.targetNode})[0] || ({})
  property bool showResolved: false
  property var expandedIncidents: ({})
  property bool gcConfirmed: false
  property double nowMs: Date.now()
  Timer { interval: 1000; running: root.surfaceActive; repeat: true; onTriggered: root.nowMs = Date.now() }
  property bool budgetConfirmed: false
  property string processWindowRequest: ""
  property string etsWindowRequest: ""
  property string stackRequest: ""
  readonly property var processWindowJob: DeckState.jobFor(jobs,processWindowRequest,"process_window",targetNode)
  readonly property var etsWindowJob: DeckState.jobFor(jobs,etsWindowRequest,"ets_window",targetNode)
  readonly property var stackJob: DeckState.jobFor(jobs,stackRequest,"sample_process",targetNode)
  readonly property bool maySample: !!service && service.panelOpen && DeckState.canMutate(snapshot,service.historicalMode,service.daemonRunning,nowMs,targetNode) && Number.isInteger(capturedNode.creation)
  property string processRequest: ""
  property string etsRequest: ""
  property string frameRequest: ""
  property string diffRequest: ""
  property string exportRequest: ""
  property string fromFrame: ""
  property string toFrame: ""
  property bool recorderPaused: false
  property var recorderFrozenTimeline: []
  property var recorderFrozenSnapshot: null
  readonly property var viewSnapshot: recorderPaused ? (frameResult || recorderFrozenSnapshot || ({})) : snapshot
  property string etsSort: "memory"
  readonly property var snapshot: service ? service.snapshot : DeckState.emptySnapshot()
  readonly property var jobs: service ? service.jobs : ({})
  readonly property var nodes: snapshot.nodes || []
  readonly property var timeline: (snapshot.flight_recorder || {}).timeline || []
  readonly property var recorderDisplayTimeline: recorderPaused ? recorderFrozenTimeline : timeline
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
  readonly property string budgetSignature: JSON.stringify({rows:snapshot.budget || [],identities:(snapshot.nodes || []).map(function(n){return [n.name,n.creation,n.attached]})})
  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(fg, 0.65)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  onBudgetSignatureChanged: budgetConfirmed = false
  onViewSnapshotChanged: {
    var next = {}
    ;(viewSnapshot.incidents || []).forEach(function(i) { if (root.expandedIncidents[i.id]) next[i.id] = true })
    expandedIncidents = next
  }
  onTargetNodeChanged: { clearDiagnostics(); processRequest = ""; etsRequest = ""; targetPid = ""; gcConfirmed = false }
  onTargetPidChanged: { cancelDiagnostic(stackRequest); stackRequest=""; processRequest = ""; gcConfirmed = false }
  Component.onCompleted: if (!targetNode && nodes.length) targetNode = nodes[0].name
  Connections {
    target: root.service
    function onHistoricalModeChanged() { if(root.service.historicalMode) root.clearDiagnostics() }
    function onLastSessionChanged() { root.clearDiagnostics(); root.clearRecorderPause(); root.processRequest = ""; root.etsRequest = ""; root.navigationStack = [] }
  }

  function cancelDiagnostic(id) { if(id && service && jobs[id] && !DeckState.terminal(jobs[id].status)) service.cancelJob(id) }
  function clearDiagnostics() {
    cancelDiagnostic(processWindowRequest);cancelDiagnostic(etsWindowRequest);cancelDiagnostic(stackRequest)
    processWindowRequest="";etsWindowRequest="";stackRequest=""
  }
  function startDiagnostic(kind) {
    if(!maySample || (kind==="sample_process" && !targetPid)) return
    var id=service.diagnosticWindow(kind,targetNode,targetPid)
    if(kind==="process_window")processWindowRequest=id
    else if(kind==="ets_window")etsWindowRequest=id
    else if(kind==="sample_process")stackRequest=id
  }
  function inspectMeasuredPid(pid) {
    activate("process",targetNode,pid)
    Qt.callLater(function(){var scroll=root.currentScroll();if(scroll && scroll.revealInspection)scroll.revealInspection()})
  }
  function reportActionable(job) { return service && service.panelOpen && DeckState.canActOnProcess(snapshot,result(job),service.historicalMode,service.daemonRunning,nowMs) }

  function result(job) { return job && job.status === "complete" ? job.result : null }
  function jobText(job, idle) {
    if (!job) return idle
    if (job.status === "error") return "Unavailable: " + String(job.error || "request failed").split("_").join(" ")
    if (job.status === "canceled") return "Canceled. Request again from a live view."
    return job.status === "complete" ? "Captured result; refresh deliberately to inspect again." : "Inspecting\u2026 the cockpit remains live."
  }
  function activate(nextTab, node, pid) {
    if ((targetPid || etsRequest) && ((nextTab && nextTab!==tab) || (pid && pid!==targetPid) || (node && node!==targetNode))) {
      navigationStack = navigationStack.concat([{tab:tab,node:targetNode,pid:targetPid,processRequest:processRequest,etsRequest:etsRequest}]).slice(-8)
    }
    if (node) targetNode = node
    tab = nextTab || "triage"
    if (pid && tab === "process") {
      targetPid = pid
      gcConfirmed = false
      if (service && !service.historicalMode) processRequest = service.inspectProcess(targetNode, targetPid)
    }
  }
  function back() {
    if (!navigationStack.length) return
    var previous = navigationStack[navigationStack.length-1]
    navigationStack = navigationStack.slice(0,-1)
    targetNode=previous.node; targetPid=previous.pid; tab=previous.tab
    processRequest=previous.processRequest; etsRequest=previous.etsRequest
    gcConfirmed=false
  }
  function clearRecorderPause() {
    recorderPaused = false
    recorderFrozenTimeline = []
    recorderFrozenSnapshot = null
    fromFrame = ""
    toFrame = ""
    frameRequest = ""
    diffRequest = ""
  }
  function returnLive() {
    clearRecorderPause()
    if (service) service.returnLive()
  }
  function selectRecorderRange(from, to) {
    if (!timeline.length && !recorderPaused) return
    if (!recorderPaused) {
      recorderFrozenTimeline = timeline.slice()
      recorderFrozenSnapshot = snapshot
      recorderPaused = true
      if (service) service.historicalMode = true
    }
    var ordered = DeckState.recorderOrderedRange(recorderFrozenTimeline, from, to)
    if (!ordered.from || !ordered.to) return
    fromFrame = ordered.from
    toFrame = ordered.to
    frameRequest = ""
    diffRequest = ""
  }
  function selectAllRecorder() {
    if (!timeline.length) return
    if (!recorderPaused) recorderFrozenTimeline = timeline.slice()
    var range = DeckState.recorderRangeAll(recorderPaused ? recorderFrozenTimeline : timeline)
    selectRecorderRange(range.from, range.to)
  }
  function selectLastRecorder(spanMs) {
    if (!timeline.length) return
    if (!recorderPaused) recorderFrozenTimeline = timeline.slice()
    var range = DeckState.recorderRangeLast(recorderPaused ? recorderFrozenTimeline : timeline, spanMs)
    selectRecorderRange(range.from, range.to)
  }
  function selectedFrom() { return recorderPaused ? fromFrame : "" }
  function selectedTo() { return recorderPaused ? toFrame : "" }
  function recorderMeta(id) {
    var rows = recorderDisplayTimeline
    var index = DeckState.recorderIndexById(rows, id)
    return index >= 0 ? rows[index] : null
  }
  function recorderSelectionSpanMs() {
    return DeckState.recorderSelectionSpanMs(recorderDisplayTimeline, fromFrame, toFrame)
  }
  function recorderCapturedSpanMs() {
    return DeckState.recorderCapturedSpanMs(recorderDisplayTimeline)
  }
  function viewRecorderFrame(id) {
    if (!service || !id) return
    if (!recorderPaused) {
      recorderFrozenTimeline = timeline.slice()
      recorderFrozenSnapshot = snapshot
      recorderPaused = true
    }
    service.historicalMode = true
    diffRequest = ""
    frameRequest = service.recorderFrame(id)
  }
  function compareRecorderRange() {
    if (!service || !recorderPaused || !fromFrame || !toFrame || fromFrame === toFrame) return
    frameRequest = ""
    diffRequest = service.compareFrames(fromFrame, toFrame)
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
  function runExport(range) { if (service) exportRequest = service.exportBundle(range ? selectedFrom() : null, range ? selectedTo() : null) }
  function actionLabel(action) {
    if (action.label) return String(action.label).slice(0,60)
    var labels={view_frame:"View evidence frame", gc_process:"Review process GC", pin_process:"Pin process", apply_budget_trial:"Review budget trial", inspect_process:"Inspect process", inspect_ets:"ETS lens", remsh:"IEx remsh", pin_node:"Pin node", export_bundle:"Export", budget_trial_revert:"Retry rollback"}
    return labels[action.kind] || "Inspect"
  }
  function runAction(action) {
    if (!service) return
    switch (action.kind) {
      case "view_frame": tab="recorder"; viewRecorderFrame(action.frame_id); break;
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
        ActionButton { required property var modelData; text: modelData.label; selected: root.tab===modelData.id; onClicked: root.tab=modelData.id }
      }
    }
    RowLayout {
      Layout.fillWidth: true
      visible: ["process","ets","pins"].indexOf(root.tab)>=0
      ActionButton { text:"Inspection back"; visible:root.navigationStack.length>0; onClicked:root.back() }
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
      Label {
        Layout.fillWidth: true
        color: root.accent
        text: {
          if (root.recorderPaused && root.fromFrame && root.toFrame) {
            var a = root.recorderMeta(root.fromFrame)
            var b = root.recorderMeta(root.toFrame)
            return "HISTORICAL RANGE / ACTIONS LOCKED  "
              + (a ? DeckState.time(a.at_ms) : "A expired")
              + " → " + (b ? DeckState.time(b.at_ms) : "B expired")
          }
          return "HISTORICAL SELECTION / ACTIONS LOCKED  "
            + (root.frameResult ? DeckState.time(root.frameResult.at_ms) : "Selected frame loading or expired")
        }
      }
      ActionButton { text: "Return to live"; onClicked: root.returnLive() }
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
      ActionButton { text: "Copy ZIP path"; enabled: root.exportJob && root.exportJob.status==="complete"; onClicked: Quickshell.clipboardText=root.exportJob.result.path }
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
          ActionButton { text: "Export diagnostics"; onClicked: root.runExport(false) }
        }
        EvidenceCard {
          width:parent.width
          Heading { width:parent.width; text:"Provider and evidence quality" }
          Label { width:parent.width; text:DeckState.providerText(root.viewSnapshot,!!root.service && root.service.daemonRunning,root.recorderPaused?(root.viewSnapshot.at_ms || root.nowMs):root.nowMs) }
          Label { width:parent.width; text:{var p=root.snapshot.provider || {},j=p.jobs || {};return "Interactive work: "+String(j.active===undefined?"unknown":j.active)+" active / "+String(j.queued===undefined?"unknown":j.queued)+" queued; oldest wait "+DeckState.duration(j.oldest_queued_ms)+". Last prior success "+DeckState.time(p.last_success_at_ms)+(p.collection_error?" / acquisition failed; evidence retained":"")} }
          Label { width:parent.width; text:"Authenticated distribution is privileged. Deep Events is explicit; process/ETS inspection runs only when requested." }
        }
        BaselineCard { width:parent.width; service:root.service; nodeName:root.targetNode; onExportRequested:function(a,b){root.exportRequest=root.service.exportBundle(a,b)} }
        Label { visible:root.service && root.service.historicalMode; width:parent.width; text:"Captured findings stay frozen while live collection continues. Return to live to unlock runtime actions." }
        Label { width: parent.width; text: "Observed facts, nearby correlations and trend heuristics stay visibly distinct. Correlation does not establish a cause." }
        Controls.TextField { width: parent.width; placeholderText: "Filter incidents by node or symptom"; text: root.query; onTextEdited: root.query=text; Accessible.name: "Filter incidents" }
        Label { visible: !(root.viewSnapshot.incidents || []).some(function(i) { return i.status==="active" }); width: parent.width; text: "No active incidents in this evidence. Missing or partial collection does not establish health; inspect provider quality above." }
        Repeater {
          model: KeyedRows { rows: DeckState.filterRows((root.viewSnapshot.incidents || []).filter(function(i) { return root.showResolved || i.status!=="resolved" }), root.query); keyField: "id" }
          InfoCard {
            id: incidentCard
            required property string rowJson
            property var modelData: JSON.parse(rowJson)
            width: triageColumn.width
            critical: modelData.severity==="critical" && modelData.status==="active"
            Heading { width: parent.width; text: incidentCard.modelData.title; color: incidentCard.critical ? root.urgent : root.fg }
            Label { width: parent.width; text: String(incidentCard.modelData.severity).toUpperCase()+"  /  "+incidentCard.modelData.status+"  /  "+incidentCard.modelData.evidence_class+"  /  "+String(incidentCard.modelData.node || "host") }
            Label { width: parent.width; text: incidentCard.modelData.summary; color: root.fg }
            Repeater {
              model: (incidentCard.modelData.evidence || []).slice(0, root.expandedIncidents[incidentCard.modelData.id] ? 12 : 2)
              Label { required property var modelData; width: parent.width; text: "["+modelData.class+"] "+String(modelData.text || "Observed operational metadata")+(modelData.eta_ms ? "  ETA "+DeckState.duration(modelData.eta_ms) : "") }
            }
            ActionButton {
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
                ActionButton {
                  required property var modelData
                  text: root.actionLabel(modelData)
                  enabled: modelData.kind==="view_frame" || modelData.kind==="export_bundle" || modelData.kind==="budget_trial_revert" || (root.service && !root.service.historicalMode && incidentCard.modelData.status==="active")
                  onClicked: root.runAction(modelData)
                }
              }
            }
            Label { width: parent.width; text: "Evidence age "+DeckState.duration((root.recorderPaused?(root.viewSnapshot.at_ms || root.nowMs):root.nowMs)-incidentCard.modelData.last_seen_ms)+"  |  First "+DeckState.time(incidentCard.modelData.first_seen_ms)+"  |  Last evidence "+DeckState.time(incidentCard.modelData.last_seen_ms) }
          }
        }
        ActivityFeed {
          width:parent.width
          rows:root.viewSnapshot.activity || (root.viewSnapshot.flight_recorder || {}).activity || []
          omitted:(root.viewSnapshot.flight_recorder || {}).omitted_activity || 0
          query:root.activityQuery; nodeFilter:root.activityNode; domainFilter:root.activityDomain; kindFilter:root.activityKind
          onQueryChanged:root.activityQuery=query
          onNodeFilterChanged:root.activityNode=nodeFilter
          onDomainFilterChanged:root.activityDomain=domainFilter
          onKindFilterChanged:root.activityKind=kindFilter
          onFrameRequested:function(id,node){root.tab="recorder";if(node)root.recorderNode=node;root.viewRecorderFrame(id)}
        }
        Heading { text: "Resource outlook" }
        Label { width: parent.width; visible: !(root.viewSnapshot.forecasts || []).length; text: "No qualified trend. Forecasts need a sustained, consistent sample window and reset across VM restarts. This is not a guarantee of future health." }
        Repeater {
          model: root.viewSnapshot.forecasts || []
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
        Heading { visible: (root.viewSnapshot.crash_triage || []).length>0; text: "Local runtime exits" }
        Repeater {
          model: root.viewSnapshot.crash_triage || []
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
              ActionButton { visible: !!exitCard.modelData.slogan; text: "Copy slogan"; onClicked: Quickshell.clipboardText=exitCard.modelData.slogan }
              ActionButton { text: "Export header evidence"; onClicked: root.runExport(false) }
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
      function revealInspection() { contentY=Math.max(0,Math.min(focusedHeading.y,contentHeight-height)) }
      contentWidth: width; contentHeight: processColumn.implicitHeight; clip: true
      Controls.ScrollBar.vertical: Controls.ScrollBar {}
      Column {
        id: processColumn
        width: processScroll.width; spacing: Style.space(12)
        DiagnosticWindow {
          width:parent.width; kind:"process_window"; job:root.processWindowJob
          canStart:root.maySample; canInspect:root.reportActionable(job)
          onStartRequested:root.startDiagnostic(kind)
          onCancelRequested:root.service.cancelJob(root.processWindowRequest)
          onInspectRequested:function(pid){root.inspectMeasuredPid(pid)}
        }
        Heading { id:focusedHeading; text: "Focused process inspection" }
        Label { width: parent.width; text: "Open a process from Hot Processes or the Watchlist. Snapshot metadata has explicit limits; application state and message contents are never collected." }
        RowLayout {
          width: parent.width
          CopyText { Layout.fillWidth: true; text: root.targetPid || "No process selected" }
          ActionButton { text: "Refresh"; enabled: !!root.targetPid && root.service && !root.service.historicalMode; onClicked: root.processRequest=root.service.inspectProcess(root.targetNode,root.targetPid) }
        }
        Label { width: parent.width; color: root.processJob && root.processJob.status==="error" ? root.urgent : root.dim; text: root.jobText(root.processJob,"Select Inspect on a live process to begin.") }
        CopyText { width: parent.width; visible: !!root.processResult; text: root.processResult ? DeckState.processText(root.processResult) : "" }
        Flow {
          width: parent.width; spacing: Style.space(6)
          ActionButton { text: "Copy report"; enabled: !!root.processResult; onClicked: Quickshell.clipboardText=DeckState.processText(root.processResult) }
          ActionButton { text: "Pin registered name"; enabled: root.processResult && !!root.processResult.registered_name && root.service && !root.service.historicalMode; onClicked: root.service.pinProcess(root.targetNode,root.processResult.registered_name) }
          ActionButton { text: "IEx remsh"; enabled: root.service && !root.service.historicalMode && !!root.targetNode; onClicked: root.service.remsh(root.targetNode) }
        }
        Flow {
          width:parent.width; spacing:Style.space(6)
          Repeater {
            model:root.processResult?(root.processResult.ancestry || []).filter(function(a){return !!a.pid}):[]
            ActionButton {
              required property var modelData
              text:"Ancestor: "+String(modelData.name || modelData.pid).slice(0,48)
              tooltipText:String(modelData.name || "")+" "+String(modelData.pid || "")
              enabled:root.processActionable
              onClicked:root.activate("process",root.targetNode,modelData.pid)
            }
          }
          ActionButton { text:"Tables owned by this PID"; enabled:root.processActionable; onClicked:{root.etsQuery=root.targetPid;root.activate("ets",root.targetNode,"");root.etsRequest=root.service.inspectEts(root.targetNode,root.etsSort)} }
        }
        DiagnosticWindow {
          width:parent.width; kind:"sample_process"; job:root.stackJob
          canStart:root.maySample && !!root.targetPid
          onStartRequested:root.startDiagnostic(kind)
          onCancelRequested:root.service.cancelJob(root.stackRequest)
        }
        InfoCard {
          width: parent.width
          visible: !!root.processResult
          Heading { text: "Deliberate action: process GC" }
          Label { width: parent.width; text: "GC can pause the selected process and may not reduce its retained data. This acts on the live PID, not a historical frame." }
          Label { width: parent.width; visible: root.processResult && !root.processActionable; text: "Captured metadata is read-only. Reinspect this process from a fresh live VM before collecting garbage." }
          Controls.CheckBox { enabled: root.processActionable; width: parent.width; text: "I understand the pause risk for this process"; checked: root.gcConfirmed; onToggled: root.gcConfirmed=checked }
          ActionButton { text: "Collect this process"; enabled: root.gcConfirmed && root.processActionable; onClicked: { root.service.collectGc(root.targetNode,root.targetPid,root.processResult.creation); root.gcConfirmed=false } }
        }
        Heading { text:"Captured hot set" }
        Label { width:parent.width; text:"Captured "+DeckState.time(root.capturedNode.hot_processes_at_ms)+" / "+DeckState.duration(root.nowMs-root.capturedNode.hot_processes_at_ms)+" old / "+String((root.capturedNode.process_scan || {}).status || "unavailable")+" / "+String((root.capturedNode.process_scan || {}).scanned===undefined?"unknown":root.capturedNode.process_scan.scanned)+" scanned, up to 24 ranked rows retained. Sorting/filtering below is local; reductions are cumulative work counters." }
        Controls.TextField { width:parent.width; placeholderText:"Filter captured processes by name or PID"; text:root.processQuery; onTextEdited:root.processQuery=text; Accessible.name:placeholderText }
        Controls.ComboBox { model:["Mailbox messages","Memory bytes","Cumulative reductions"]; currentIndex:["mailbox","memory_bytes","reductions"].indexOf(root.processSort); onActivated:function(i){root.processSort=["mailbox","memory_bytes","reductions"][i]}; Accessible.name:"Captured process sort" }
        Repeater {
          model:KeyedRows { rows:DeckState.rankedProcesses(root.capturedNode.hot_processes || [],root.processQuery,root.processSort); keyField:"pid" }
          InfoCard {
            id:hotCard; required property string rowJson
            property var entry:JSON.parse(rowJson)
            width:processColumn.width
            Heading { width:parent.width; text:(hotCard.entry.name || "unregistered")+" / "+hotCard.entry.pid }
            Label { width:parent.width; text:hotCard.entry.mailbox+" messages / "+DeckState.bytes(hotCard.entry.memory_bytes)+" / "+hotCard.entry.reductions+" reductions" }
            ActionButton { text:"Inspect exact PID"; enabled:root.service && !root.service.historicalMode && root.nowMs-root.capturedNode.hot_processes_at_ms<=10000; onClicked:root.activate("process",root.targetNode,hotCard.entry.pid) }
          }
        }
        Label { width:parent.width; visible:!(root.capturedNode.hot_processes || []).length; text:"No captured hot set. Open-panel collection warms this sample of up to 24 rows; missing/capped acquisition is not a zero-work runtime." }
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
          ActionButton { text: "Inspect tables"; enabled: root.service && !!root.targetNode && !root.service.historicalMode; onClicked: root.etsRequest=root.service.inspectEts(root.targetNode,root.etsSort) }
        }
        DiagnosticWindow {
          width:parent.width; kind:"ets_window"; job:root.etsWindowJob
          canStart:root.maySample; canInspect:root.reportActionable(job)
          onStartRequested:root.startDiagnostic(kind)
          onCancelRequested:root.service.cancelJob(root.etsWindowRequest)
          onInspectRequested:function(pid){root.inspectMeasuredPid(pid)}
        }
        Controls.TextField { width:parent.width; text:root.etsQuery; onTextEdited:root.etsQuery=text; placeholderText:"Filter captured tables by name or owner"; Accessible.name:placeholderText }
        Label { width: parent.width; text: root.jobText(root.etsJob,"No tables have been enumerated. Inspection is explicit and metadata-only.") }
        Label { width: parent.width; visible: !!root.etsResult; color: root.accent; text: root.etsResult ? root.etsResult.scanned_tables+" / "+root.etsResult.total_tables+" tables sampled  |  "+(root.etsResult.partial?"PARTIAL":"complete enumeration")+"  |  sorted by "+root.etsResult.sort+"  |  target word size "+root.etsResult.wordsize+" bytes" : "" }
        Label { width: parent.width; visible: !!root.etsResult; text: "Table metadata may change during collection. Scanned memory: "+DeckState.bytes(root.etsResult ? root.etsResult.sampled_memory_bytes : null)+". ETS counts have no hard-capacity forecast." }
        Repeater {
          model: KeyedRows { rows: DeckState.filterRows(root.etsResult ? root.etsResult.top || [] : [],root.etsQuery); keyField: "id" }
          InfoCard {
            id: tableCard
            required property string rowJson
            property var modelData: JSON.parse(rowJson)
            width: etsColumn.width
            RowLayout {
              width: parent.width
              Heading { Layout.fillWidth: true; text: tableCard.modelData.name; elide:Text.ElideMiddle }
              Heading { text: DeckState.bytes(tableCard.modelData.memory_bytes) }
            }
            Label { width: parent.width; text: tableCard.modelData.size+" elements  |  "+tableCard.modelData.type+"  |  "+tableCard.modelData.protection+"  |  "+(tableCard.modelData.named_table?"named":"unnamed") }
            Label { width: parent.width; text: "Owner "+(tableCard.modelData.owner_name || "")+" "+tableCard.modelData.owner+"  |  read concurrency "+tableCard.modelData.read_concurrency+"  |  write concurrency "+tableCard.modelData.write_concurrency }
            ActionButton { text: "Inspect owner"; enabled: !!tableCard.modelData.owner && root.service && !root.service.historicalMode; onClicked: root.activate("process",root.targetNode,tableCard.modelData.owner) }
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

        RowLayout {
          width: parent.width
          Heading { text: "Flight recorder"; Layout.fillWidth: true }
          Label {
            text: root.recorderPaused ? "PAUSED" : "LIVE"
            color: root.recorderPaused ? root.fg : root.accent
            font.bold: true
          }
        }

        Label {
          width: parent.width
          text: {
            var frames = (root.snapshot.flight_recorder || {}).frame_count || 0
            var span = root.recorderCapturedSpanMs()
            if (!frames) return "Waiting for the first retained frame. The recorder is memory-resident and begins fresh with the helper."
            return frames + " retained frames · " + DeckState.duration(span) + " visible window. "
              + (root.recorderPaused
                ? "Historical selection is frozen while live collection continues in the background."
                : "The right edge follows the rolling in-memory buffer. Drag the timeline to investigate without chasing timestamps.")
          }
        }

        Flow {
          width:parent.width; spacing:Style.space(6)
          Controls.ComboBox { model:["Host RSS","VM memory composition","Run queue","Scheduler utilization","Hard-capacity occupancy"]; currentIndex:["rss","memory","run_queue","scheduler_utilization","capacity"].indexOf(root.recorderMetric); onActivated:function(i){root.recorderMetric=["rss","memory","run_queue","scheduler_utilization","capacity"][i]}; Accessible.name:"Recorder metric" }
          Controls.ComboBox {
            visible:root.recorderMetric!=="rss"
            model:(root.recorderDisplayTimeline || []).reduce(function(out,f){(f.nodes || []).forEach(function(n){if(out.indexOf(n.name)<0)out.push(n.name)});return out},[])
            currentIndex:model.indexOf(root.recorderNode || root.targetNode)
            onActivated:function(i){root.recorderNode=model[i]}
            Accessible.name:"Recorder node"
          }
        }
        Label { width:parent.width; text:((root.snapshot.flight_recorder || {}).omitted_frames || 0)+" retained frames not drawn; exact endpoints remain addressable. Up to 16 node traces per frame; missing/omitted nodes render unavailable. ▲ and ■ aggregate all symptoms/events in a sample; inspect its counts and captured activity." }
        RecorderTimeline {
          id: recorderTimeline
          metric: root.recorderMetric
          nodeName: root.recorderNode || root.targetNode
          renderActive: root.surfaceActive && visible
          width: parent.width
          timeline: root.recorderDisplayTimeline
          fromFrame: root.fromFrame
          toFrame: root.toFrame
          live: !root.recorderPaused
          fg: root.fg
          dim: root.dim
          accent: root.accent
          urgent: root.urgent
          onRangeRequested: function(from, to) { root.selectRecorderRange(from, to) }
        }

        RowLayout {
          width: parent.width
          visible: root.recorderPaused && !!root.fromFrame && !!root.toFrame
          spacing: Style.space(10)

          Label {
            Layout.fillWidth: true
            text: {
              var a = root.recorderMeta(root.fromFrame)
              return a ? "A  " + DeckState.time(a.at_ms) + "  ·  " + DeckState.bytes(a.beam_rss_bytes) : "A  expired"
            }
          }
          Label {
            text: DeckState.duration(root.recorderSelectionSpanMs()) + " selected"
            color: root.accent
            font.bold: true
          }
          Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: {
              var b = root.recorderMeta(root.toFrame)
              return b ? "B  " + DeckState.time(b.at_ms) + "  ·  " + DeckState.bytes(b.beam_rss_bytes) : "B  expired"
            }
          }
        }

        Flow {
          width: parent.width; spacing: Style.space(6)
          ActionButton { text:"Go live"; selected:!root.recorderPaused; onClicked:root.returnLive() }
          ActionButton { text:"Last 1m"; enabled:root.timeline.length>1; onClicked:root.selectLastRecorder(60000) }
          ActionButton { text:"All retained"; enabled:root.timeline.length>1; onClicked:root.selectAllRecorder() }
          ActionButton {
            text:"View A"
            enabled:root.recorderPaused && !!root.fromFrame && root.service
            onClicked:root.viewRecorderFrame(root.fromFrame)
          }
          ActionButton {
            text:"View B"
            enabled:root.recorderPaused && !!root.toFrame && root.service
            onClicked:root.viewRecorderFrame(root.toFrame)
          }
          ActionButton {
            text:"Compare A → B"
            enabled:root.recorderPaused && !!root.fromFrame && !!root.toFrame && root.fromFrame!==root.toFrame
            onClicked:root.compareRecorderRange()
          }
          ActionButton {
            text:"Export range"
            enabled:root.recorderPaused && !!root.fromFrame && !!root.toFrame
            onClicked:root.runExport(true)
          }
        }

        Label {
          width: parent.width
          color: root.dim
          text: root.recorderPaused
            ? "Drag either handle to refine the frozen range. Click-drag elsewhere to replace it. Tab to the timeline; Left/Right moves B and Shift+Left/Right moves A."
            : "Alert markers appear above the selected trace; runtime events appear below it. Drag any interval—or click a point—to enter read-only historical mode."
        }

        Label {
          width:parent.width
          text:root.jobText(root.frameJob,"Select a point or range, then View A or View B to fetch that exact retained frame. Expired frames return an error; they are never silently replaced.")
        }
        InfoCard {
          width:parent.width; visible:!!root.frameResult
          Heading { text:"FRAME / "+(root.frameResult?DeckState.time(root.frameResult.at_ms):"") }
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
        Label { width:parent.width; text:root.jobText(root.diffJob,"Select a range to compare exact resource deltas, node transitions and sampled hot-set changes between A and B.") }
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
        ActionButton { text:"Pin selected node"; enabled:!!root.targetNode && root.service && !root.service.historicalMode; onClicked:root.service.pinNode(root.targetNode) }
        Label { width:parent.width; color:root.urgent; visible:!!(root.viewSnapshot.watchlist || {}).error; text:String((root.viewSnapshot.watchlist || {}).error || "") }
        Label { width:parent.width; visible:!((root.viewSnapshot.watchlist || {}).entries || []).length; text:"No pins yet. Pin a node here or a registered name from the process inspector." }
        Repeater {
          model: KeyedRows { rows: (root.viewSnapshot.watchlist || {}).entries || []; keyField: "id" }
          InfoCard {
            id: pinCard
            required property string rowJson
            property var modelData: JSON.parse(rowJson)
            width:pinsColumn.width
            Heading { width:parent.width; text:pinCard.modelData.label || pinCard.modelData.name || pinCard.modelData.node }
            Label { width:parent.width; text:pinCard.modelData.node+"  /  "+pinCard.modelData.kind+"  /  "+pinCard.modelData.status; color:pinCard.modelData.status==="present"?root.accent:root.dim }
            Label { width:parent.width; text:"Observation "+DeckState.time(pinCard.modelData.observed_at_ms)+" / "+DeckState.duration(root.nowMs-pinCard.modelData.observed_at_ms)+" old"+(pinCard.modelData.stale?" / STALE retained values; current lookup unavailable":"") }
            Label { width:parent.width; visible:!!pinCard.modelData.pid; text:String(pinCard.modelData.pid || "")+"  |  Mailbox "+String(pinCard.modelData.mailbox || 0)+"  |  "+DeckState.bytes(pinCard.modelData.memory_bytes) }
            Flow {
              width:parent.width; spacing:Style.space(6)
              ActionButton { text:"Inspect"; visible:pinCard.modelData.kind==="registered_process"; enabled:pinCard.modelData.status==="present" && root.service && !root.service.historicalMode; onClicked:root.activate("process",pinCard.modelData.node,pinCard.modelData.pid) }
              ActionButton { text:"Remove pin"; onClicked:root.service.removePin(pinCard.modelData.id) }
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
        ActionButton {
          text:root.service && root.service.budgetRequestPending ? "Starting trial…" : "Begin 30-second trial"
          enabled:root.budgetConfirmed && root.service && !root.service.budgetRequestPending && !root.service.historicalMode && (root.snapshot.budget || []).some(function(r) { return r.current!==r.suggested }) && (!root.snapshot.budget_trial || ["kept","reverted"].indexOf(root.snapshot.budget_trial.status)>=0)
          onClicked:{ root.service.beginBudget(root.snapshot.budget); root.budgetConfirmed=false }
        }
        Label {
          width:parent.width
          visible:root.service && root.service.budgetRequestPending
          color:root.accent
          text:"Starting budget trial — waiting for helper acknowledgement."
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
