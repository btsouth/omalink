import QtQuick
import Quickshell
import Quickshell.Io
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  property var historyList: null
  property int anchorIndex: -1
  property double anchorY: 0
  property string anchorBody: ""
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
        capture.start()
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
    id: capture
    interval: 150
    onTriggered: {
      test.anchorIndex = test.historyList.indexAt(1, test.historyList.contentY + 1)
      var item = test.historyList.itemAtIndex(test.anchorIndex)
      test.check(item !== null, "older-history anchor missing")
      test.anchorY = item.mapToItem(test.historyList, 0, 0).y
      test.anchorBody = item.modelData.body
    }
  }
  Timer {
    id: settle
    interval: 500
    onTriggered: {
      var item = test.historyList.itemAtIndex(test.anchorIndex)
      test.check(item !== null && item.modelData.body === test.anchorBody && Math.abs(item.mapToItem(test.historyList, 0, 0).y - test.anchorY) < 2,
        "new SMS moved the visible older-history message: " + test.anchorY + " -> " + (item ? item.mapToItem(test.historyList, 0, 0).y : "missing"))
      console.log("omalink message event runtime tests passed")
      messages.close()
      Qt.quit()
    }
  }
}
