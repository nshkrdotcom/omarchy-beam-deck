import QtQuick
import QtTest
import qs.Commons
import "../../qml" as Deck
TestCase {
  visible:true
  id: suite
  name: "ProtectedPanel"
  when: windowShown
  width: 1900
  height: 840
  QtObject {
    id: fakeService
    property string workspace:"cockpit"
    property string investigationTab:"triage"
    property bool daemonRunning: true
    property bool panelOpen: false
    property bool historicalMode: false
    property var jobs: ({})
    property string lastError: ""
    property string lastAction: ""
    property double lastActionAt: 0
    property string notificationError: ""
    property bool budgetRequestPending: false
    property var snapshot: ({at_ms:Date.now(),budget_trial:null,onboarding:{state:"no_runtimes"},summary:{},nodes:[],host:{},incidents:[]})
    function setPanelOpen(v) { panelOpen=v }
    function returnLive() { historicalMode=false }
    function refresh() {}
  }
  Component { id: factory; Deck.Panel { service: fakeService } }
  function descendants(item) {
    var out=[item]
    for(var i=0;i<item.children.length;i++) out=out.concat(descendants(item.children[i]))
    return out
  }
  property var originalFont: null
  function init() { originalFont=Style.font }
  function cleanup() { Style.font=originalFont }
  function test_larger_host_tokens() {
    Style.font=Object.assign({},Style.font,{caption:15,subtitle:19,body:18,bodySmall:16})
    test_header({w:900})
  }
  function test_header_data() { return [{tag:"compact",w:900},{tag:"native",w:1270},{tag:"wide",w:1900}] }
  function test_header(data) {
    var p=createTemporaryObject(factory,suite,{width:data.w,height:764})
    verify(p)
    wait(30)
    var all=descendants(p), title=all.filter(function(x){return x.text==="BEAM DECK"})[0]
    verify(title)
    compare(title.font.family,Style.font.family); compare(title.font.pixelSize,Style.font.subtitle)
    compare(title.font.weight,Font.DemiBold); verify(Math.abs(title.font.letterSpacing-0.4)<1/64)
    var names=["Cockpit","Investigate","Refresh","Shortcuts","Close"]
    var buttons=names.map(function(n){return all.filter(function(x){return x.text===n && x.horizontalPadding!==undefined})[0]})
    var rail=buttons[0].parent
    for(var i=0;i<buttons.length;i++) {
      var b=buttons[i]; compare(b.parent,rail); compare(b.fontSize,Style.font.caption)
      compare(b.horizontalPadding,Style.spacing.controlPaddingX); compare(b.verticalPadding,Style.spacing.controlPaddingY)
      compare(b.y,buttons[0].y); verify(b.width>=b.implicitWidth)
      if(i) verify(b.x>=buttons[i-1].x+buttons[i-1].width)
    }
    var point=title.mapToItem(p,0,0); compare(point.x,10)
    compare(Math.round(rail.mapToItem(p,rail.width,0).x),Math.min(data.w,1280)-10)
    verify(title.mapToItem(p,title.width,0).x<rail.mapToItem(p,0,0).x)
    compare(buttons[4].bordered,true)
    p.destroy()
  }
}
