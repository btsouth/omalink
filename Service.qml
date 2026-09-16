import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false
  property bool installed: false
  property bool refreshing: false
  property var devices: []
  property string statusText: "Checking…"
  property string actionStatus: ""
  property string actionSuccess: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property var notifySources: settings && settings["notifyApps"] !== undefined && settings["notifyApps"] !== null
    ? String(settings["notifyApps"]) : undefined
  readonly property string notifyPopups: String(setting("notifyPopups", "On")).toLowerCase() === "off" ? "off" : "on"
  readonly property bool mediaControls: String(setting("mediaControls", "On")).toLowerCase() !== "off"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helperPath: pluginDir + "/bin/omalink"

  function withNotify(command) {
    var full = command.slice()
    if (notifySources !== undefined) full = full.concat(["--notify-apps", notifySources])
    return full.concat(["--popups", notifyPopups])
  }
  readonly property bool connected: devices.length > 0

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
    installed = status.installed === true
    devices = status.devices || []
    statusText = String(status.statusText || Model.deviceSummary(devices))
  }

  function ring(deviceId) {
    if (!deviceId || actionProcess.running) return
    actionStatus = "Ringing phone…"
    actionSuccess = "Phone is ringing"
    actionProcess.command = [helperPath, "ring", String(deviceId)]
    actionProcess.running = true
  }

  function sendClipboard(deviceId) {
    if (!deviceId || actionProcess.running) return
    actionStatus = "Sending clipboard…"
    actionSuccess = "Clipboard sent"
    actionProcess.command = [helperPath, "clipboard", String(deviceId)]
    actionProcess.running = true
  }

  function shareText(deviceId, value) {
    if (!deviceId || !value || actionProcess.running) return
    actionStatus = "Sending to phone…"
    actionSuccess = "Sent to phone"
    actionProcess.command = [helperPath, "share", String(deviceId), String(value)]
    actionProcess.running = true
  }

  function dismissNotification(deviceId, notificationId) {
    if (!deviceId || !notificationId || actionProcess.running) return
    actionStatus = "Dismissing notification…"
    actionSuccess = "Notification dismissed"
    actionProcess.command = [helperPath, "dismiss", String(deviceId), String(notificationId)]
    actionProcess.running = true
  }

  function dismissAllNotifications(deviceId) {
    if (!deviceId || actionProcess.running) return
    actionStatus = "Clearing notifications…"
    actionSuccess = "Notifications cleared"
    actionProcess.command = withNotify([helperPath, "dismiss-all", String(deviceId)])
    actionProcess.running = true
  }

  function replyToNotification(deviceId, replyId, message) {
    if (!deviceId || !replyId || !message || actionProcess.running) return
    actionStatus = "Sending reply…"
    actionSuccess = "Reply sent"
    actionProcess.command = [helperPath, "notify-reply", String(deviceId), String(replyId), String(message)]
    actionProcess.running = true
  }

  function openPairing() {
    if (installed) Quickshell.execDetached(["kdeconnect-app"])
  }

  // Media actions are fire-and-forget: the panel refreshes its media state on
  // the process exit and from its regular polling, so no status text needed.
  function mediaAction(deviceId, action) {
    if (!deviceId || !action || mediaProcess.running) return
    mediaProcess.command = [helperPath, "media-action", String(deviceId), String(action)]
    mediaProcess.running = true
  }

  function mediaVolume(deviceId, volume) {
    if (!deviceId || mediaProcess.running) return
    mediaProcess.command = [helperPath, "media-volume", String(deviceId), String(Math.round(Number(volume) || 0))]
    mediaProcess.running = true
  }

  function mediaSeek(deviceId, position) {
    if (!deviceId || mediaProcess.running) return
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
    onExited: root.refreshing = false
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
