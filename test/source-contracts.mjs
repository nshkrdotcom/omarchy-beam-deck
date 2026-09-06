// Structural repository contracts; these do not replace compilation or runtime tests.
import assert from "node:assert/strict";
import fs from "node:fs";
const read = p => fs.readFileSync(p, "utf8");
const manifest = JSON.parse(read("manifest.json"));
assert.equal(manifest.version, "1.1.0");
assert.deepEqual([...manifest.kinds].sort(), ["bar-widget", "service"]);
assert.equal(manifest.entryPoints.panel, undefined);
const barWidget = read("qml/BarWidget.qml");
const panelSource = read("qml/Panel.qml");
assert.match(barWidget, /source:\s*Qt\.resolvedUrl\("Panel\.qml"\)/);
assert.match(barWidget, /panelLoader\.item\.anchorItem\s*=\s*button/);
assert.match(barWidget, /panelLoader\.item\.hostWidget\s*=\s*root/);
assert.match(barWidget, /panelLoader\.item\.service\s*=\s*root\.beamService/);
assert.match(barWidget, /function\s+closeForPopoutSwitch\s*\(/);
assert.doesNotMatch(barWidget, /omarchy-shell shell toggle nshkr\.beam-deck/);
assert.match(panelSource, /^Panel\s*\{/m);
assert.match(panelSource, /\bKeyboardPanel\s*\{/);
assert.match(panelSource, /\bPanelKeyCatcher\s*\{/);
assert.match(panelSource, /Keys\.priority:\s*Keys\.AfterItem/);
assert.match(panelSource, /contentWidth:\s*panel\.fittedContentWidth\(Style\.space\(1280\)\)/);
assert.match(panelSource, /contentHeight:\s*panel\.cappedContentHeight\(Style\.space\(840\)\)/);
assert.doesNotMatch(panelSource, /\bPanelWindow\s*\{/);
assert.doesNotMatch(panelSource, /\bWlrLayershell\b/);
assert.doesNotMatch(panelSource, /Style\.space\(48\)/);
assert.doesNotMatch(panelSource, /Math\.min\(panel\.(width|height)\s*-\s*Style\.space/);
assert.match(read("daemon/mix.exs"), /version: "1\.1\.0"/);
assert.match(read("daemon/lib/beam_deck/diagnostics/bundle.ex"), /version: "1\.1\.0"/);
const source = read("daemon/lib/beam_deck/config.ex").split("@defaults ")[1].split("\n\n  def defaults")[0];
const defaults = JSON.parse(source.replaceAll("%{", "{").replaceAll("=>", ":").replace(/(?<=\d)_(?=\d)/g, ""));
assert.deepEqual(JSON.parse(read("config/config.example.json")), defaults);
const daemon = read("daemon/lib/beam_deck/daemon.ex");
const ui = read("qml/Investigation.qml") + read("qml/Service.qml") + read("qml/TrialBar.qml");
for (const cmd of ["inspect_process", "inspect_ets", "recorder_frame", "compare_frames", "export_bundle", "watchlist_add", "watchlist_remove", "budget_trial_begin", "budget_trial_keep", "budget_trial_revert"]) {
  assert.ok(daemon.includes('"' + cmd + '"'), `daemon missing ${cmd}`);
  assert.ok(ui.includes('"' + cmd + '"'), `UI missing ${cmd}`);
}
const processSource = read("daemon/lib/beam_deck/diagnostics/process.ex");
assert.match(processSource, /\{:dictionary, :"\$ancestors"\}/);
assert.doesNotMatch(processSource, /:sys,\s*:(get_state|get_status)|\[pid,\s*:dictionary\]|:messages\b/);
const etsSource = read("daemon/lib/beam_deck/diagnostics/ets.ex");
assert.doesNotMatch(etsSource, /:ets,\s*:(tab2list|select|match|lookup|match_object)\b/);
assert.doesNotMatch(read("qml/DeckState.js"), /\beval\s*\(/);
// Qt Quick TextEdit computes implicitHeight itself and exposes it read-only.
// A v1.1 regression assigned implicitHeight in CopyText, making Investigation.qml
// unavailable and therefore preventing Panel.qml from loading at all.
const investigation = read("qml/Investigation.qml");
const copyText = investigation.match(/component CopyText: TextEdit \{([\s\S]*?)\n  \}/);
assert.ok(copyText, "CopyText component missing");
assert.doesNotMatch(copyText[1], /\bimplicitHeight\s*:/, "TextEdit implicitHeight is read-only in Quickshell");
for (const path of ["README.md", "SECURITY.md", "HANDOFF.md", "docs/ARCHITECTURE.md", "docs/PROTOCOL.md", "docs/CONFIGURATION.md", "docs/VALIDATION.md", "docs/IMPLEMENTATION-1.1.md"]) {
  assert.ok(fs.statSync(path).size > 200, `documentation missing: ${path}`);
}
console.log("repository contracts: versions, native bar-panel surface, configuration parity, command wiring, privacy boundaries and documentation present");