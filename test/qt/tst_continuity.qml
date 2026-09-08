import QtQuick
import QtTest
import qs.Commons
import "../../qml" as Deck
TestCase {
  visible:true
  id:suite
  name:"InvestigationContinuity"
  when:windowShown
  width:1270; height:764
  property int seq:0
  QtObject {
    id:fakeService
    property string workspace:"cockpit"
    property string investigationTab:"triage"
    property bool daemonRunning:true
    property bool panelOpen:true
    property bool historicalMode:false
    property var jobs:({})
    property var operatorBaseline:null
    property string lastSession:"test-session"
    property string lastError:""
    property string lastAction:""
    property string notificationError:""
    property bool budgetRequestPending:false
    property var snapshot:({})
    function setPanelOpen(v) { panelOpen=v }
    function returnLive() { historicalMode=false }
    function refresh() {}
    property var canceledIds:[]
    function diagnosticWindow(kind,n,p) { return kind+"-"+(++suite.seq) }
    function cancelJob(id) { canceledIds=canceledIds.concat([id]); return true }
    function inspectProcess(n,p) { return "process-"+(++suite.seq) }
    function recorderFrame(id) { return "frame-"+(++suite.seq) }
    function compareFrames(a,b) { return "diff-"+(++suite.seq) }
  }
  Component { id:factory; Deck.Panel { service:fakeService } }
  function all(item) { var out=[item]; for(var i=0;i<item.children.length;i++) out=out.concat(all(item.children[i])); return out }
  function investigation(p) { return all(p).filter(function(x){return typeof x.selectRecorderRange==="function"})[0] }
  function sample(at,title) { return {at_ms:at,session_id:"test-session",nodes:[{name:"fixture@host",attached:true,creation:1,restart_churn:[],expected_peers:[]}],host:{},budget_trial:null,summary:{runtime_count:1},incidents:[{id:"one",title:title,summary:"Measured fixture",status:"active",severity:"warning",evidence_class:"observed",evidence:[],actions:[]}],flight_recorder:{newest_frame_id:"frame-2",oldest_frame_id:"frame-1",activity:[{id:"event-1",frame_id:"frame-1",node:"fixture@host",kind:"registered_replaced",domain:"process",summary:"Registered name changed",evidence_class:"observed",at_ms:100}],timeline:[{frame_id:"frame-1",at_ms:100},{frame_id:"frame-2",at_ms:200}]}} }
  function init() { fakeService.operatorBaseline=null; fakeService.snapshot=sample(200,"old finding"); fakeService.jobs=({}); fakeService.historicalMode=false; fakeService.panelOpen=true }
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
  function test_budget_confirmation_resets_on_vm_replacement() {
    var p=createTemporaryObject(factory,suite,{width:1270,height:764})
    p.openInvestigation("budget","fixture@host",""); wait(30)
    var inv=investigation(p); inv.budgetConfirmed=true
    var next=sample(201,"same finding"); next.nodes[0].creation=2
    fakeService.snapshot=next; wait(20); compare(inv.budgetConfirmed,false)
  }
  function test_process_pivot_has_exact_back_navigation() {
    var p=createTemporaryObject(factory,suite,{width:1270,height:764})
    p.openInvestigation("process","fixture@host","<0.1.0>"); wait(30)
    var inv=investigation(p), original=inv.processRequest
    inv.activate("process","fixture@host","<0.2.0>")
    verify(typeof inv.back === "function"); inv.back()
    compare(inv.targetPid,"<0.1.0>"); compare(inv.processRequest,original)
  }
  function test_operator_baseline_and_activity_pivot() {
    var p=createTemporaryObject(factory,suite,{width:1270,height:764})
    p.openInvestigation("triage","fixture@host",""); wait(30)
    var capture=all(p).filter(function(x){return x.text==="Capture baseline" && x.clicked})[0]
    verify(capture); capture.clicked(); compare(fakeService.operatorBaseline.frame_id,"frame-2")
    var eventButton=all(p).filter(function(x){return x.text==="View captured frame" && x.clicked})[0]
    verify(eventButton); eventButton.clicked(); wait(20)
    var inv=investigation(p); compare(inv.tab,"recorder"); compare(fakeService.historicalMode,true); verify(inv.frameRequest!=="")
    inv.returnLive(); inv.tab="triage"; wait(20)
    var clear=all(p).filter(function(x){return x.text==="Clear baseline" && x.clicked})[0]
    verify(clear); clear.clicked(); compare(fakeService.operatorBaseline,null)
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
  function test_interval_workflow_keeps_exact_target_and_rejects_late_results() {
    failOnWarning(/TypeError|ReferenceError/)
    fakeService.snapshot=sample(Date.now(),"live");fakeService.canceledIds=[]
    var p=createTemporaryObject(factory,suite,{width:1270,height:764})
    p.openInvestigation("process","fixture@host","");wait(30)
    var inv=investigation(p)
    var start=all(p).filter(function(x){return x.text==="Measure process activity · 5s" && x.clicked})[0]
    verify(start,"Process activity start exists");verify(start.enabled);start.clicked();wait(20)
    var id=inv.processWindowRequest;verify(id!=="")
    fakeService.jobs=({[id]:{request_id:id,kind:"process_window",node:"fixture@host",status:"started"}});wait(20)
    var cancel=all(p).filter(function(x){return x.text==="Cancel" && x.visible && x.clicked})[0]
    verify(cancel);cancel.clicked();compare(fakeService.canceledIds[0],id)
    fakeService.jobs=({[id]:{request_id:id,kind:"process_window",node:"fixture@host",status:"complete",result:{kind:"process_window",node:"fixture@host",creation:1,at_ms:Date.now(),rows:[{key:"one",pid:"<0.1.0>",status:"matched",name:"fixture",reductions_per_second:100}]}}});wait(20)
    var inspect=all(p).filter(function(x){return x.text==="Inspect PID" && x.clicked})[0];verify(inspect);verify(inspect.enabled)
    inspect.clicked();wait(20);compare(inv.targetPid,"<0.1.0>");verify(inv.currentScroll().contentY>0,"survey pivot reveals the inspector")
    inv.targetNode="replacement@host"
    fakeService.jobs=({[id]:{request_id:id,kind:"process_window",node:"fixture@host",status:"complete",result:{node:"fixture@host",rows:[]}}});wait(20)
    compare(inv.processWindowJob,null)
    inv.targetNode="fixture@host";inv.targetPid="<0.1.0>";inv.startDiagnostic("sample_process");var old=inv.stackRequest;verify(old!=="")
    inv.targetPid="<0.99.0>";compare(inv.stackRequest,"")
    fakeService.historicalMode=true;wait(20);compare(inv.processWindowRequest,"")
  }

}
