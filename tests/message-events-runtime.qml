import QtQuick
import Quickshell
import Quickshell.Io
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  property var historyList: null
  property double scrollBefore: 0
  property double started: Date.now()
  Plugin.Messages { id: messages }
  function check(value, text) {
    if (!value) { console.error("FAIL: " + text); Qt.quit(); throw new Error(text) }
  }
  function find(item, depth) {
    if (!item || depth > 30) return null
    if (item.objectName === "messageHistoryList") return item
    var children = item.data || item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = find(children[i], depth + 1)
      if (found) return found
    }
    if (item.contentItem && !item.contentItem.length) return find(item.contentItem, depth + 1)
    return null
  }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      if (test.step === 0) {
        messages.open('{"deviceId":"fixture","deviceName":"Test phone"}')
        test.step++
      } else if (test.step === 1 && messages.conversations.length) {
        messages.openThread(messages.conversations[0])
        test.step++
      } else if (test.step === 2 && messages.messages.length) {
        test.historyList = test.find(messages, 0)
        test.check(test.historyList !== null, "history list missing")
        messages.followingLatest = false
        test.historyList.contentY = 200
        test.scrollBefore = test.historyList.contentY
        test.step++
      } else if (test.step === 3 && messages.messages.length === 81) {
        test.check(Date.now() - test.started < 4000, "new SMS waited for polling")
        test.check(messages.messages[80].body === "New incoming message", "wrong message loaded")
        test.check(!messages.followingLatest, "incoming message interrupted older-history reading")
        test.step++
        settle.start()
      }
    }
  }
  Timer {
    id: settle
    interval: 500
    onTriggered: {
      test.check(Math.abs(test.historyList.contentY - test.scrollBefore) < 2,
        "new SMS changed the older-history scroll position: " + test.scrollBefore + " -> " + test.historyList.contentY)
      console.log("omalink message event runtime tests passed")
      messages.close()
      Qt.quit()
    }
  }
}
