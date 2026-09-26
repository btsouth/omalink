import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "FileShareModel.js" as Files

Item {
  id: root
  property string deviceId: ""
  property string deviceName: ""
  property bool canShare: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string helperPath: Files.localPath(Qt.resolvedUrl("bin/omalink-files").toString())
  // Native picker is preferred. Tests may use Qt's fallback without a portal.
  property bool useNativeDialog: true
  property var selectedPaths: []
  property string destinationId: ""
  property string destinationName: ""
  property string statusText: ""
  property string statusState: ""
  property string statusDestinationName: ""
  property int selectionGeneration: 0
  property var pickerRoute: null
  property bool requestActive: false
  readonly property bool sending: requestActive || sendProcess.running
  readonly property bool pickerVisible: picker.visible
  implicitHeight: content.implicitHeight
  implicitWidth: 320
  signal requestFinished(string state, string destination)

  onDeviceIdChanged: invalidateSelection()
  onCanShareChanged: if (!canShare) invalidateSelection()

  function invalidateSelection() {
    selectionGeneration++
    selectedPaths = []
    destinationId = ""
    destinationName = ""
    pickerRoute = null
    picker.close()
  }
  function route() {
    if (!canShare || !Files.validDeviceId(deviceId) || sending) return null
    return {id:deviceId, name:String(deviceName || deviceId).slice(0, 256), generation:selectionGeneration}
  }
  function selectUrls(urls, capturedRoute) {
    if (!capturedRoute || capturedRoute.generation !== selectionGeneration || capturedRoute.id !== deviceId || !canShare || sending) return false
    var parsed = Files.selection(urls)
    if (!parsed.ok) {
      statusState = "failed"
      statusText = parsed.error
      statusDestinationName = capturedRoute.name
      return false
    }
    selectedPaths = parsed.paths
    destinationId = capturedRoute.id
    destinationName = capturedRoute.name
    statusText = ""
    statusState = ""
    statusDestinationName = ""
    return true
  }
  function openPicker() {
    var captured = route()
    if (!captured) return
    pickerRoute = captured
    picker.open()
  }
  function removeFile(index) {
    if (sending || index < 0 || index >= selectedPaths.length) return
    selectedPaths = selectedPaths.filter(function(_, position) { return position !== index })
  }
  function submit() {
    if (sending || !canShare || !Files.validDeviceId(destinationId) || destinationId !== deviceId || selectedPaths.length < 1 || selectedPaths.length > 32) return false
    sendProcess.requestCount = selectedPaths.length
    sendProcess.destinationName = destinationName
    sendProcess.response = ""
    sendProcess.command = ["timeout", "--kill-after=1s", "45s", helperPath, destinationId].concat(selectedPaths)
    statusState = "submitting"
    statusDestinationName = destinationName
    statusText = qsTr("Submitting file request to KDE Connect…")
    // A repeated click cannot resend an accepted or uncertain batch. Re-select
    // files explicitly if another request is needed after checking the phone.
    selectedPaths = []
    requestActive = true
    sendProcess.running = true
    return true
  }

  FileDialog {
    id: picker
    title: qsTr("Choose files for %1").arg(root.pickerRoute ? root.pickerRoute.name : "")
    fileMode: FileDialog.OpenFiles
    options: root.useNativeDialog ? 0 : FileDialog.DontUseNativeDialog
    onAccepted: {
      var urls = []
      for (var i = 0; i < selectedFiles.length; i++) urls.push(selectedFiles[i].toString())
      root.selectUrls(urls, root.pickerRoute)
      root.pickerRoute = null
    }
    onRejected: root.pickerRoute = null
  }
  Process {
    id: sendProcess
    property int requestCount: 0
    property string destinationName: ""
    property string response: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: sendProcess.response = text }
    onExited: function(exitCode) {
      root.requestActive = false
      var outcome = Files.result(response, exitCode, requestCount)
      root.statusState = outcome.state
      root.statusText = outcome.text
      root.statusDestinationName = destinationName
      root.requestFinished(outcome.state, destinationName)
    }
  }
  ColumnLayout {
    id: content
    width: root.width
    spacing: Style.space(6)
    Text {
      Layout.fillWidth: true
      text: root.destinationId !== "" && root.selectedPaths.length ? qsTr("To %1 · %2 files").arg(root.destinationName).arg(root.selectedPaths.length)
        : root.canShare ? qsTr("To %1").arg(String(root.deviceName || root.deviceId).slice(0, 256)) : qsTr("Connect a phone with file sharing enabled")
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }
    Controls.ScrollView {
      visible: root.selectedPaths.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(Style.space(150), fileList.implicitHeight)
      clip: true
      contentWidth: availableWidth
      ColumnLayout {
        id: fileList
        width: parent.width
        spacing: Style.space(2)
        Repeater {
          model: root.selectedPaths
          RowLayout {
            required property string modelData
            required property int index
            Layout.fillWidth: true
            spacing: Style.space(8)
            Text {
              text: "󰈔"
              textFormat: Text.PlainText
              color: Qt.darker(root.foreground, 1.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              Layout.fillWidth: true
              text: modelData
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
            }
            PanelActionButton {
              iconText: "󰅖"
              tooltipText: qsTr("Remove")
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Remove %1").arg(modelData)
              focusable: true
              enabled: !root.sending
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.removeFile(index)
            }
          }
        }
      }
    }
    RowLayout {
      spacing: Style.space(8)
      Button {
        iconText: "󰉋"
        text: root.selectedPaths.length > 0 ? qsTr("Change") : qsTr("Choose files")
        bordered: true
        focusable: true
        enabled: root.canShare && !root.sending
        opacity: enabled ? 1.0 : 0.5
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openPicker()
      }
      Button {
        text: qsTr("Clear")
        focusable: true
        visible: root.selectedPaths.length > 0
        enabled: !root.sending
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.invalidateSelection()
      }
      Item { Layout.fillWidth: true }
      Button {
        iconText: "󰒊"
        text: qsTr("Send files")
        bordered: true
        focusable: true
        visible: root.selectedPaths.length > 0
        enabled: root.canShare && !root.sending && root.destinationId === root.deviceId
        opacity: enabled ? 1.0 : 0.5
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.submit()
      }
    }
    Text {
      Layout.fillWidth: true
      visible: root.statusText !== ""
      text: root.statusDestinationName ? qsTr("%1: %2").arg(root.statusDestinationName).arg(root.statusText) : root.statusText
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      Accessible.role: Accessible.StaticText
      Accessible.name: text
    }
    Text {
      Layout.fillWidth: true
      text: qsTr("Up to 32 files and 8 GiB. Check KDE Connect and your phone for transfer results.")
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }
  }
}
