pragma Singleton
import QtQuick
QtObject {
  property color foreground: "#ffccaa"
  property color accent: "#9999ff"
  property color urgent: "#ff4433"
  property var popups: ({background:"#070c20",text:"#ffccaa",border:"#9999ff"})
  property var tooltip: ({background:"#070c20",text:"#ffccaa",border:"#9999ff"})
  property var shellValues: ({})
}
