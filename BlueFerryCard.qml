import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

ColumnLayout {
  id: root
  required property var service
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  signal openHistory(var endpoint, string backendOwner)
  spacing: 8

  Text {
    Layout.fillWidth: true
    text: qsTr("iPhone history · BlueFerry")
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    wrapMode: Text.Wrap
  }
  Text {
    Layout.fillWidth: true
    text: qsTr("Experimental, view only. This shows history retained by the local BlueFerry backend, separately from your selected KDE phone.")
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }
  Text {
    Layout.fillWidth: true
    text: root.service.statusText
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }
  Text {
    Layout.fillWidth: true
    text: root.service.storageText
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }
  Text {
    Layout.fillWidth: true
    text: qsTr("Install and pair your iPhone in BlueFerry, then start its backend. OmaLink does not start it automatically or change pairing, wallet or retention settings.")
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }
  Flow {
    Layout.fillWidth: true
    spacing: 8
    Button {
      text: root.service.refreshing ? qsTr("Checking…") : qsTr("Refresh")
      enabled: root.service.enabled && root.service.panelOpen && !root.service.refreshing
      focusable: true
      Accessible.role: Accessible.Button
      Accessible.name: qsTr("Refresh BlueFerry status")
      onClicked: root.service.refresh()
    }
    Button {
      text: qsTr("View history")
      enabled: root.service.canReadHistory && !root.service.refreshing
      focusable: true
      Accessible.role: Accessible.Button
      Accessible.name: qsTr("View read-only BlueFerry history")
      onClicked: root.openHistory(root.service.endpoint, root.service.backendOwner)
    }
    Button {
      text: qsTr("Setup guide")
      focusable: true
      Accessible.role: Accessible.Button
      Accessible.name: qsTr("Open the BlueFerry setup guide in your browser")
      onClicked: Qt.openUrlExternally("https://github.com/erikwb/blueferry#pair-an-iphone")
    }
  }
}
