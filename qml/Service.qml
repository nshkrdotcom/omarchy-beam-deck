import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var snapshot: ({ type: "snapshot", protocol: 1, onboarding: { state: "starting" }, summary: { runtime_count: 0, attached_count: 0, warning_count: 0, critical_count: 0 }, host: { logical_cpus: 0, runtimes: [], memory: {} }, nodes: [], alerts: [], budget: [], history: [], events: [] })
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
    return send({ cmd: "panel", open: panelOpen })
  }
  function setSchedulers(node, value) { return send({ cmd: "set_schedulers", node: node, value: Number(value) }) }
  function setDirtySchedulers(node, value) { return send({ cmd: "set_dirty_schedulers", node: node, value: Number(value) }) }
  function restore(node) { return send({ cmd: "restore", node: node }) }
  function deepEvents(node, enabled) { return send({ cmd: "deep_events", node: node, enabled: !!enabled }) }
  function collectGc(node, pid) { return send({ cmd: "gc", node: node, pid: pid }) }

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
        snapshot = data
        lastError = ""
      } else if (data.type === "action") {
        lastAction = String(data.action || "") + ": " + String(data.result || "")
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

  IpcHandler {
    target: "nshkr.beam-deck"
    function status(): string { return JSON.stringify(root.snapshot) }
    function refresh(): string { root.refresh(); return "ok" }
    function open(): string { if (root.shell) root.shell.summon("nshkr.beam-deck", "{}"); return "ok" }
    function ping(): string { return "ok" }
  }
}
