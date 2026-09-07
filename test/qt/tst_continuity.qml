import QtQuick
import QtTest
import qs.Commons
import "../../qml" as Deck
TestCase {
  id:suite
  name:"InvestigationContinuity"
  when:windowShown
  width:1270; height:764
  property int seq:0
  QtObject {
    id:fakeService
    property bool daemonRunning:true
    property bool panelOpen:true
    property bool historicalMode:false
    property var jobs:({})
    property string lastSession:"test-session"
    property string lastError:""
    property string lastAction:""
    property string notificationError:""
    property bool budgetRequestPending:false
    property var snapshot:({})
    function setPanelOpen(v) { panelOpen=v }
    function returnLive() { historicalMode=false }
    function refresh() {}
    function inspectProcess(n,p) { return "process-"+(++suite.seq) }
    function recorderFrame(id) { return "frame-"+(++suite.seq) }
    function compareFrames(a,b) { return "diff-"+(++suite.seq) }
  }
  Component { id:factory; Deck.Panel { service:fakeService } }
  function all(item) { var out=[item]; for(var i=0;i<item.children.length;i++) out=out.concat(all(item.children[i])); return out }
  function investigation(p) { return all(p).filter(function(x){return typeof x.selectRecorderRange==="function"})[0] }
  function sample(at,title) { return {at_ms:at,session_id:"test-session",nodes:[{name:"fixture@host",attached:true,creation:1,restart_churn:[],expected_peers:[]}],host:{},budget_trial:null,summary:{runtime_count:1},incidents:[{id:"one",title:title,summary:"Measured fixture",status:"active",severity:"warning",evidence_class:"observed",evidence:[],actions:[]}],flight_recorder:{timeline:[{frame_id:"frame-1",at_ms:100},{frame_id:"frame-2",at_ms:200}]}} }
  function init() { fakeService.snapshot=sample(200,"old finding"); fakeService.jobs=({}); fakeService.historicalMode=false; fakeService.panelOpen=true }
  function test_exact_missing_node() {
    failOnWarning(/TypeError/)
    var p=createTemporaryObject(factory,suite,{width:1270,height:764,selectedNode:"ended@host"})
    verify(p); wait(20); compare(p.selected(),null)
    verify(all(p).some(function(x){return x.visible && typeof x.text === "string" && x.text.indexOf("Selected node is no longer observed: ended@host")>=0}))
  }
  function test_workspace_keeps_context() {
    var p=createTemporaryObject(factory,suite,{width:1270,height:764})
    p.openInvestigation("recorder","fixture@host",""); wait(30)
    var inv=investigation(p); verify(inv); inv.query="operator filter"; inv.selectRecorderRange("frame-1","frame-2")
    p.liveCockpit(); wait(20); p.openInvestigation(); wait(30)
    var again=investigation(p); verify(again); compare(again,inv)
    compare(again.tab,"recorder"); compare(again.query,"operator filter"); compare(again.fromFrame,"frame-1")
    compare(again.recorderPaused,true); compare(fakeService.historicalMode,true)
  }
  function test_freeze_before_reply_and_reject_old_target() {
    var p=createTemporaryObject(factory,suite,{width:1270,height:764})
    p.openInvestigation("triage","fixture@host",""); wait(30)
    var inv=investigation(p); inv.viewRecorderFrame("frame-1"); var old=inv.frameRequest
    compare(fakeService.historicalMode,true)
    fakeService.snapshot=sample(300,"future finding"); wait(10)
    compare(inv.viewSnapshot.incidents[0].title,"old finding")
    inv.returnLive(); fakeService.jobs=({[old]:{request_id:old,kind:"recorder_frame",status:"complete",result:{frame_id:"frame-1",at_ms:100,incidents:[]}}}); wait(20)
    compare(fakeService.historicalMode,false); compare(inv.frameResult,null)
    inv.activate("process","fixture@host","<0.1.0>"); var prior=inv.processRequest
    inv.targetPid="<0.2.0>"; compare(inv.processRequest,"")
    fakeService.jobs=({[prior]:{request_id:prior,kind:"inspect_process",node:"fixture@host",status:"complete",result:{pid:"<0.1.0>"}}}); wait(10)
    compare(inv.processResult,null)
  }
  function test_modified_navigation_stays_with_control() {
    var p=createTemporaryObject(factory,suite,{width:1270,height:764})
    p.openInvestigation("triage","fixture@host",""); wait(30)
    var inv=investigation(p), catcher=all(p).filter(function(x){return x.blocked!==undefined})[0]
    catcher.forceActiveFocus(); keyClick(Qt.Key_Right,Qt.ControlModifier); compare(inv.tab,"triage")
    keyClick(Qt.Key_L); compare(inv.tab,"recorder")
    keyClick(Qt.Key_G); compare(fakeService.historicalMode,false)
  }
  function test_editor_modified_keys() {
    var p=createTemporaryObject(factory,suite,{width:1270,height:764})
    p.openInvestigation("triage","fixture@host",""); wait(30)
    var field=all(p).filter(function(x){return x.placeholderText==="Filter incidents by node or symptom"})[0]
    verify(field); field.forceActiveFocus(); "hello".split("").forEach(function(c){ keyClick(c) }); compare(field.text,"hello")
    keyClick(Qt.Key_A,Qt.ControlModifier); keyClick(Qt.Key_C,Qt.ControlModifier)
    compare(p.workspace,"investigate"); compare(field.selectedText,"hello")
    keyClick(Qt.Key_R,Qt.AltModifier); compare(p.workspace,"investigate")
  }
}
