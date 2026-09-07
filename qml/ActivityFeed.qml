import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import "DeckState.js" as DeckState

Column {
  id:root
  property var rows:[]
  property string nodeFilter:""
  property string domainFilter:"all"
  property string kindFilter:"all"
  property string query:""
  property int omitted:0
  readonly property var shown:DeckState.activityRows(rows,nodeFilter,domainFilter,kindFilter,query)
  spacing:Style.space(8)
  signal frameRequested(string frameId,string node)
  EvidenceText { width:parent.width; text:"ACTIVITY / "+root.shown.length+" shown of "+root.rows.length+" retained"+(root.omitted?" / "+root.omitted+" older or excess changes omitted":""); color:Color.popups.text; font.bold:true }
  Flow {
    width:parent.width; spacing:Style.space(6)
    Controls.ComboBox { model:["All nodes"].concat(root.rows.map(function(r){return r.node || "host"}).filter(function(n,i,a){return a.indexOf(n)===i})); currentIndex:root.nodeFilter?model.indexOf(root.nodeFilter):0; onActivated:function(i){root.nodeFilter=i?model[i]:""}; Accessible.name:"Activity node filter" }
    Controls.ComboBox { model:["All domains","node","process","runtime"]; currentIndex:root.domainFilter==="all"?0:model.indexOf(root.domainFilter); onActivated:function(i){root.domainFilter=i?model[i]:"all"}; Accessible.name:"Activity domain filter" }
    Controls.ComboBox { model:["All changes","Connections: opened + closed","Restarts / name replacement"]; currentIndex:["all","connections","restarts"].indexOf(root.kindFilter); onActivated:function(i){root.kindFilter=["all","connections","restarts"][i]}; Accessible.name:"Activity kind filter" }
  }
  Controls.TextField { width:parent.width; text:root.query; onTextEdited:root.query=text; placeholderText:"Filter retained activity"; Accessible.name:placeholderText }
  EvidenceText { width:parent.width; visible:!root.shown.length; text:"No retained activity matches these filters. Capped scans cannot establish process exits; disconnected distribution does not prove a VM ended." }
  Repeater {
    model:KeyedRows { rows:root.shown }
    EvidenceCard {
      id:card
      required property string rowJson
      property var entry:JSON.parse(rowJson)
      width:root.width
      EvidenceText { width:parent.width; text:DeckState.time(card.entry.at_ms)+" / "+card.entry.kind.replace(/_/g," ")+" / "+(card.entry.node || "host"); color:Color.popups.text; font.bold:true }
      EvidenceText { width:parent.width; text:card.entry.summary+(card.entry.name?"\nName: "+card.entry.name:"")+(card.entry.subject?" / "+card.entry.subject:"") }
      EvidenceText { width:parent.width; text:"Observed / captured "+DeckState.time(card.entry.captured_at_ms)+" / "+card.entry.frame_id+((card.entry.changed_fields || []).length?" / fields: "+card.entry.changed_fields.join(", "):"") }
      ActionButton { text:"View captured frame"; onClicked:root.frameRequested(card.entry.frame_id,card.entry.node || "") }
    }
  }
}
