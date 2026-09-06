import QtQuick
import Quickshell
import Quickshell.Io
import "DeckState.js" as DeckState

Item {
  id: root
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var snapshot: DeckState.emptySnapshot()
  property var jobs: ({})
  property bool historicalMode: false
  property int sequence: 0
  property string lastSession: ""
  property string notificationError: ""
  property var notificationQueue: []
  property bool notificationBusy: false
  property string lastError: ""
  property string lastAction: ""
  property bool daemonRunning: daemon.running
  property bool panelOpen: false
  property int restartDelayMs: 1000
  readonly property string pluginRoot: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""

  function send(command) {
    if (!daemon.running) return false
    try {
      daemon.write(JSON.stringify(command) + "\n")
      return true
    } catch (e) {
      lastError = "Could not send command: " + e
      return false
    }
  }

  function refresh() { return send({ cmd: "refresh" }) }
  function setPanelOpen(open) {
    panelOpen = !!open
    if (!open) { historicalMode = false; jobs = DeckState.cancelInteractive(jobs, Date.now()) }
    return send({ cmd: "panel", open: panelOpen })
  }
  function setSchedulers(node, value) { if (!mayMutate(node)) return false; return send({ cmd: "set_schedulers", node: node, value: Number(value) }) }
  function setDirtySchedulers(node, value) { if (!mayMutate(node)) return false; return send({ cmd: "set_dirty_schedulers", node: node, value: Number(value) }) }
  function restore(node) { if (!mayMutate(node)) return false; return send({ cmd: "restore", node: node }) }
  function deepEvents(node, enabled) { if (enabled && !mayMutate(node)) return false; return send({ cmd: "deep_events", node: node, enabled: !!enabled }) }
  function collectGc(node, pid, creation) {
    if (!mayMutate(node) || !Number.isInteger(creation)) return false
    return send({cmd:"gc",node:node,pid:pid,expected_creation:creation})
  }


  function mayMutate(node) {
    var allowed = panelOpen && DeckState.canMutate(snapshot, historicalMode, daemonRunning, Date.now(), node)
    if (!allowed) lastAction = "Return to a fresh live view before changing a runtime."
    return allowed
  }
  function request(kind, args) {
    var id = "ui-" + Date.now() + "-" + (++sequence)
    var command = Object.assign({}, args || {}, { cmd: kind, request_id: id })
    jobs = DeckState.acceptJob(jobs, {request_id:id, kind:kind, node:command.node, status:"queued"}, Date.now())
    if (!send(command)) jobs = DeckState.acceptJob(jobs, {request_id:id, kind:kind, status:"error", error:"helper_unavailable"}, Date.now())
    return id
  }
  function inspectProcess(node, pid) { return request("inspect_process", {node:node, pid:pid}) }
  function inspectEts(node, sort) { return request("inspect_ets", {node:node, sort:sort || "memory"}) }
  function recorderFrame(id) { return request("recorder_frame", {frame_id:id}) }
  function compareFrames(from, to) { return request("compare_frames", {from_frame_id:from, to_frame_id:to}) }
  function exportBundle(from, to) { return request("export_bundle", {from_frame_id:from || null, to_frame_id:to || null}) }
  function beginBudget(rows) { return mayMutate() ? request("budget_trial_begin", {rows:rows}) : "" }
  function keepBudget(id) { return mayMutate() && send({cmd:"budget_trial_keep",trial_id:id}) }
  function revertBudget(id) { return send({cmd:"budget_trial_revert",trial_id:id}) }
  function pinNode(node) { return send({cmd:"watchlist_add",entry:{kind:"node",node:node,label:String(node).slice(0,80)}}) }
  function pinProcess(node, name) { return send({cmd:"watchlist_add",entry:{kind:"registered_process",node:node,name:name,label:String(name).slice(0,80)}}) }
  function removePin(id) { return send({cmd:"watchlist_remove",id:id}) }
  function returnLive() { historicalMode = false }

  function nextNotification() {
    if (notificationBusy || !notificationQueue.length) return
    notificationBusy = true
    notifier.command = notificationQueue[0]
    notifier.running = true
    notificationDeadline.restart()
  }
  function finishNotification() {
    if (!notificationBusy) return
    notificationDeadline.stop()
    notificationBusy = false
    notificationQueue = notificationQueue.slice(1)
    Qt.callLater(nextNotification)
  }

  function openTerminal(command) {
    if (!command) return
    Quickshell.execDetached(["xdg-terminal-exec", "--app-id=TUI.float", "-e", "bash", "-lc", command + "; printf '\\nPress Enter to close...'; read -r"])
  }
  function installBeam() { openTerminal(shellQuote(pluginRoot + "/bin/beam-deck-onboard")) }
  function remsh(node) { openTerminal(shellQuote(pluginRoot + "/bin/beam-deck-remsh") + " " + shellQuote(node)) }
  function launchProfile(normalSchedulers, dirtyCpuSchedulers) { openTerminal(shellQuote(pluginRoot + "/bin/beam-deck-profile") + " --schedulers " + Number(normalSchedulers) + " --dirty-cpu " + Number(dirtyCpuSchedulers)) }
  function shellQuote(value) { return "'" + String(value || "").split("'").join("'\\''") + "'" }

  function handleLine(line) {
    if (!line || String(line).trim() === "") return
    try {
      var data = JSON.parse(String(line))
      if (data.type === "snapshot") {
        if (lastSession && data.session_id && lastSession !== data.session_id) {
          jobs = ({})
          historicalMode = false
          lastAction = "Helper restarted; historical selections and pending results were cleared."
        }
        if (data.session_id) lastSession = String(data.session_id)
        snapshot = Object.assign(DeckState.emptySnapshot(), data)
        lastError = ""
      } else if (data.type === "action") {
        lastAction = String(data.action || "") + ": " + (typeof data.result === "object" ? JSON.stringify(data.result) : String(data.result || ""))
      } else if (data.type === "job") {
        jobs = DeckState.acceptJob(jobs, data, Date.now())
        if (["set_schedulers", "set_dirty_schedulers", "restore", "gc", "budget_trial_keep", "budget_trial_revert"].indexOf(data.kind) >= 0 && DeckState.terminal(data.status))
          lastAction = data.kind + ": " + (data.result && data.result.restored === false ? "RESTORE NOT CONFIRMED - " + JSON.stringify(data.result.failures || []) : data.status) + (data.error ? " - " + data.error : "")
      } else if (data.type === "budget_trial") {
        snapshot = Object.assign({}, snapshot, {budget_trial:data.trial})
      } else if (data.type === "notification") {
        if (notificationQueue.length < 8) {
          notificationQueue = notificationQueue.concat([DeckState.notificationArgs(data)])
          nextNotification()
        }
      } else if (data.type === "error") {
        lastError = String(data.error || "error") + (data.reason ? ": " + data.reason : "")
      } else if (data.type === "event") {
        var next = Object.assign({}, snapshot)
        var ev = (snapshot.events || []).slice()
        ev.unshift(data.event)
        next.events = ev.slice(0, 30)
        snapshot = next
      }
    } catch (e) {
      lastError = "Invalid daemon output: " + e
    }
  }

  Process {
    id: daemon
    stdinEnabled: true
    command: root.pluginRoot ? [root.pluginRoot + "/bin/beam-deckd"] : []
    running: root.pluginRoot !== ""
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    stderr: SplitParser { onRead: function(line) { if (String(line).trim() !== "") root.lastError = String(line).trim() } }
    onStarted: {
      root.restartDelayMs = 1000
      if (root.panelOpen) Qt.callLater(function() { root.setPanelOpen(true) })
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "beam-deckd exited with status " + exitCode
      jobs = DeckState.cancelInteractive(jobs, Date.now())
      historicalMode = false
      daemon.running = false
      restartTimer.interval = root.restartDelayMs
      root.restartDelayMs = Math.min(root.restartDelayMs * 2, 30000)
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    repeat: false
    onTriggered: if (root.pluginRoot !== "") daemon.running = true
  }

  Timer { interval: 10000; running: true; repeat: true; onTriggered: root.jobs = DeckState.pruneJobs(root.jobs, Date.now()) }
  Process {
    id: notifier
    onExited: function(code) {
      if (code !== 0) root.notificationError = "Desktop notification unavailable; incident remains in BEAM Deck."
      root.finishNotification()
    }
    stderr: SplitParser { onRead: function(line) { root.notificationError = "Desktop notification helper reported an error." } }
  }
  Timer {
    id: notificationDeadline
    interval: 3000
    onTriggered: {
      root.notificationError = "Desktop notification could not be confirmed."
      // Consume the queue only after process exit, never before a previous child exits.
      if (notifier.running) notifier.running = false
      else root.finishNotification()
    }
  }

  IpcHandler {
    target: "nshkr.beam-deck"
    function status(): string { return JSON.stringify(root.snapshot) }
    function refresh(): string { root.refresh(); return "ok" }
    function open(): string { if (root.shell) root.shell.summon("nshkr.beam-deck", "{}"); return "ok" }
    function ping(): string { return "ok" }
  }
}
