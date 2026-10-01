import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root
  property string barPosition: "top"
  property real barSize: 0
  property var entries: []
  property int nextId: 0
  property string pendingCode: ""
  property int copyingId: -1
  property int copiedId: -1
  property int copyErrorId: -1

  function showCode(code) {
    var value = String(code || "")
    if (!/^[0-9]{4,8}$/.test(value)) return
    // Only a few short-lived codes are kept, and never written to settings.
    var current = entries.filter(function(entry) { return entry.code !== value })
    current.push({id: ++nextId, code: value, arrived: Date.now()})
    entries = current.slice(-3)
  }

  function remove(id) {
    entries = entries.filter(function(entry) { return entry.id !== id })
  }

  function clear() {
    entries = []
    if (!codeCopy.running) pendingCode = ""
    copiedId = -1
    copyErrorId = -1
  }

  function copyCode(id, code) {
    if (codeCopy.running || !/^[0-9]{4,8}$/.test(code)) return
    copyErrorId = -1
    pendingCode = code
    copyingId = id
    codeCopy.stdinEnabled = true
    // wl-copy advertises a sensitive MIME hint. Omarchy's clipboard history
    // skips these selections. The code itself is written on stdin, not argv.
    codeCopy.command = ["/usr/bin/wl-copy", "--sensitive", "--type", "text/plain;charset=utf-8"]
    codeCopy.running = true
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.entries.length > 0
    onTriggered: {
      var now = Date.now()
      root.entries = root.entries.filter(function(entry) { return now - entry.arrived < 20000 })
    }
  }

  Timer {
    id: copiedDelay
    interval: 1200
    onTriggered: {
      root.remove(root.copiedId)
      root.copiedId = -1
    }
  }

  Process {
    id: codeCopy
    onStarted: {
      write(root.pendingCode)
      root.pendingCode = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        if (root.copiedId > 0) root.remove(root.copiedId)
        root.copiedId = root.copyingId
        copiedDelay.restart()
      } else {
        root.copyErrorId = root.copyingId
      }
      root.copyingId = -1
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.entries.length > 0
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "omalink-mfa"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region { item: toastColumn }

      ColumnLayout {
        id: toastColumn
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Style.gapsOut
        anchors.bottomMargin: root.barPosition === "bottom" ? root.barSize + Style.space(12) : Style.gapsOut
        spacing: Style.space(8)

        Repeater {
          model: root.entries

          Rectangle {
            id: toast
            required property var modelData
            Layout.preferredWidth: Style.space(360)
            implicitHeight: content.implicitHeight + Style.space(20)
            color: Color.popups.background
            radius: Style.cornerRadius
            border.width: 1
            border.color: Color.foreground

            ColumnLayout {
              id: content
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true

                Text {
                  Layout.fillWidth: true
                  text: qsTr("Verification code")
                  textFormat: Text.PlainText
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Button {
                  text: "✕"
                  focusable: true
                  foreground: Color.foreground
                  fontFamily: Style.font.family
                  Accessible.role: Accessible.Button
                  Accessible.name: qsTr("Dismiss verification code")
                  onClicked: root.remove(toast.modelData.id)
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(12)

                Text {
                  Layout.fillWidth: true
                  text: toast.modelData.code
                  textFormat: Text.PlainText
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  Accessible.name: qsTr("Verification code %1").arg(text)
                }

                Button {
                  text: root.copiedId === toast.modelData.id ? qsTr("Copied") : qsTr("Copy code")
                  enabled: root.copyingId === -1 && root.copiedId !== toast.modelData.id
                  focusable: true
                  bordered: true
                  foreground: Color.foreground
                  fontFamily: Style.font.family
                  Accessible.role: Accessible.Button
                  Accessible.name: qsTr("Copy verification code %1").arg(toast.modelData.code)
                  onClicked: root.copyCode(toast.modelData.id, toast.modelData.code)
                }
              }

              Text {
                visible: root.copyErrorId === toast.modelData.id
                Layout.fillWidth: true
                text: qsTr("Could not copy code. Try again.")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
