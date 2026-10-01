import QtQuick
import Quickshell
import qs.Commons
import "." as Plugin
import "Model.js" as Model

ShellRoot {
  id: test
  property int step: 0
  property var phone: null
  property var saved: ({})
  property var peer: null
  property string launched: ""
  readonly property var first: ({id:"abc123",name:"Pixel",notifications:[{id:"same",appName:"Messages",text:"Pixel message",isConversation:false,replyable:false,dismissable:false}]})
  readonly property var second: ({id:"def456",name:"Galaxy",notifications:[{id:"same",appName:"Messages",text:"Galaxy message",isConversation:false,replyable:false,dismissable:false}]})
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function named(item, name, depth) {
    if (!item || depth > 30) return null
    if (item.objectName === name) return item
    var children = item.data || item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = named(children[i], name, depth + 1)
      if (found) return found
    }
    if (item.contentItem) {
      if (item.contentItem.length !== undefined) {
        for (var c = 0; c < item.contentItem.length; c++) {
          var content = named(item.contentItem[c], name, depth + 1)
          if (content) return content
        }
      } else return named(item.contentItem, name, depth + 1)
    }
    return null
  }
  function status(devices) {
    var normalized = devices.map(function(device) {
      var copy = JSON.parse(JSON.stringify(device))
      if (copy.paired === undefined) copy.paired = true
      if (copy.reachable === undefined) copy.reachable = true
      copy.connectionState = copy.paired ? (copy.reachable ? "ready" : "offline") : "unpaired"
      if (!copy.capabilities) {
        copy.capabilities = {}
        for (var key of ["messaging", "notifications", "ring", "sharing", "clipboard", "media"])
          copy.capabilities[key] = {state:"available",reason:"loaded",supported:true,loaded:true,enabled:true,permission:"unknown",plugin:Model.capabilityPlugins[key]}
      }
      return copy
    })
    return JSON.stringify({schemaVersion:1,ok:true,installed:true,observedAt:Date.now(),discoveryTruncated:false,backend:{name:"kdeconnect",version:"26.08.1",versionSource:"kdeconnect-cli",available:true},devices:normalized})
  }
  QtObject {
    id: fakeShell
    function updateEntryInline(id, value) {
      var changed = JSON.stringify(test.saved) !== JSON.stringify(value)
      test.saved = JSON.parse(JSON.stringify(value))
      // The real bar pushes updated entry settings to every screen's loader.
      panel.settings = JSON.parse(JSON.stringify(value))
      if (test.peer) test.peer.settings = JSON.parse(JSON.stringify(value))
      return changed
    }
    function summon(id, value) { test.launched = value; return true }
  }
  QtObject {
    id: fakeBar
    property QtObject shell: fakeShell
    property color foreground: Color.foreground
    property color barForeground: Color.foreground
    property color urgent: "red"
    property string fontFamily: "monospace"
    property int height: 30
    property int barSize: 30
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property string position: "top"
    property var activePopout: false
    function requestPopout(item) { activePopout = item }
    function releasePopout(item) { activePopout = false }
    function hideTooltip(item) {}
  }
  PanelWindow {
    visible: Quickshell.env("OMALINK_PREVIEW") !== ""
    implicitWidth: 400; implicitHeight: 35
    anchors { top: true; left: true }
    Plugin.Panel { id: panel; manageIpc: false; bar: fakeBar }
  }
  // A second instance models a shell reload with the persisted settings.
  Component { id: restoredPanel; Plugin.Panel { manageIpc: false; bar: fakeBar } }

  Timer {
    interval: 500
    running: panel.opened && Quickshell.env("OMALINK_PREVIEW") !== ""
    repeat: true
    onTriggered: {
      test.phone.applyStatus(test.status([test.first]))
      panel.unreadRaw = [{threadId:7,names:["Synthetic sender"],preview:"Synthetic preview",timestamp:1000,unread:true}]
      panel.seenMap = ({})
    }
  }

  Timer {
    interval: 750
    running: true
    repeat: true
    onTriggered: {
      if (test.step === 0) {
        for (var i = 0; i < panel.children.length; i++)
          if (typeof panel.children[i].applyStatus === "function") test.phone = panel.children[i]
        test.check(test.phone !== null, "actual Service not loaded")
        test.phone.applyStatus(test.status([test.first, test.second]))
        test.check(panel.activePhoneId === "", "multi-phone discovery auto-selected")
        panel.selectDevice("abc123")
        test.check(test.saved.selectedDeviceId === "abc123", "selection not persisted")
        panel.selectDevice("abc123")
        test.check(test.phone.actionStatus === "", "host no-op misreported as persistence failure")
        test.check(panel.notifications[0].text === "Pixel message", "wrong notification source")
        panel.notifReplyId = "same"
        panel.notifReplyDeviceId = "abc123"
        panel.shareDeviceId = "abc123"
        panel.refreshUnread()
        panel.selectDevice("def456")
        test.check(panel.notifReplyId === "" && panel.shareDeviceId === "", "draft route survived selection change")
        panel.selectDevice("abc123")
      } else if (test.step === 1) {
        test.check(panel.unreadRaw.length === 0, "late read accepted after switching away and back")
        panel.selectDevice("def456")
        test.check(panel.notifications[0].text === "Galaxy message", "selected notifications did not switch")
        test.phone.applyStatus(test.status([test.second, test.first]))
        test.check(panel.activePhoneId === "def456", "discovery reorder changed selection")
        panel.openMessages({})
        test.check(JSON.parse(test.launched).deviceId === "def456", "Messages launch used another phone")
        var endpoint = JSON.parse(test.launched).endpoint
        test.check(endpoint.provider === "kdeconnect" && endpoint.instanceId === "local"
          && endpoint.deviceId === "def456" && endpoint.accountId === null, "Messages launch lost endpoint identity")
        panel.refreshUnread()
      } else if (test.step === 2) {
        test.check(panel.unreadRaw[0].names[0] === "def456", "unread read not routed to selected phone")
        test.phone.ring("def456")
        panel.selectDevice("abc123")
        test.phone.applyStatus(test.status([test.second]))
        test.check(panel.activePhoneId === "abc123" && !panel.activePhoneReady, "offline selection retargeted")
        test.check(test.phone.statusText.indexOf("Offline") !== -1, "offline explanation missing")
        test.check(panel.notifications.length === 0, "offline notifications shown as current")
        test.phone.ring("abc123")
      } else if (test.step === 3) {
        test.phone.applyStatus(test.status([test.first, test.second]))
        test.check(panel.activePhoneReady, "selected phone did not reconnect")
        test.phone.applyStatus("{}");
        test.check(!panel.activePhoneReady && test.phone.statusFailed, "malformed status left mutations enabled")
        test.phone.ring("abc123")
        test.check(test.phone.actionStatus.indexOf("unavailable") !== -1, "stale action not rejected")
        test.peer = restoredPanel.createObject(panel, {settings:test.saved})
        test.check(test.peer.activePhoneId === "abc123", "saved selection lost on reload")
        for (var p = 0; p < test.peer.children.length; p++)
          if (typeof test.peer.children[p].applyStatus === "function")
            test.peer.children[p].applyStatus(test.status([test.first, test.second]))
        test.peer.selectDevice("def456")
        test.check(panel.activePhoneId === "def456", "another panel's selection was not applied")
        test.peer.destroy()
        test.peer = null
        panel.settings = ({selectedDeviceId:"abc123",selectedDeviceName:"Pixel"})
        test.phone.applyStatus(test.status([test.first]))
        test.check(panel.activePhoneReady, "good status did not recover")
        panel.settings = ({})
        test.phone.applyStatus(test.status([test.first]))
        test.check(test.saved.selectedDeviceId === "abc123", "single-phone initial choice not saved")
        // Known offline phones remain selectable without enabling any actions.
        var offline = JSON.parse(JSON.stringify(test.second))
        offline.reachable = false
        test.phone.applyStatus(test.status([test.first, offline]))
        panel.selectDevice("def456")
        test.check(panel.activePhoneId === "def456" && !panel.activePhoneReady, "offline selection not represented")
        test.check(test.phone.statusText.indexOf("Offline") !== -1, "known offline state not explained")
        var unpaired = JSON.parse(JSON.stringify(test.first))
        unpaired.paired = false
        panel.settings = ({})
        test.phone.applyStatus(test.status([unpaired]))
        test.check(panel.activePhoneId === "", "unpaired discovery auto-selected")
        panel.selectDevice("abc123")
        test.check(!panel.activePhoneReady && test.phone.setupText(test.phone.selectedDevice).indexOf("pair") !== -1, "pairing guidance missing")
        var disabled = JSON.parse(test.status([test.first]))
        disabled.devices[0].capabilities.messaging.enabled = false
        disabled.devices[0].capabilities.messaging.loaded = false
        test.phone.applyStatus(JSON.stringify(disabled))
        test.check(panel.activePhoneReady && !panel.messagesReady, "disabled messaging enabled")
        test.launched = ""
        panel.openMessages({})
        test.check(test.launched === "", "disabled messaging opened")
        test.check(test.phone.canUseCapability("abc123", "ring"), "unrelated available capability blocked")
        test.phone.clockNow = test.phone.lastSuccessAt + 700000
        test.check(!panel.activePhoneReady, "stale status left actions enabled")
        test.phone.applyStatus(test.status([test.first]))
        test.check(panel.messagesReady, "refresh did not restore available capability")
        var unknown = JSON.parse(test.status([test.first]))
        unknown.devices[0].capabilities = {}
        test.phone.applyStatus(JSON.stringify(unknown))
        test.check(!panel.messagesReady && !test.phone.canUseCapability("abc123", "ring"), "missing capability evidence allowed actions")
        test.phone.ring("abc123")
        test.phone.sendClipboard("abc123")
        test.phone.shareText("abc123", "must not send")
        test.phone.dismissNotification("abc123", "id")
        test.phone.dismissAllNotifications("abc123")
        test.phone.replyToNotification("abc123", "id", "must not send")
        test.phone.mediaAction("abc123", "PlayPause")
        test.phone.mediaVolume("abc123", 10)
        test.phone.mediaSeek("abc123", 10)
        test.phone.loadDiagnostics()
      } else if (test.step === 4) {
        test.check(test.phone.diagnosticsText.indexOf("device-1") !== -1, "diagnostics not displayed")
        test.check(test.phone.diagnosticsText.indexOf("PRIVATE") === -1, "diagnostics exposed unknown private fields")
        // A capability flip invalidates an in-flight read, even if it recovers.
        test.phone.applyStatus(test.status([test.first]))
        panel.refreshUnread()
        var flip = JSON.parse(test.status([test.first]))
        flip.devices[0].capabilities.messaging.enabled = false
        test.phone.applyStatus(JSON.stringify(flip))
        test.phone.applyStatus(test.status([test.first]))
      } else if (test.step === 5) {
        test.check(panel.unreadRaw.length === 0, "late read survived capability flip")
        var missing = JSON.parse(test.status([test.first]))
        missing.devices[0].reachable = null
        test.phone.applyStatus(JSON.stringify(missing))
        test.check(!panel.activePhoneReady, "unknown reachability allowed actions")
        missing.devices[0].reachable = true
        missing.devices[0].paired = null
        test.phone.applyStatus(JSON.stringify(missing))
        test.check(!panel.activePhoneReady, "unknown pairing allowed actions")
        missing.backend.available = false
        missing.ok = false
        test.phone.installed = false
        test.phone.applyStatus(JSON.stringify(missing))
        test.check(test.phone.installed && !panel.activePhoneReady, "missing daemon hid installed manager or allowed actions")
        test.phone.applyStatus(test.status([test.first]))
        panel.selectDevice("abc123")
        var originalSettings = panel.settings
        var shareHidden = JSON.parse(JSON.stringify(originalSettings))
        shareHidden.panelContent = "Hide"
        panel.settings = shareHidden
        panel.shareDeviceId = "abc123"
        var shareInput = test.named(panel, "shareTextField", 0)
        test.check(shareInput !== null, "share field missing")
        shareInput.text = "  exact 😀  "
        shareInput.accepted()
        test.check(test.phone.actionBusy, "hiding notification content blocked share Enter")
        panel.settings = originalSettings
        test.check(test.phone.actionBusy, "share did not synchronously block duplicate action")
        test.check(test.phone.shareText("abc123", "duplicate") === false, "duplicate share accepted")
      } else if (test.step === 6) {
        test.check(!test.phone.actionBusy, "share remained busy")
        test.check(test.phone.actionStatus.indexOf("Pixel:") === 0, "share result lost original destination")
        test.phone.applyStatus(test.status([test.first]))
        test.check(test.phone.replyToNotification("abc123", "reply-id", "  exact 😀  ") === true, "notification reply rejected")
        test.check(test.phone.replyToNotification("abc123", "reply-id", "duplicate") === false, "duplicate reply accepted")
      } else if (test.step === 7) {
        test.check(!test.phone.actionBusy, "notification reply remained busy")
        test.phone.applyStatus(test.status([test.first]))
        test.check(!panel.panelContentHidden, "legacy settings unexpectedly hide content")
        var notifications = test.named(panel, "notificationContentList", 0)
        var unread = test.named(panel, "unreadContentList", 0)
        var reply = test.named(panel, "notificationReplyField", 0)
        test.check(notifications && unread && reply, "privacy controls missing from actual Panel")
        panel.unreadRaw = [{threadId:7,names:["private sender"],preview:"private preview",timestamp:1000,unread:true}]
        panel.seenMap = ({})
        panel.notifReplyId = "pending"
        panel.notifReplyTitle = "private sender"
        panel.notifReplyDeviceId = "abc123"
        reply.text = "unsent private reply"
        var hidden = JSON.parse(JSON.stringify(panel.settings))
        hidden.panelContent = "Hide"
        panel.settings = hidden
        test.check(panel.panelContentHidden && panel.notifications.length === 1, "privacy hid counts or failed to enable")
        test.check(notifications.model.length === 0 && unread.model.length === 0, "hidden content remained in delegate models")
        test.check(!notifications.visible && !unread.visible, "private lists stayed visible")
        test.check(panel.notifReplyId === "" && panel.notifReplyTitle === "" && panel.notifReplyDeviceId === "" && reply.text === "", "privacy retained an unsent reply")
        if (Quickshell.env("OMALINK_PREVIEW") === "hidden") {
          panel.open()
          stop()
          return
        }
        var reloaded = restoredPanel.createObject(panel, {settings:hidden})
        test.check(reloaded.panelContentHidden, "hidden preference lost on reload")
        reloaded.destroy()
        var shown = JSON.parse(JSON.stringify(hidden))
        shown.panelContent = "Show"
        panel.settings = shown
        test.check(notifications.model.length === 1 && unread.model.length === 1, "show did not restore current content")
        test.check(reply.text === "" && panel.notifReplyId === "", "show restored discarded draft")
        if (Quickshell.env("OMALINK_PREVIEW") === "shown") {
          panel.open()
          stop()
          return
        }
        console.log("omalink selection runtime tests passed")
        Qt.quit()
      }
      test.step++
    }
  }
}
