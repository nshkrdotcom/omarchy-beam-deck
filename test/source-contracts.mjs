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
const serviceStatusSource = read("qml/Service.qml");
assert.ok(serviceStatusSource.includes("function ipcStatusSnapshot()"));
assert.ok(serviceStatusSource.includes("property bool budgetRequestPending: false"));
assert.ok(serviceStatusSource.includes('lastAction = "Starting budget trial… waiting for helper acknowledgement."'));
assert.ok(read("qml/Investigation.qml").includes('"Starting trial…"'));

assert.ok(serviceStatusSource.includes(
  'function status(): string { return JSON.stringify(root.ipcStatusSnapshot()) }'
));
assert.ok(!serviceStatusSource.includes(
  'function status(): string { return JSON.stringify(root.snapshot) }'
));
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
for (const path of ["README.md", "SECURITY.md", "docs/ARCHITECTURE.md", "docs/PROTOCOL.md", "docs/CONFIGURATION.md", "docs/VALIDATION.md", "docs/IMPLEMENTATION-1.1.md"]) {
  assert.ok(fs.statSync(path).size > 200, `documentation missing: ${path}`);
}
const discoveryRegression = read("daemon/lib/beam_deck/discovery.ex");
assert.match(
  discoveryRegression,
  /@helper_node_re\s+~r\/\^beam_deck_\[0-9\]\+\(\?:@\|\$\)\//
);
assert.doesNotMatch(
  discoveryRegression,
  /String\.starts_with\?\(to_string\(name\), "beam_deck_"\)/
);

const discoveryTests = read("daemon/test/discovery_test.exs");
assert.match(
  discoveryTests,
  /beam_deck_demo@host/
);
assert.match(
  discoveryTests,
  /beam_deck_api@host/
);
assert.match(
  discoveryTests,
  /beam_deck_58391@host/
);
// legitimate beam_deck application names must not be hidden as helpers

const pinnedPanel = read("qml/Panel.qml");
assert.match(pinnedPanel, /function nodePinned\(name\)/);
assert.match(pinnedPanel, /Pinned node unavailable:/);
assert.match(
  pinnedPanel,
  /It remains listed because it is in your Watchlist/
);


const beamBar = read("qml/BarWidget.qml");
assert.doesNotMatch(
  beamBar,
  /horizontalCenterOffset\s*:\s*root\.vertical\s*\?\s*0\s*:\s*4/,
  "BEAM Deck bar glyph must remain centered on its selection indicator"
);

const beamDiscovery = read("daemon/lib/beam_deck/discovery.ex");
assert.match(
  beamDiscovery,
  /@helper_node_re\s+~r\/\^beam_deck_\[0-9\]\+\(\?:@\|\$\)\//
);
assert.doesNotMatch(
  beamDiscovery,
  /String\.starts_with\?\(to_string\(name\),\s*"beam_deck_"\)/
);

const beamDiscoveryTests = read("daemon/test/discovery_test.exs");
for (const name of [
  "beam_deck_58391@host",
  "beam_deck_demo@host",
  "beam_deck_api@host"
]) {
  assert.ok(
    beamDiscoveryTests.includes(name),
    "missing helper-name regression: " + name
  );
}

const beamPanel = read("qml/Panel.qml");
assert.match(beamPanel, /function nodePinned\(name\)/);
assert.match(beamPanel, /Pinned node unavailable:/);

const keyboardPanel = read("qml/Panel.qml");
assert.match(keyboardPanel, /onMoveRequested:\s*function\(dx, dy\) \{ root\.keyboardMove\(dx, dy\) \}/);
assert.match(keyboardPanel, /onTextKey:\s*function\(text\) \{ root\.handleShortcut\(text\) \}/);
assert.match(keyboardPanel, /DeckState\.panelShortcut\(text\)/);
assert.match(keyboardPanel, /text:\s*"Shortcuts"/);
const keyboardInvestigation = read("qml/Investigation.qml");
assert.match(keyboardInvestigation, /DeckState\.investigationTabShortcut\(text\)/);
assert.match(keyboardInvestigation, /function cycleTab\(direction\)/);
assert.match(keyboardInvestigation, /function keyboardMove\(dx, dy\)/);


// recorder range navigator replaces timestamp dropdowns
const investigationSource = read("qml/Investigation.qml");
const recorderTimelineSource = read("qml/RecorderTimeline.qml");
assert.match(investigationSource, /RecorderTimeline\s*\{/);
assert.match(investigationSource, /property bool recorderPaused:\s*false/);
assert.match(investigationSource, /property var recorderFrozenTimeline:\s*\[\]/);
assert.match(investigationSource, /function selectRecorderRange\(from, to\)/);
assert.match(investigationSource, /service\.historicalMode = true/);
assert.match(investigationSource, /text:\"Last 1m\"/);
assert.match(investigationSource, /text:\"All retained\"/);
assert.match(investigationSource, /text:\"Compare A → B\"/);
assert.doesNotMatch(investigationSource, /Earlier recorder frame|Later recorder frame/);
assert.doesNotMatch(investigationSource, /function options\(\)|recorderOptions\(/);
assert.match(recorderTimelineSource, /Canvas\s*\{/);
assert.match(recorderTimelineSource, /signal rangeRequested\(string fromFrame, string toFrame\)/);
assert.match(recorderTimelineSource, /Accessible\.role:\s*Accessible\.Slider/);
assert.match(recorderTimelineSource, /ShiftModifier/);
assert.match(read("qml/DeckState.js"), /function recorderOrderedRange\(/);
assert.match(read("qml/DeckState.js"), /function recorderRangeLast\(/);


// recorder view/compare result modes are mutually exclusive
assert.match(investigationSource, /function viewRecorderFrame\(id\)\s*\{[\s\S]*?diffRequest = ""[\s\S]*?frameRequest = service\.recorderFrame\(id\)/);
assert.match(investigationSource, /function compareRecorderRange\(\)\s*\{[\s\S]*?frameRequest = ""[\s\S]*?diffRequest = service\.compareFrames\(fromFrame, toFrame\)/);
assert.match(investigationSource, /text:"View A"[\s\S]*?onClicked:root\.viewRecorderFrame\(root\.fromFrame\)/);
assert.match(investigationSource, /text:"View B"[\s\S]*?onClicked:root\.viewRecorderFrame\(root\.toFrame\)/);
assert.match(investigationSource, /text:"Compare A → B"[\s\S]*?onClicked:root\.compareRecorderRange\(\)/);

console.log("repository contracts: versions, native bar-panel surface, keyboard navigation, configuration parity, command wiring, privacy boundaries and documentation present");
