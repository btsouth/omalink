import QtQuick
import qs.Commons

// Compact slider for the OmaLink media section: a thin track with a small
// knob, sized for the panel's dense rows. PanelSlider is built for the audio
// panel's taller rows; this keeps seek and volume to ~14px each. Applies
// changes on `released` (drag end or wheel) so a phone round-trip happens
// once, not once per pointer move.
Item {
  id: root

  property QtObject bar: null
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 1
  property bool integer: false
  property color trackColor: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "#333"
  property color fillColor: bar ? bar.foreground : Color.foreground
  property bool dragging: false
  property real liveValue: value

  signal moved(real value)
  signal released(real value)

  implicitWidth: Style.space(120)
  implicitHeight: Style.space(14)

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))

  onValueChanged: if (!dragging) liveValue = value

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(3, Style.space(3))
    radius: height / 2
    color: root.trackColor
  }

  Rectangle {
    anchors.verticalCenter: track.verticalCenter
    anchors.left: track.left
    height: track.height
    radius: track.radius
    color: root.fillColor
    width: track.width * root.progress
  }

  Rectangle {
    id: knob
    width: Style.space(8)
    height: Style.space(8)
    radius: width / 2
    color: root.fillColor
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    function valueFromX(x) {
      var clamped = Math.max(0, Math.min(track.width, x))
      var raw = root.minimum + (clamped / track.width) * root.range
      if (root.integer) raw = Math.round(raw)
      return Math.max(root.minimum, Math.min(root.maximum, raw))
    }

    onPressed: function(mouse) {
      root.dragging = true
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onReleased: function(mouse) {
      root.dragging = false
      root.released(root.liveValue)
      root.liveValue = root.value
    }
    onWheel: function(wheel) {
      var delta = wheel.angleDelta.y > 0 ? root.step : -root.step
      var next = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + delta))
      if (root.integer) next = Math.round(next)
      root.liveValue = next
      root.moved(next)
      root.released(next)
    }
  }
}
