import QtQuick
import "BlueFerryModel.js" as BlueFerry

Item {
  id: root
  // Item.enabled is the explicit user opt-in. No discovery or activation while off.
  enabled: false
  property bool panelOpen: false
  property string helperPath: decodeURIComponent(Qt.resolvedUrl("bin/omalink-blueferry").toString().replace(/^file:\/\//, ""))
  property int generation: 0
  property int requestGeneration: -1
  property var snapshot: null
  property string failureCode: ""
  readonly property var endpoint: BlueFerry.endpoint()
  readonly property string backendOwner: snapshot ? snapshot.backendOwner : ""
  readonly property bool refreshing: statusRequest.running
  readonly property bool canReadHistory: enabled && panelOpen && !!snapshot && snapshot.canReadHistory && failureCode === ""
  readonly property string statusText: !enabled ? qsTr("BlueFerry is off in OmaLink")
    : refreshing && !snapshot ? qsTr("Checking BlueFerry…")
    : failureCode !== "" ? BlueFerry.errorText(failureCode)
    : !snapshot ? qsTr("Open the panel to check BlueFerry")
    : snapshot.connection === "ready" ? qsTr("Phone message profiles connected")
    : snapshot.connection === "connecting" ? qsTr("BlueFerry is connecting to the phone")
    : snapshot.connection === "authorization-required" ? qsTr("Allow message access on the iPhone in BlueFerry setup")
    : snapshot.connection === "offline" ? qsTr("Phone offline; retained history may still be available")
    : qsTr("Phone connection is unknown")
  readonly property string storageText: !snapshot ? qsTr("Storage status is unavailable")
    : snapshot.storage === "locked" ? qsTr("Unlock the desktop wallet in BlueFerry to view encrypted history")
    : snapshot.storage === "disabled" || snapshot.storagePolicy === "none" ? qsTr("BlueFerry is set not to retain local history")
    : snapshot.storage === "error" ? qsTr("BlueFerry could not read retained data. Check its storage settings.")
    : snapshot.storage !== "ready" ? qsTr("BlueFerry storage availability is unknown")
    : snapshot.storagePolicy === "encrypted" ? qsTr("BlueFerry retains encrypted history; OmaLink keeps this view in memory")
    : snapshot.storagePolicy === "plaintext" ? qsTr("BlueFerry retains unencrypted history; OmaLink keeps this view in memory")
    : qsTr("BlueFerry storage policy is unknown")

  onEnabledChanged: reset()
  onPanelOpenChanged: reset()
  Component.onCompleted: if (enabled && panelOpen) refresh()

  function reset() {
    generation++
    statusRequest.cancel()
    snapshot = null
    failureCode = ""
    if (enabled && panelOpen) Qt.callLater(refresh)
  }

  function refresh() {
    if (!enabled || !panelOpen || refreshing) return false
    requestGeneration = generation
    return statusRequest.start({version:1, operation:"status"})
  }

  ProviderRequest {
    id: statusRequest
    helperPath: root.helperPath
    onFinished: function(transport) {
      if (!root.enabled || !root.panelOpen || root.requestGeneration !== root.generation) return
      var outcome = BlueFerry.result(transport, "status", "")
      if (!outcome.ok) {
        root.snapshot = null
        root.failureCode = outcome.code
        return
      }
      root.snapshot = outcome
      root.failureCode = ""
    }
  }
  Timer {
    interval: 30000
    repeat: true
    running: root.enabled && root.panelOpen
    onTriggered: root.refresh()
  }
}
