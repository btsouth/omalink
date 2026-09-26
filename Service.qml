import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "NotificationPolicy.js" as NotificationPolicy
import "ProviderModel.js" as Providers

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false
  property bool installed: false
  property bool statusFailed: false
  property bool statusReady: false
  property bool refreshing: false
  property var devices: []
  property string backendVersion: ""
  property bool discoveryTruncated: false
  property double lastSuccessAt: 0
  property double clockNow: Date.now()
  property string diagnosticsText: ""
  property string diagnosticsStatus: ""
  readonly property bool diagnosticsBusy: diagnosticsProcess.running
  readonly property bool stale: lastSuccessAt > 0 && clockNow - lastSuccessAt > Math.max(60000, (panelOpen ? 3 : refreshIntervalSec) * 2000)
  readonly property string freshnessText: lastSuccessAt <= 0 ? qsTr("No successful refresh yet")
    : (stale ? qsTr("Outdated · last checked %1") : qsTr("Last checked %1")).arg(Qt.formatTime(new Date(lastSuccessAt), "hh:mm:ss"))
  readonly property string selectedDeviceId: Model.selectedDeviceId(devices, String(setting("selectedDeviceId", "")))
  readonly property var selectedEndpoint: Providers.kdeEndpoint(selectedDeviceId)
  readonly property string selectedEndpointKey: Providers.endpointKey(selectedEndpoint)
  readonly property var selectedDevice: Model.deviceById(devices, selectedDeviceId)
  readonly property string selectedDeviceName: selectedDevice ? selectedDevice.name
    : String(setting("selectedDeviceName", "Selected phone")).slice(0, 256)
  readonly property bool selectedDeviceReady: canUseDevice(selectedDeviceId)
  readonly property string statusText: !statusReady ? qsTr("Checking…")
    : statusFailed ? qsTr("Could not refresh phone status. Actions paused.")
    : !installed ? qsTr("KDE Connect is not installed")
    : stale ? qsTr("Phone status is outdated. Refresh to use actions.")
    : selectedDeviceId !== "" ? selectedDeviceName + (selectedDeviceReady ? "" : " · " + connectionText(selectedDevice))
    : devices.length > 1 ? qsTr("Choose a phone below") : qsTr("No phone connected")
  property string actionStatus: ""
  property string privateDestinationName: ""
  readonly property bool actionBusy: actionProcess.running || privateAction.running
  property string actionSuccess: ""
  signal selectionSuggested(string deviceId, string deviceName)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property var notifySources: settings && settings["notifyApps"] !== undefined && settings["notifyApps"] !== null
    ? String(settings["notifyApps"]) : undefined
  readonly property string notifyPopups: String(setting("notifyPopups", "On")).toLowerCase() === "off" ? "off" : "on"
  readonly property var notifyRules: NotificationPolicy.normalizeRules(setting("notifyAppRules", null))
  readonly property string notifyRulesArgument: NotificationPolicy.helperArgument(notifyRules)
  readonly property bool mediaControls: String(setting("mediaControls", "On")).toLowerCase() !== "off"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helperPath: pluginDir + "/bin/omalink"

  function withNotify(command) {
    return [helperPath, "--popups", notifyPopups].concat(
      notifySources !== undefined ? ["--notify-apps", notifySources] : [],
      notifyRulesArgument !== "" ? ["--notify-rules", notifyRulesArgument] : [], command.slice(1))
  }
  onNotifySourcesChanged: notificationPolicyChanged()
  onNotifyRulesArgumentChanged: notificationPolicyChanged()
  onNotifyPopupsChanged: restartWatcher()

  // A status read started under the old policy may still list a record the
  // new policy hides. Its result is discarded and read again.
  property int statusGeneration: 0
  function notificationPolicyChanged() {
    statusGeneration++
    restartWatcher()
  }

  function notifyRulesFor(deviceId) {
    return NotificationPolicy.phoneRules(notifyRules, Providers.endpointKey(Providers.kdeEndpoint(deviceId)))
  }

  // The complete new rule set for settings, or null when a limit is reached.
  function notifyRulesWith(deviceId, key, state, label) {
    return NotificationPolicy.withRule(notifyRules, Providers.endpointKey(Providers.kdeEndpoint(deviceId)), key, state, label)
  }

  function notifyRulesWithout(deviceId) {
    return NotificationPolicy.withoutPhone(notifyRules, Providers.endpointKey(Providers.kdeEndpoint(deviceId)))
  }

  function restartWatcher() {
    watchProcess.running = false
    watchRestart.restart()
    refresh()
  }

  readonly property bool connected: installed && !statusFailed && !stale && devices.some(Model.deviceReady)

  function connectionText(device) {
    if (!device) return qsTr("Offline or unavailable")
    if (device.paired === false) return qsTr("Pairing required")
    if (device.reachable === false) return qsTr("Offline")
    return Model.deviceReady(device) ? qsTr("Connected") : qsTr("Connection unknown")
  }

  function setupText(device) {
    if (statusFailed) return qsTr("Refresh the connection before using phone actions.")
    if (stale) return qsTr("Connection information is outdated. Refresh to check this phone.")
    if (device && device.paired === false)
      return qsTr("Open Manage devices and pair this phone. Approve the request on both devices.")
    if (!device || device.reachable === false)
      return qsTr("Open KDE Connect on the phone and connect both devices to the same network. Check pairing and your firewall if it stays offline.")
    if (!Model.deviceReady(device)) return qsTr("KDE Connect could not confirm pairing and reachability. Refresh or open Manage devices.")
    return qsTr("Task availability comes from KDE Connect plugins. Phone permissions may still be required; missing data does not prove permission was denied.")
  }

  function canSelectDevice(deviceId) {
    return installed && !statusFailed && Model.deviceById(devices, deviceId) !== null
  }

  function canUseCapability(deviceId, capability) {
    return canUseDevice(deviceId) && Model.capabilityAvailable(Model.deviceById(devices, deviceId), capability)
  }

  function capabilityText(deviceId, capability) {
    if (statusFailed || stale) return qsTr("Refresh connection")
    var device = Model.deviceById(devices, deviceId)
    if (!Model.deviceReady(device)) return connectionText(device)
    var state = Model.capabilityState(device, capability)
    if (state === "available") return qsTr("Available through KDE Connect")
    if (state === "disabled") return qsTr("Enable this plugin in Manage devices")
    if (state === "unsupported") return qsTr("Not supported by this connection")
    return qsTr("Availability unknown; check KDE Connect on both devices")
  }

  function loadDiagnostics() {
    if (diagnosticsProcess.running) return
    diagnosticsText = ""
    diagnosticsStatus = qsTr("Checking diagnostics…")
    diagnosticsProcess.running = true
  }

  function canUseDevice(deviceId) {
    return installed && !statusFailed && !stale && Model.deviceReady(Model.deviceById(devices, deviceId))
  }

  function actionTarget(deviceId, capability) {
    if (capability ? canUseCapability(deviceId, capability) : canUseDevice(deviceId)) return true
    actionStatus = capability && canUseDevice(deviceId) ? capabilityText(deviceId, capability)
      : qsTr("Phone unavailable. Refresh its connection before trying again.")
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
    statusProcess.generation = statusGeneration
    statusProcess.command = withNotify([helperPath, "status"])
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var status = Model.parseStatus(raw)
    statusReady = true
    statusFailed = String(raw || "").trim() === "" || status.ok !== true
    if (status.schemaVersion === 1) installed = status.installed === true
    if (statusFailed) return
    devices = status.devices || []
    backendVersion = status.backend && status.backend.version ? status.backend.version : ""
    discoveryTruncated = status.discoveryTruncated === true
    lastSuccessAt = Date.now()
    clockNow = lastSuccessAt
    if (selectedDevice && (String(setting("selectedDeviceId", "")) !== selectedDeviceId
        || String(setting("selectedDeviceName", "")) !== selectedDevice.name))
      selectionSuggested(selectedDeviceId, selectedDevice.name)
  }

  function ring(deviceId) {
    if (actionBusy || !actionTarget(deviceId, "ring")) return
    actionStatus = "Ringing phone…"
    actionSuccess = qsTr("Ring requested for %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = [helperPath, "ring", String(deviceId)]
    actionProcess.running = true
  }

  function sendClipboard(deviceId) {
    if (actionBusy || !actionTarget(deviceId, "clipboard")) return
    actionStatus = "Sending clipboard…"
    actionSuccess = qsTr("Clipboard request sent to %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = [helperPath, "clipboard", String(deviceId)]
    actionProcess.running = true
  }

  function shareText(deviceId, value) {
    if (!value || actionBusy || !actionTarget(deviceId, "sharing")) return false
    actionStatus = "Sending to phone…"
    privateDestinationName = Model.deviceById(devices, deviceId).name
    clearActionStatus.stop()
    return privateAction.start({version:1, operation:"share", deviceId:String(deviceId), body:String(value)})
  }

  function dismissNotification(deviceId, notificationId) {
    if (!notificationId || actionBusy || !actionTarget(deviceId, "notifications")) return
    actionStatus = "Dismissing notification…"
    actionSuccess = qsTr("Dismissal requested for %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = [helperPath, "dismiss", String(deviceId), String(notificationId)]
    actionProcess.running = true
  }

  function dismissAllNotifications(deviceId) {
    if (actionBusy || !actionTarget(deviceId, "notifications")) return
    actionStatus = "Clearing notifications…"
    actionSuccess = qsTr("Notification clearing requested for %1").arg(Model.deviceById(devices, deviceId).name)
    actionProcess.command = withNotify([helperPath, "dismiss-all", String(deviceId)])
    actionProcess.running = true
  }

  function replyToNotification(deviceId, replyId, message) {
    if (!replyId || !message || actionBusy || !actionTarget(deviceId, "notifications")) return false
    actionStatus = "Sending reply…"
    privateDestinationName = Model.deviceById(devices, deviceId).name
    clearActionStatus.stop()
    return privateAction.start({version:1, operation:"notify-reply", deviceId:String(deviceId), replyId:String(replyId), body:String(message)})
  }

  function openPairing() {
    if (installed) Quickshell.execDetached(["kdeconnect-app"])
  }

  // Media actions are fire-and-forget: the panel refreshes its media state on
  // the process exit and from its regular polling, so no status text needed.
  function mediaAction(deviceId, action) {
    if (!action || mediaProcess.running || !actionTarget(deviceId, "media")) return
    mediaProcess.command = [helperPath, "media-action", String(deviceId), String(action)]
    mediaProcess.running = true
  }

  function mediaVolume(deviceId, volume) {
    if (mediaProcess.running || !actionTarget(deviceId, "media")) return
    mediaProcess.command = [helperPath, "media-volume", String(deviceId), String(Math.round(Number(volume) || 0))]
    mediaProcess.running = true
  }

  function mediaSeek(deviceId, position) {
    if (mediaProcess.running || !actionTarget(deviceId, "media")) return
    mediaProcess.command = [helperPath, "media-seek", String(deviceId), String(Math.round(Number(position) || 0))]
    mediaProcess.running = true
  }

  Timer {
    interval: 5000
    repeat: true
    running: true
    onTriggered: root.clockNow = Date.now()
  }

  Process {
    id: diagnosticsProcess
    command: [root.helperPath, "diagnostics"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var report = Model.parseDiagnostics(text)
        root.diagnosticsText = report ? JSON.stringify(report, null, 2) : ""
        root.diagnosticsStatus = report ? qsTr("Select and copy this report. It excludes phone names, IDs, addresses and message contents.")
          : qsTr("Could not read diagnostics. Try again.")
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.diagnosticsText = ""
        root.diagnosticsStatus = qsTr("Could not read diagnostics. Try again.")
      }
    }
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
    property int generation: -1
    readonly property bool current: generation === root.statusGeneration
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (statusProcess.current) root.applyStatus(text)
    }
    onExited: function(exitCode) {
      root.refreshing = false
      if (!statusProcess.current) {
        Qt.callLater(root.refresh)
        return
      }
      if (exitCode !== 0) {
        root.statusReady = true
        root.statusFailed = true
      }
    }
  }

  PrivateRequest {
    id: privateAction
    helperPath: root.helperPath
    onFinished: function(outcome) {
      root.actionStatus = root.privateDestinationName + ": " + outcome.text
      if (outcome.state === "accepted") clearActionStatus.restart()
      root.refresh()
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
