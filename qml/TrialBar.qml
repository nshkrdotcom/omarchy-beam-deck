import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
  id:root
  property var service:null
  readonly property var trial:service ? service.snapshot.budget_trial || null : null
  property double nowMs:Date.now()
  readonly property int seconds:trial ? Math.max(0,Math.ceil((trial.expires_at_ms-nowMs)/1000)) : 0
  visible:!!trial
  implicitHeight:visible ? body.implicitHeight+Style.space(18) : 0
  color:Util.alpha(trial && trial.status==="rollback_failed"?Color.urgent:Color.accent,0.08)
  borderSpec:Border.flat(Util.alpha(Color.accent,0.3),1)
  radius:Style.cornerRadius
  Timer { interval:250; repeat:true; running:root.visible; onTriggered:root.nowMs=Date.now() }
  RowLayout {
    id:body
    x:Style.space(9); y:Style.space(9); width:parent.width-Style.space(18)
    Text {
      Layout.fillWidth:true
      text:root.trial ? "BUDGET  /  "+root.trial.status+(root.trial.status==="active"?"  /  "+root.seconds+"s to automatic rollback":"")+(root.trial.status==="rollback_failed"?" - restoration is NOT confirmed; retry while the same VM is reachable.":root.trial.status==="kept"?" - original-value Restore remains available.":"") : ""
      color:root.trial && root.trial.status==="rollback_failed"?Color.urgent:Color.popups.text
      font.family:Style.font.family; font.pixelSize:Style.font.caption; wrapMode:Text.Wrap; textFormat:Text.PlainText
    }
    ActionButton { text:"Keep"; visible:!!root.trial && root.trial.status==="active"; enabled:root.seconds>0 && root.service && !root.service.historicalMode; onClicked:root.service.keepBudget(root.trial.trial_id) }
    ActionButton { text:root.trial && root.trial.status==="rollback_failed"?"Retry rollback":"Revert now"; visible:!!root.trial && ["applying","active","reverting","rollback_failed"].indexOf(root.trial.status)>=0; enabled:!!root.trial && root.trial.status!=="reverting"; onClicked:root.service.revertBudget(root.trial.trial_id) }
  }
}
