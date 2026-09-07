import QtQuick
import QtTest
import qs.Commons
import "../../qml" as Deck
TestCase {
  visible:true
  id:suite
  name:"MeasuredRecorder"
  when:windowShown
  width:700; height:600
  Component { id:factory; Deck.RecorderTimeline { onRangeRequested:function(a,b){fromFrame=a;toFrame=b;live=false} } }
  function rows() { return [0,1000,9000].map(function(ms,i){return {frame_id:"frame-"+(i+1),at_ms:100000-ms,sample_mono_ms:ms,beam_rss_bytes:100+i,nodes:[{name:"fixture",creation:1,attached:true,memory:{total:200+i,processes:80,binary:40,ets:20}}]} }) }
  function test_measured_pointer_and_live_keys() {
    var r=createTemporaryObject(factory,suite,{width:640,timeline:rows()}); wait(30)
    compare(Math.round(r.xForIndex(1)),Math.round(r.plotLeft+r.plotWidth/9))
    mouseClick(r,r.plotLeft+r.plotWidth*0.14,(r.plotTop+r.plotBottom)/2)
    compare(r.toFrame,"frame-2")
    r.live=true; r.forceActiveFocus(); keyClick(Qt.Key_Home); compare(r.toFrame,"frame-1")
    keyClick(Qt.Key_End); compare(r.toFrame,"frame-3")
    keyClick(Qt.Key_Left,Qt.ShiftModifier); compare(r.fromFrame,"frame-1")
  }
  function test_expired_endpoint_is_unavailable() {
    var r=createTemporaryObject(factory,suite,{width:640,timeline:rows(),fromFrame:"frame-expired",toFrame:"frame-3",live:false}); wait(10)
    compare(r.hasSelection,false)
  }
  function test_caption_reflow_and_inactive_paint() {
    var r=createTemporaryObject(factory,suite,{width:440,timeline:rows(),live:false}); wait(30)
    verify(r.metric!==undefined); r.metric="memory"; r.nodeName="fixture"; wait(30)
    var before=r.plotTop, font=Style.font
    Style.font=Object.assign({},font,{caption:font.caption+8}); wait(30)
    verify(r.plotTop>before); verify(r.height>=r.plotBottom)
    Style.font=font; r.renderActive=false; wait(30)
    var paints=r.paintCount; r.timeline=rows().slice(1); wait(30); compare(r.paintCount,paints)
    r.renderActive=true; wait(50); verify(r.paintCount>paints)
  }
}
