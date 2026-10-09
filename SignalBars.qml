import QtQuick
import qs.Commons

import qs.Commons as Commons
Item {
  id: root

  property int strength: -1
  property color activeColor: Commons.Color.foreground
  property color inactiveColor: Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.22)

  readonly property int level: Math.max(0, Math.min(4, strength))

  implicitWidth: Style.space(18)
  implicitHeight: Style.space(14)

  Row {
    anchors.fill: parent
    spacing: Style.space(2)

    Repeater {
      model: 4

      Item {
        required property int index
        width: (parent.width - parent.spacing * 3) / 4
        height: parent.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.height * (index + 1) / 4
          radius: Math.min(width / 2, Style.space(1))
          color: index < root.level ? root.activeColor : root.inactiveColor
        }
      }
    }
  }
}
