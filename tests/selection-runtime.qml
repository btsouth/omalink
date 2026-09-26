import QtQuick
import Quickshell
import "." as Plugin

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
  function status(devices) { return JSON.stringify({ok:true,installed:true,devices:devices}) }
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
    function summon(id, value) { test.launched = value }
  }
  QtObject {
    id: fakeBar
    property QtObject shell: fakeShell
    property color foreground: "white"
    property color barForeground: "white"
    property color urgent: "red"
    property string fontFamily: "monospace"
    property int height: 30
    property int barSize: 30
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property string position: "top"
    function hideTooltip(item) {}
  }
  Plugin.Panel { id: panel; manageIpc: false; bar: fakeBar }
  // A second instance models a shell reload with the persisted settings.
  Component { id: restoredPanel; Plugin.Panel { manageIpc: false; bar: fakeBar } }

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
        console.log("omalink selection runtime tests passed")
        Qt.quit()
      }
      test.step++
    }
  }
}
