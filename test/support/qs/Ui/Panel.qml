import QtQuick
Item {
  id: root
  property string moduleName: ""
  property bool manageIpc: false
  property var bar: null
  property var settings: ({})
  property bool opened: false
  property bool popoutSwitchClosing: false
  property QtObject controller: QtObject {
    function show() { root.opened=true }
    function hide() { root.opened=false }
  }
  function toggle() { opened=!opened }
  function closeForPopoutSwitch() { opened=false }
}
