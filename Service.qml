import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false
  property bool installed: false
  property bool statusFailed: false
  property bool statusReady: false
  property bool refreshing: false
  property var devices: []
  readonly property string selectedDeviceId: Model.selectedDeviceId(devices, String(setting("selectedDeviceId", "")))
  readonly property var selectedDevice: Model.deviceById(devices, selectedDeviceId)
  readonly property string selectedDeviceName: selectedDevice ? selectedDevice.name
    : String(setting("selectedDeviceName", "Selected phone")).slice(0, 256)
  readonly property bool selectedDeviceReady: canUseDevice(selectedDeviceId)
  readonly property string statusText: !statusReady ? qsTr("Checking…")
    : statusFailed ? qsTr("Could not refresh phone status. Actions paused.")
    : !installed ? qsTr("KDE Connect is not installed")
    : selectedDeviceId !== "" ? selectedDeviceName + (selectedDevice ? "" : " · " + qsTr("Offline or unavailable"))
    : devices.length > 1 ? qsTr("Choose a phone below") : qsTr("No phone connected")
  property string actionStatus: ""
  property string actionSuccess: ""
  signal selectionSuggested(string deviceId, string deviceName)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property var notifySources: settings && settings["notifyApps"] !== undefined && settings["notifyApps"] !== null
    ? String(settings["notifyApps"]) : undefined
  readonly property string notifyPopups: String(setting("notifyPopups", "On")).toLowerCase() === "off" ? "off" : "on"
  readonly property bool mediaControls: String(setting("mediaControls", "On")).toLowerCase() !== "off"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helperPath: pluginDir + "/bin/omalink"

  function withNotify(command) {
    return [helperPath, "--popups", notifyPopups].concat(
      notifySources !== undefined ? ["--notify-apps", notifySources] : [], command.slice(1))
  }
  onNotifySourcesChanged: restartWatcher()
  onNotifyPopupsChanged: restartWatcher()

  function restartWatcher() {
    watchProcess.running = false
    watchRestart.restart()
    refresh()
  }

  readonly property bool connected: installed && !statusFailed && devices.length > 0

  function canUseDevice(deviceId) {
    return installed && !statusFailed && Model.deviceById(devices, deviceId) !== null
  }

  function actionTarget(deviceId) {
    if (canUseDevice(deviceId)) return true
    actionStatus = qsTr("Phone unavailable. Refresh its connection before trying again.")
    clearActionStatus.restart()
    return false
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  function refresh() {
    if (statusProcess.running) return
    refreshing = true
    statusProcess.command = withNotify([helperPath, "status"])
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var status = Model.parseStatus(raw)
    statusReady = true
    statusFailed = String(raw || "").trim() === "" || status.ok !== true
    if (statusFailed) return
    installed = status.installed === true
    devices = status.devices || []
    if (selectedDevice && (String(setting("selectedDeviceId", "")) !== selectedDeviceId
        || String(setting("selectedDeviceName", "")) !== selectedDevice.name))
      selectionSuggested(selectedDeviceId, selectedDevice.name)
  }

  function ring(deviceId) {
    if (actionProcess.running || !actionTarget(deviceId)) return
    actionStatus = "Ringing phone…"
    actionSuccess = qsTr("Ring requested for %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = [helperPath, "ring", String(deviceId)]
    actionProcess.running = true
  }

  function sendClipboard(deviceId) {
    if (actionProcess.running || !actionTarget(deviceId)) return
    actionStatus = "Sending clipboard…"
    actionSuccess = qsTr("Clipboard request sent to %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = [helperPath, "clipboard", String(deviceId)]
    actionProcess.running = true
  }

  function shareText(deviceId, value) {
    if (!value || actionProcess.running || !actionTarget(deviceId)) return
    actionStatus = "Sending to phone…"
    actionSuccess = qsTr("Share request sent to %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = [helperPath, "share", String(deviceId), String(value)]
    actionProcess.running = true
  }

  function dismissNotification(deviceId, notificationId) {
    if (!notificationId || actionProcess.running || !actionTarget(deviceId)) return
    actionStatus = "Dismissing notification…"
    actionSuccess = qsTr("Dismissal requested for %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = [helperPath, "dismiss", String(deviceId), String(notificationId)]
    actionProcess.running = true
  }

  function dismissAllNotifications(deviceId) {
    if (actionProcess.running || !actionTarget(deviceId)) return
    actionStatus = "Clearing notifications…"
    actionSuccess = qsTr("Notification clearing requested for %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = withNotify([helperPath, "dismiss-all", String(deviceId)])
    actionProcess.running = true
  }

  function replyToNotification(deviceId, replyId, message) {
    if (!replyId || !message || actionProcess.running || !actionTarget(deviceId)) return
    actionStatus = "Sending reply…"
    actionSuccess = qsTr("Reply request sent to %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = [helperPath, "notify-reply", String(deviceId), String(replyId), String(message)]
    actionProcess.running = true
  }

  function openPairing() {
    if (installed) Quickshell.execDetached(["kdeconnect-app"])
  }

  // Media actions are fire-and-forget: the panel refreshes its media state on
  // the process exit and from its regular polling, so no status text needed.
  function mediaAction(deviceId, action) {
    if (!action || mediaProcess.running || !actionTarget(deviceId)) return
    mediaProcess.command = [helperPath, "media-action", String(deviceId), String(action)]
    mediaProcess.running = true
  }

  function mediaVolume(deviceId, volume) {
    if (mediaProcess.running || !actionTarget(deviceId)) return
    mediaProcess.command = [helperPath, "media-volume", String(deviceId), String(Math.round(Number(volume) || 0))]
    mediaProcess.running = true
  }

  function mediaSeek(deviceId, position) {
    if (mediaProcess.running || !actionTarget(deviceId)) return
    mediaProcess.command = [helperPath, "media-seek", String(deviceId), String(Math.round(Number(position) || 0))]
    mediaProcess.running = true
  }

  Timer {
    interval: (root.panelOpen ? 3 : root.refreshIntervalSec) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: clearActionStatus
    interval: 2500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: watchProcess
    command: root.withNotify([root.helperPath, "watch"])
    running: true
    stdout: SplitParser {
      onRead: root.refresh()
    }
    onExited: watchRestart.restart()
  }

  Timer {
    id: watchRestart
    interval: 5000
    repeat: false
    onTriggered: watchProcess.running = true
  }

  Process {
    id: statusProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode !== 0) {
        root.statusReady = true
        root.statusFailed = true
      }
    }
  }

  Process {
    id: actionProcess
    onExited: function(exitCode) {
      root.actionStatus = exitCode === 0 ? root.actionSuccess : "Action failed"
      clearActionStatus.restart()
      root.refresh()
    }
  }

  Process {
    id: mediaProcess
    onExited: root.refresh()
  }
}
