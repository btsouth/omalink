import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "." as Plugin
import "ProviderModel.js" as Providers

ShellRoot {
  id: test
  property int step: 0
  property var phone: null
  property var saved: ({})
  property bool watchingRevert: false
  property bool staleApplied: false
  property int appliedAfterRevert: 0
  property double allowedAt: 0
  readonly property string pixelKey: Providers.endpointKey(Providers.kdeEndpoint("abc123"))
  readonly property string work: Quickshell.env("OMALINK_RULES_DIR")
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
  function apps(list) { return list.map(function(item) { return item.appName }).join(",") }
  function rows() { return panel.notificationAppRows.map(function(row) { return row.key + "=" + row.state }).join(",") }
  function row(repeater, key) {
    for (var i = 0; i < repeater.count; i++) {
      var item = repeater.itemAt(i)
      if (item && item.key === key) return item
    }
    return null
  }
  QtObject {
    id: fakeShell
    function updateEntryInline(id, value) {
      var changed = JSON.stringify(test.saved) !== JSON.stringify(value)
      test.saved = JSON.parse(JSON.stringify(value))
      panel.settings = JSON.parse(JSON.stringify(value))
      return changed
    }
    function summon(id, value) {}
  }
  QtObject {
    id: fakeBar
    property QtObject shell: fakeShell
    property color foreground: Commons.Color.foreground
    property color barForeground: Commons.Color.foreground
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
    implicitWidth: 400; implicitHeight: 35
    anchors { top: true; left: true }
    Plugin.Panel {
      id: panel
      manageIpc: false
      bar: fakeBar
      settings: ({selectedDeviceId: "abc123", selectedDeviceName: "Pixel"})
    }
  }
  Component { id: restoredPanel; Plugin.Panel { manageIpc: false; bar: fakeBar } }
  // Only a status read started under the current policy may be applied.
  Connections {
    target: test.phone
    function onDevicesChanged() {
      if (!test.watchingRevert) return
      test.appliedAfterRevert++
      var pixel = test.phone.devices.filter(function(device) { return device.id === "abc123" })[0]
      if (pixel && test.apps(pixel.notifications).indexOf("Chat") !== -1) test.staleApplied = true
    }
  }

  Timer {
    interval: 800
    running: true
    repeat: true
    onTriggered: {
      if (test.step === 0) {
        for (var i = 0; i < panel.children.length; i++)
          if (typeof panel.children[i].applyStatus === "function") test.phone = panel.children[i]
        test.check(test.phone !== null, "actual Service not loaded")
        if (!test.phone.statusReady || test.phone.devices.length !== 2) return
        test.check(panel.activePhoneId === "abc123", "saved phone not selected")
        test.check(test.apps(panel.phoneNotifications) === "Messages", "legacy source filter changed: " + test.apps(panel.phoneNotifications))
        test.check(panel.messageEntries.length === 1 && panel.notifications.length === 0, "SMS was duplicated outside Messages")
        test.check(panel.notificationSources.examined === 3 && panel.notificationSources.hidden === 2, "scan summary lost")
        test.check(test.rows() === "pkg:com.example.chat=default,pkg:com.google.android.apps.messaging=default,app:Signal=default",
          "observed rows wrong: " + test.rows())
        test.check(panel.notificationAppRows[2].nameOnly && !panel.notificationAppRows[0].nameOnly, "name-only identity not labeled")
        test.check(panel.notificationSummary.join("|") === "2 more hidden by your filters.", "summary: " + panel.notificationSummary.join("|"))
        var generation = test.phone.statusGeneration
        panel.persistSelection("abc123", "Pixel")
        test.check(test.phone.statusGeneration === generation, "unrelated setting invalidated status")
        panel.showSettings = true
        panel.showNotificationApps = true
        test.check(test.named(panel, "notificationAppList", 0).visible, "app list not shown")
        panel.setNotificationRule("pkg:com.example.chat", "allow", "Chat")
        var saved = test.saved.notifyAppRules[test.pixelKey]["pkg:com.example.chat"]
        test.check(saved.state === "allow" && saved.label === "Chat", "allow rule not saved")
        test.check(test.saved.notifyApps === undefined && test.saved.selectedDeviceId === "abc123", "unrelated settings rewritten")
        test.check(test.phone.statusGeneration === generation + 1, "policy change did not invalidate status")
        test.allowedAt = Date.now()
      } else if (test.step === 1) {
        // The watcher restarts after five quiet seconds; let it pick up the rule.
        if (test.apps(panel.phoneNotifications) !== "Chat,Messages" || Date.now() - test.allowedAt < 6000) return
        Quickshell.execDetached(["touch", test.work + "/slow"])
      } else if (test.step === 2) {
        test.phone.refresh()
        test.check(test.phone.refreshing, "slow status did not start")
        test.watchingRevert = true
        panel.setNotificationRule("pkg:com.example.chat", "default", "Chat")
        test.check(test.saved.notifyAppRules === undefined, "last rule left an empty entry")
        // The panel applies the helper's source filter itself, so Default hides
        // Chat at once instead of waiting for the next read.
        test.check(test.apps(panel.phoneNotifications) === "Messages", "Default waited for the helper: " + test.apps(panel.phoneNotifications))
        Quickshell.execDetached(["rm", "-f", test.work + "/slow"])
      } else if (test.step === 3) {
        if (test.phone.refreshing || test.appliedAfterRevert === 0) return
        test.check(!test.staleApplied, "status read under the old policy restored a hidden app")
        test.check(test.apps(panel.phoneNotifications) === "Messages", "revert not applied: " + test.apps(panel.phoneNotifications))
        panel.setNotificationRule("pkg:com.google.android.apps.messaging", "mute", "Messages")
        test.check(panel.phoneNotifications.length === 0, "mute waited for the helper")
        test.check(panel.notificationSectionVisible, "filtered-empty section hidden")
        test.check(panel.notificationSummary[0] === "3 phone notifications are hidden by your filters.",
          "filtered-empty not explained: " + panel.notificationSummary.join("|"))
        panel.setNotificationRule("app:Signal", "mute", "Signal")
        test.phone.dismissAllNotifications("abc123")
      } else if (test.step === 4) {
        if (test.phone.actionBusy || test.phone.refreshing) return
        test.check(test.rows() === "pkg:com.example.chat=default,pkg:com.google.android.apps.messaging=mute,app:Signal=mute",
          "rule states wrong: " + test.rows())
        test.check(panel.notificationSources.hidden === 3 && panel.phoneNotifications.length === 0, "helper did not apply mutes")
        // Rules belong to one phone.
        panel.selectDevice("def456")
        test.check(Object.keys(panel.activePhoneRules).length === 0, "another phone's rules applied")
        test.check(test.apps(panel.phoneNotifications) === "Messages", "second phone lost its notifications")
        test.check(test.rows().indexOf("mute") === -1, "second phone shows the first phone's rules")
        panel.selectDevice("abc123")
        test.check(Object.keys(panel.activePhoneRules).length === 2, "rules lost after switching back")
        var reloaded = restoredPanel.createObject(panel, {settings: test.saved})
        var restored = null
        for (var p = 0; p < reloaded.children.length; p++)
          if (typeof reloaded.children[p].notifyRulesFor === "function") restored = reloaded.children[p]
        test.check(restored && restored.notifyRulesFor("abc123")["app:Signal"].state === "mute", "rules lost on reload")
        reloaded.destroy()
        // App names follow Panel message content.
        var repeater = test.named(panel, "notificationAppRepeater", 0)
        test.check(repeater && repeater.count === 3, "app rows not built")
        var hidden = JSON.parse(JSON.stringify(panel.settings))
        hidden.panelContent = "Hide"
        panel.settings = hidden
        test.check(!test.named(panel, "notificationAppList", 0).visible && repeater.count === 0, "hidden content kept app names")
        test.check(!test.named(panel, "notificationAppsButton", 0).visible, "app rules offered while hidden")
        test.check(panel.notificationSummary.length > 0, "counts hidden with content")
        var shown = JSON.parse(JSON.stringify(hidden))
        shown.panelContent = "Show"
        panel.settings = shown
        test.check(repeater.count === 3, "show did not restore app rows")
        panel.open()
      } else if (test.step === 5) {
        if (Quickshell.env("OMALINK_PREVIEW") === "apps") {
          stop()
          return
        }
        var list = test.named(panel, "notificationAppRepeater", 0)
        var chat = test.row(list, "pkg:com.example.chat")
        chat.ruleGroup.forceActiveFocus()
        test.check(chat.ruleGroup.activeFocus, "rule control cannot take keyboard focus")
        chat.ruleGroup.changed("mute")
      } else if (test.step === 6) {
        var rows = test.named(panel, "notificationAppRepeater", 0)
        var rebuilt = test.row(rows, "pkg:com.example.chat")
        test.check(rebuilt.rule === "mute" && rebuilt.ruleGroup.value === "mute", "keyboard change not applied")
        test.check(rebuilt.ruleGroup.activeFocus, "keyboard focus lost after changing a rule")
        // A new app in the next scan must not rebuild the rows either.
        var status = JSON.parse(JSON.stringify({schemaVersion: 1, ok: true, installed: true, observedAt: 1,
          discoveryTruncated: false, backend: {name: "kdeconnect", version: "26.08.1", versionSource: "kdeconnect-cli", available: true},
          devices: test.phone.devices}))
        var scan = status.devices[0].notificationSources
        scan.examined++
        scan.hidden++
        scan.apps.unshift({key: "pkg:com.example.added", appName: "Added", packageName: "com.example.added", count: 1, permitted: false, sourceAllowed: false})
        test.phone.applyStatus(JSON.stringify(status))
        test.check(rows.count === 4 && test.row(rows, "pkg:com.example.chat") === rebuilt, "a new scan rebuilt the rows")
        test.check(rebuilt.ruleGroup.activeFocus, "keyboard focus lost when a new app appeared")
        panel.resetNotificationRules()
        test.check(test.saved.notifyAppRules === undefined && Object.keys(panel.activePhoneRules).length === 0, "reset kept rules")
      } else if (test.step === 7) {
        if (test.phone.refreshing) return
        test.check(test.apps(panel.phoneNotifications) === "Messages", "reset did not restore the source filter")
        // A status process that cannot start must not block later reads.
        Quickshell.execDetached(["chmod", "-x", test.work + "/bin/omalink"])
      } else if (test.step === 8) {
        test.allowedAt = test.phone.lastSuccessAt
        test.phone.refresh()
      } else if (test.step === 9) {
        Quickshell.execDetached(["chmod", "+x", test.work + "/bin/omalink"])
      } else if (test.step === 10) {
        test.phone.refresh()
      } else if (test.step === 11) {
        if (test.phone.lastSuccessAt <= test.allowedAt) return
        console.log("omalink notification rules runtime tests passed")
        Qt.quit()
      }
      test.step++
    }
  }
}
