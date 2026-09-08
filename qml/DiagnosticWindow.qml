import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui
import "DeckState.js" as DeckState

BorderSurface {
  id: root
  property string kind: "process_window"
  property var job: null
  property bool canStart: false
  property bool canInspect: false
  property string query: ""
  property string sort: kind==="process_window"?"reductions_per_second":"memory_delta_bytes"
  property string expandedStack: ""
  property int page: 0
  readonly property var rankedRows: DeckState.intervalRows(report,query,sort)
  readonly property var pageRows: rankedRows.slice(page*5,page*5+5)
  onQueryChanged:page=0
  onSortChanged:page=0
  onReportChanged:{page=0;expandedStack=""}
  readonly property bool pending: !!job && !DeckState.terminal(job.status)
  readonly property var report: job && job.status==="complete" ? job.result : null
  readonly property string title: kind==="process_window"?"Process activity":kind==="ets_window"?"ETS growth":"Stack samples"
  signal startRequested()
  signal cancelRequested()
  signal inspectRequested(string pid)
  implicitHeight: body.implicitHeight + Style.space(24)
  color: Util.alpha(Color.popups.text,0.035)
  borderSpec: Border.flat(Util.alpha(Color.popups.text,0.12),1)
  radius: Style.cornerRadius

  Column {
    id: body
    x:Style.space(12); y:Style.space(12); width:root.width-Style.space(24); spacing:Style.space(7)
    Label { width:parent.width; font.bold:true; text:root.title }
    Label {
      width:parent.width
      text:root.kind==="process_window"?"Measure work and growth over five seconds. Two admitted process scans; reductions/s measures work, not CPU percent."
        :root.kind==="ets_window"?"Compare table memory and element counts over five seconds. Match real table identities, then inspect their owners. No table contents."
        :"Observe this exact PID up to 20 times. Stack frequency includes waiting; it is not CPU time, call count or allocation attribution. No tracing or GC."
    }
    Flow {
      width:parent.width; spacing:Style.space(6)
      ActionButton {
        text:root.kind==="process_window"?"Measure process activity · 5s":root.kind==="ets_window"?"Measure ETS growth · 5s":"Sample this PID · 5s"
        enabled:root.canStart && !root.pending
        onClicked:root.startRequested()
      }
      ActionButton { text:"Cancel"; visible:root.pending; onClicked:root.cancelRequested() }
      ActionButton { text:"Copy measurements"; enabled:!!root.report; onClicked:Quickshell.clipboardText=DeckState.intervalText(root.report) }
    }
    Label {
      width:parent.width
      text:root.pending?"Sampling request "+root.job.status+". You can continue inspecting or cancel this request."
        :!root.job?(!root.canStart?"Requires a fresh live node; stack sampling also requires a selected PID.":"Ready. Starts only when requested.")
        :root.job.status==="error"?"Unavailable: "+String(root.job.error || "request failed").split("_").join(" ")
        :root.job.status==="canceled"?"Canceled. No continuous sampler remains."
        :"Captured "+DeckState.time(root.report.from_at_ms)+" → "+DeckState.time(root.report.at_ms)+" / "+DeckState.measured(root.report.span_ms,"ms")+" / "+(root.report.partial?"PARTIAL":"completed acquisition")
    }
    Label {
      width:parent.width; visible:!!root.report
      text:!root.report?"":root.kind==="sample_process"
        ?root.report.samples+" / "+root.report.requested_samples+" samples; "+root.report.missed_samples+" missing. "+(root.report.statuses || []).map(function(s){return s.status+": "+s.count}).join(" / ")+"\nMemory change "+DeckState.signedBytes(root.report.memory_delta_bytes)+" / "+DeckState.measured(root.report.reductions_per_second,"reductions/s")+" / mailbox change "+DeckState.measured(root.report.mailbox_delta,"messages")
        :"Scanned "+root.report.first_scanned+" → "+root.report.last_scanned+"; matched "+root.report.matched+"; first only "+root.report.first_only+"; last only "+root.report.last_only+"; "+root.report.omitted_rows+" ranked rows omitted. Unmatched does not prove an exit or creation."
    }
    Flow {
      width:parent.width; spacing:Style.space(6); visible:!!root.report && root.kind!=="sample_process"
      Controls.TextField { width:Math.min(320,parent.width); placeholderText:"Filter measured names or PIDs"; text:root.query; onTextEdited:root.query=text; Accessible.name:placeholderText }
      Controls.ComboBox {
        model:root.kind==="process_window"?["Reductions/s","Memory change","Mailbox change"]:["Memory change","Element change"]
        currentIndex:(root.kind==="process_window"?["reductions_per_second","memory_delta_bytes","mailbox_delta"]:["memory_delta_bytes","size_delta"]).indexOf(root.sort)
        onActivated:function(i){root.sort=(root.kind==="process_window"?["reductions_per_second","memory_delta_bytes","mailbox_delta"]:["memory_delta_bytes","size_delta"])[i]}
        Accessible.name:"Measured interval sort"
      }
    }
    Flow {
      width:parent.width; spacing:Style.space(6); visible:root.rankedRows.length>0
      Label { text:"Rows "+(root.page*5+1)+"–"+Math.min(root.page*5+5,root.rankedRows.length)+" of "+root.rankedRows.length+" filtered results" }
      ActionButton { text:"Previous rows"; enabled:root.page>0; onClicked:root.page-- }
      ActionButton { text:"Next rows"; enabled:(root.page+1)*5<root.rankedRows.length; onClicked:root.page++ }
    }
    Repeater {
      model:KeyedRows { rows:root.pageRows; keyField:"key" }
      Column {
        id:row; required property string rowJson
        property var entry:JSON.parse(rowJson)
        width:body.width; spacing:Style.space(4)
        Label { width:parent.width; text:DeckState.intervalRowText(row.entry,root.kind) }
        ActionButton {
          text:root.kind==="process_window"?"Inspect PID":"Inspect owner"
          enabled:root.canInspect && row.entry.status!=="not_reobserved" && !!(row.entry.pid || row.entry.owner)
          onClicked:root.inspectRequested(row.entry.pid || row.entry.owner)
        }
      }
    }
    Repeater {
      model:KeyedRows { rows:root.report?(root.report.stacks || []):[]; keyField:"key" }
      Column {
        id:stackRow; required property string rowJson
        property var entry:JSON.parse(rowJson)
        width:body.width; spacing:Style.space(4)
        Label { width:parent.width; text:stackRow.entry.count+" / "+root.report.samples+" samples ("+Math.round(100*DeckState.stackFraction(stackRow.entry,root.report))+"%) · "+DeckState.stackFrame((stackRow.entry.frames || [])[0]) }
        Item {
          width:parent.width; height:Style.space(6)
          Rectangle { anchors.fill:parent; color:Util.alpha(Color.popups.text,0.1) }
          Rectangle { objectName:"stackFrequencyBar"; width:parent.width*DeckState.stackFraction(stackRow.entry,root.report); height:parent.height; color:Color.accent }
        }
        ActionButton { text:root.expandedStack===stackRow.entry.key?"Hide stack":"Show stack"; selected:root.expandedStack===stackRow.entry.key; onClicked:root.expandedStack=root.expandedStack===stackRow.entry.key?"":stackRow.entry.key }
        Label { width:parent.width; visible:root.expandedStack===stackRow.entry.key; text:(stackRow.entry.frames || []).map(DeckState.stackFrame).join("\n") }
      }
    }
    Label { width:parent.width; visible:!!root.report && !(root.report.rows || []).length && !(root.report.stacks || []).length; text:"No comparable rows or stack frames were captured. Review scan/sample coverage above." }
  }
  component Label: Text { color:Color.popups.text; font.family:Style.font.family; font.pixelSize:Style.font.caption; wrapMode:Text.Wrap; textFormat:Text.PlainText }
}
