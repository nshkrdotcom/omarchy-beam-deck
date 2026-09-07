pragma Singleton
import QtQuick
QtObject {
  property var font: ({family:"JetBrainsMono Nerd Font",caption:10,body:12,bodySmall:11,subtitle:13,title:16,icon:14})
  property var spacing: ({hairline:1,xxs:2,xs:3,sm:4,md:6,lg:8,xl:10,xxl:12,huge:18,controlGap:6,controlPaddingX:10,controlPaddingY:6})
  property int cornerRadius: 0
  property int gapsOut: 5
  property var styleOverrides: ({})
  property real normalBorderWidth: 1
  property real normalBorderAlpha: 0.4
  property real focusBorderWidth: 1
  property real focusBorderAlpha: 1
  property real hoverBorderWidth: 1
  property real hoverBorderAlpha: 0.5
  property real selectedBorderWidth: 0
  property real selectedBorderAlpha: 0
  function space(n) { return n }
  function normalStateColor(f,a) { return f }
  function focusStateColor(f,a) { return a }
  function hoverStateColor(f,a) { return f }
  function selectedStateColor(f,a) { return f }
  function pressedFillFor(f,a) { return Qt.rgba(f.r,f.g,f.b,0.2) }
  function focusFillFor(f,a) { return Qt.rgba(a.r,a.g,a.b,0.15) }
  function hoverFillFor(f,a) { return Qt.rgba(f.r,f.g,f.b,0.1) }
  function selectedFillFor(f,a) { return Qt.rgba(f.r,f.g,f.b,0.15) }
}
