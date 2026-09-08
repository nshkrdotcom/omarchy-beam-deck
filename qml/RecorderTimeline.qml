import QtQuick
import qs.Commons
import qs.Ui
import "DeckState.js" as DeckState

FocusScope {
  id: root
  property var timeline: []
  property string fromFrame: ""
  property string toFrame: ""
  property bool live: true
  property string metric: "rss"
  property string nodeName: ""
  property bool renderActive: visible
  property color fg: Color.popups.text
  property color dim: Util.alpha(fg, 0.58)
  property color accent: Color.accent
  property color urgent: Color.urgent
  property int paintCount: 0
  readonly property var series: DeckState.recorderSeries(timeline,metric,nodeName)
  signal rangeRequested(string fromFrame, string toFrame)

  readonly property real plotLeft: Style.space(12)
  readonly property real plotRight: width-Style.space(12)
  readonly property real plotTop: heading.y+heading.height+Style.space(8)
  readonly property real plotBottom: plotTop+Style.space(112)
  readonly property real plotWidth: Math.max(1,plotRight-plotLeft)
  readonly property real plotHeight: plotBottom-plotTop
  readonly property bool hasSelection: !live && indexForFrame(fromFrame)>=0 && indexForFrame(toFrame)>=0
  readonly property real fromX: xForFrame(fromFrame)
  readonly property real toX: xForFrame(toFrame)
  readonly property real selectionLeft: Math.min(fromX,toX)
  readonly property real selectionRight: Math.max(fromX,toX)
  property string dragMode: ""
  property string dragAnchor: ""
  property int hoverIndex: -1
  implicitHeight: legend.y+legend.height+Style.space(10)
  activeFocusOnTab: timeline.length>0
  Accessible.role: Accessible.Slider
  Accessible.name: series.title+" flight recorder. "+(live?"Live":"Historical")
  Accessible.description: "Left/Right step B; Shift+Left/Right step A; Home/End first/last; G returns to live. Drag to select exact retained frames."

  function indexForFrame(id) { return DeckState.recorderIndexById(timeline,id) }
  function xForIndex(i) { return i>=0 && i<series.points.length ? plotLeft+series.points[i].x*plotWidth : plotLeft }
  function xForFrame(id) { return xForIndex(indexForFrame(id)) }
  function nearestIndex(x) {
    var best=-1, distance=Infinity
    for(var i=0;i<series.points.length;i++) { var d=Math.abs(xForIndex(i)-x); if(d<distance){best=i;distance=d} }
    return best
  }
  function frameAtX(x) { var i=nearestIndex(x); return i<0?"":timeline[i].frame_id }
  function requestOrdered(a,b) { var r=DeckState.recorderOrderedRange(timeline,a,b); if(r.from && r.to) rangeRequested(r.from,r.to) }
  function moveEndpoint(which,delta) {
    if(!timeline.length) return
    var a=hasSelection?indexForFrame(fromFrame):timeline.length-1, b=hasSelection?indexForFrame(toFrame):a
    if(which==="from") a=Math.max(0,Math.min(b,a+delta)); else b=Math.max(a,Math.min(timeline.length-1,b+delta))
    requestOrdered(timeline[a].frame_id,timeline[b].frame_id)
  }
  function repaint() { if(renderActive) plot.requestPaint() }
  onSeriesChanged: repaint()
  onRenderActiveChanged: repaint()
  onPlotTopChanged: repaint()
  onWidthChanged: repaint()
  onHeightChanged: repaint()
  onFgChanged: repaint()
  onDimChanged: repaint()
  onAccentChanged: repaint()
  onUrgentChanged: repaint()
  function traceSummary(trace) {
    var i=hoverIndex>=0?hoverIndex:(hasSelection?indexForFrame(toFrame):timeline.length-1)
    var a=hasSelection?indexForFrame(fromFrame):0
    var points=trace.points
    return trace.label+" · "+trace.style+"\n"+DeckState.metricText(points[a]?points[a].value:null,series.unit)+" → "+DeckState.metricText(points[i]?points[i].value:null,series.unit)
  }
  Keys.onPressed: function(event) {
    if(event.modifiers & (Qt.ControlModifier|Qt.AltModifier|Qt.MetaModifier) || !timeline.length) return
    if(event.key===Qt.Key_Left || event.key===Qt.Key_Right) {
      root.moveEndpoint((event.modifiers & Qt.ShiftModifier)?"from":"to",event.key===Qt.Key_Right?1:-1); event.accepted=true
    } else if(event.key===Qt.Key_Home || event.key===Qt.Key_End) {
      var id=timeline[event.key===Qt.Key_Home?0:timeline.length-1].frame_id
      if(hasSelection && !(event.modifiers & Qt.ShiftModifier)) requestOrdered(fromFrame,id)
      else requestOrdered(id,hasSelection?toFrame:id)
      event.accepted=true
    }
  }
  Rectangle { anchors.fill:parent; color:Util.alpha(root.fg,0.035); radius:Style.cornerRadius; border.width:root.activeFocus?2:1; border.color:root.activeFocus?root.accent:Util.alpha(root.fg,0.14) }
  Text {
    id:heading; x:Style.space(12); y:Style.space(8); width:parent.width-Style.space(24)
    text:root.series.title+(root.metric!=="rss"?" / "+(root.nodeName || "choose a node"):"")
      +"\nScale "+DeckState.metricScale(root.series.min,root.series.max,root.series.unit)
      +" · "+(root.series.positionsMeasured?"measured time":"sequence spacing (time unavailable)")
      +"\n▲ symptoms  ■ events · gaps and VM boundaries break traces"
    color:root.dim; font.family:Style.font.family; font.pixelSize:Style.font.caption; textFormat:Text.PlainText; wrapMode:Text.Wrap
  }
  Canvas {
    id:plot; anchors.fill:parent; visible:root.renderActive
    onPaint: {
      if(!root.renderActive) return
      root.paintCount++
      var ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
      ctx.lineWidth=1; ctx.strokeStyle=Util.alpha(root.fg,0.1)
      for(var g=0;g<3;g++) { var gy=root.plotTop+g/2*root.plotHeight;ctx.beginPath();ctx.moveTo(root.plotLeft,gy);ctx.lineTo(root.plotRight,gy);ctx.stroke() }
      var min=root.series.min, max=root.series.max
      var colors=[root.accent,root.fg,root.urgent,root.dim], dashes=[[],[6,3],[1,3],[6,3,1,3]]
      root.series.traces.forEach(function(trace,t) {
        ctx.beginPath();var connected=false
        trace.points.forEach(function(p,i) {
          if(p.value===null) { connected=false;return }
          var x=root.xForIndex(i),y=DeckState.metricY(p.value,min,max,root.plotTop,root.plotBottom)
          if(!connected || p.breakBefore) ctx.moveTo(x,y); else ctx.lineTo(x,y)
          connected=true
        })
        ctx.strokeStyle=colors[t];ctx.lineWidth=2;ctx.setLineDash(dashes[t]);ctx.stroke();ctx.setLineDash([])
        trace.points.forEach(function(p,i) {
          if(p.value===null) return
          var y=DeckState.metricY(p.value,min,max,root.plotTop,root.plotBottom)
          ctx.fillStyle=colors[t];ctx.fillRect(root.xForIndex(i)-1,y-1,2,2)
        })
      })
      root.timeline.slice(0,150).forEach(function(row,i) {
        var x=root.xForIndex(i)
        if(Number(row.alert_count || 0)>0) {ctx.fillStyle=root.urgent;ctx.beginPath();ctx.moveTo(x,root.plotTop);ctx.lineTo(x-3,root.plotTop+6);ctx.lineTo(x+3,root.plotTop+6);ctx.closePath();ctx.fill()}
        if(Number(row.event_count || 0)>0) {ctx.fillStyle=root.accent;ctx.fillRect(x-2,root.plotBottom-4,4,4)}
      })
    }
  }
  Rectangle { visible:root.hasSelection; x:root.selectionLeft; y:root.plotTop; width:Math.max(2,root.selectionRight-root.selectionLeft); height:root.plotHeight; color:Util.alpha(root.accent,0.1); border.width:1; border.color:Util.alpha(root.accent,0.5) }
  Repeater {
    model:[root.fromX,root.toX]
    Rectangle { required property real modelData; visible:root.hasSelection; x:modelData-3; y:root.plotTop-3; width:6; height:root.plotHeight+6; color:root.accent }
  }
  MouseArea {
    id:interaction; x:0; y:root.plotTop; width:root.width; height:root.plotHeight
    hoverEnabled:true; cursorShape:Qt.CrossCursor
    onPositionChanged:function(mouse) {
      root.hoverIndex=root.nearestIndex(mouse.x)
      if(!pressed || !root.dragMode) return
      var frame=root.frameAtX(mouse.x)
      if(root.dragMode==="from") root.requestOrdered(frame,root.toFrame)
      else if(root.dragMode==="to") root.requestOrdered(root.fromFrame,frame)
      else root.requestOrdered(root.dragAnchor,frame)
    }
    onExited:if(!pressed)root.hoverIndex=-1
    onPressed:function(mouse) {
      var frame=root.frameAtX(mouse.x);if(!frame)return
      root.forceActiveFocus()
      if(root.hasSelection && Math.abs(mouse.x-root.fromX)<16) {root.dragMode="from";root.requestOrdered(frame,root.toFrame)}
      else if(root.hasSelection && Math.abs(mouse.x-root.toX)<16) {root.dragMode="to";root.requestOrdered(root.fromFrame,frame)}
      else {root.dragMode="new";root.dragAnchor=frame;root.requestOrdered(frame,frame)}
    }
    onReleased:{root.dragMode="";root.dragAnchor=""}
    onCanceled:{root.dragMode="";root.dragAnchor=""}
  }
  Text {
    x:Style.space(12); y:root.plotBottom+Style.space(8); width:parent.width-Style.space(24)
    text:{
      var i=root.hoverIndex>=0?root.hoverIndex:(root.hasSelection?root.indexForFrame(root.toFrame):root.timeline.length-1),p=root.timeline[i]
      return p?(root.hoverIndex>=0?"INSPECT ":root.live?"LIVE ":"PAUSED ")+DeckState.time(p.at_ms)+" / "+p.frame_id+" / "+Number(p.alert_count || 0)+" symptoms / "+Number(p.event_count || 0)+" events"+(root.series.points[i].gap?" / collection gap":"")+(root.series.points[i].restart?" / VM boundary or unavailable":""):"No measured samples"
    }
    id:inspectionText; color:root.dim; font.family:Style.font.family; font.pixelSize:Style.font.caption; textFormat:Text.PlainText; wrapMode:Text.Wrap
  }
  Flow {
    id:legend; x:Style.space(12); y:inspectionText.y+inspectionText.height+Style.space(8); width:parent.width-Style.space(24); spacing:0
    Repeater {
      model:root.series.traces
      Text {
        required property var modelData
        width:legend.width/Math.min(root.series.traces.length,root.width>=680?4:root.width>=360?2:1)
        text:root.traceSummary(modelData); color:root.fg; font.family:Style.font.family; font.pixelSize:Style.font.caption; textFormat:Text.PlainText; wrapMode:Text.Wrap
        bottomPadding:Style.space(4); rightPadding:Style.space(8)
      }
    }
  }
}
