import QtQuick
import qs.Commons
import "DeckState.js" as DeckState

EvidenceCard {
  id:root
  property var service:null
  property string nodeName:""
  readonly property var snapshot:service?service.snapshot:({})
  readonly property var capturedBaseline:service?service.operatorBaseline:null
  readonly property string status:DeckState.baselineStatus(capturedBaseline,snapshot)
  property string comparisonRequest:""
  property string comparisonTo:""
  readonly property var job:DeckState.jobFor(service?service.jobs:({}),comparisonRequest,"compare_frames")
  onCapturedBaselineChanged:{ comparisonRequest=""; comparisonTo="" }
  signal exportRequested(string fromFrame,string toFrame)
  EvidenceText { width:parent.width; text:"INTERVENTION BASELINE"; font.bold:true; color:Color.popups.text }
  EvidenceText {
    width:parent.width
    text:root.capturedBaseline?root.capturedBaseline.frame_id+" / "+DeckState.time(root.capturedBaseline.at_ms)+" / "+(root.capturedBaseline.node || "all observed nodes")+" / VM "+(root.capturedBaseline.creation===undefined?"identity unavailable":root.capturedBaseline.creation)+" / "+((root.capturedBaseline.quality || {}).status || "quality unknown")+" / "+root.status.replace(/_/g," ")
      :"Capture a retained frame before an intervention. Compare the exact frame with a later sample; changed workload may explain the difference. Baselines expire with recorder retention."
  }
  Flow {
    width:parent.width; spacing:Style.space(6)
    ActionButton {
      text:root.capturedBaseline?"Replace baseline":"Capture baseline"
      enabled:root.service && !root.service.historicalMode && !!DeckState.captureBaseline(root.snapshot,root.nodeName)
      onClicked:root.service.operatorBaseline=DeckState.captureBaseline(root.snapshot,root.nodeName)
    }
    ActionButton {
      text:"Compare with latest"; enabled:root.status==="retained" && root.service && !root.service.historicalMode
      onClicked:{root.comparisonTo=root.snapshot.flight_recorder.newest_frame_id;root.comparisonRequest=root.service.compareFrames(root.capturedBaseline.frame_id,root.comparisonTo)}
    }
    ActionButton { text:"Clear baseline"; visible:!!root.capturedBaseline; onClicked:root.service.operatorBaseline=null }
    ActionButton { text:"Export comparison"; enabled:!!root.job && root.job.status==="complete"; onClicked:root.exportRequested(root.capturedBaseline.frame_id,root.comparisonTo) }
  }
  EvidenceText {
    width:parent.width; visible:!!root.job
    text:root.job?(root.job.status==="complete"?"Exact result to "+root.comparisonTo+". It stays captured until you compare again.":root.job.status==="error"?"Comparison unavailable: "+String(root.job.error || "expired evidence").replace(/_/g," "):"Comparison "+root.job.status):""
  }
  TextEdit {
    width:parent.width; visible:!!root.job && root.job.status==="complete"
    text:visible?DeckState.diffText(root.job.result):""
    color:Color.popups.text; font.family:Style.font.family; font.pixelSize:Style.font.caption
    textFormat:TextEdit.PlainText; wrapMode:TextEdit.Wrap; readOnly:true; selectByMouse:true; selectByKeyboard:true; activeFocusOnTab:true
    Accessible.name:"Captured baseline comparison"
  }
}
