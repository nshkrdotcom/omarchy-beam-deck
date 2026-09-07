import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id:root
  default property alias content:body.data
  implicitHeight:body.implicitHeight+Style.space(24)
  color:Util.alpha(Color.popups.text,0.035)
  borderSpec:Border.flat(Util.alpha(Color.popups.text,0.12),1)
  radius:Style.cornerRadius
  Column { id:body; x:Style.space(12); y:Style.space(12); width:root.width-Style.space(24); spacing:Style.space(8) }
}
