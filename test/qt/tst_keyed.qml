import QtQuick
import QtTest
import "../../qml" as Deck
TestCase {
  id:suite
  name:"KeyedEvidence"
  when:windowShown
  width:500; height:300
  function test_stable_delegate_and_focus_reveal() {
    var component=Qt.createComponent("../../qml/KeyedRows.qml")
    compare(component.status,Component.Ready,component.errorString())
    var model=component.createObject(suite,{rows:[{id:"one",text:"One"},{id:"two",text:"Two"}]})
    verify(model)
    var view=Qt.createQmlObject('import QtQuick; import "../../qml" as Deck; Flickable { width:400; height:120; contentWidth:width; contentHeight:body.height; property alias repeater:rep; Column { id:body; width:400; Repeater { id:rep; delegate: Deck.ActionButton { required property string rowJson; required property string rowKey; text:JSON.parse(rowJson).text; selected:true; height:100 } } } }',suite)
    view.repeater.model=model; wait(30)
    var row=view.repeater.itemAt(1); row.forceActiveFocus(); wait(20)
    verify(row.activeFocus); verify(row._showFocusRing); verify(view.contentY>0)
    verify(row.mapToItem(view,0,row.height).y<=view.height)
    model.rows=[{id:"zero",text:"Zero"},{id:"two",text:"Changed"},{id:"one",text:"One"}]; wait(30)
    compare(view.repeater.itemAt(1),row); compare(row.text,"Changed"); verify(row.activeFocus)
    view.destroy(); model.destroy()
  }
}
