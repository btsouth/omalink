import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  function check(condition, message) {
    if (!condition) {
      console.error("FAIL: " + message)
      Qt.quit()
      throw new Error(message)
    }
  }
  Plugin.Messages { id: messages }
  // The cached list shows before the slower full read finishes.
  Timer {
    id: cachedCheck
    interval: 150
    onTriggered: test.check(messages.conversations.length === 1 && messages.conversations[0].preview === "cached"
                            && !messages.loading, "the cached thread list was not shown first")
  }
  Timer {
    interval: 700
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (test.step === 0) {
        messages.open('{"deviceId":"first"}')
        messages.close()
      } else if (test.step === 1) {
        test.check(messages.contacts.length === 0 && messages.conversations.length === 0,
                   "late data repopulated the closed window")
        test.check(Object.keys(messages.messageCache).length === 0, "cache survived close")
        messages.open('{"deviceId":"first"}')
        cachedCheck.start()
      } else if (test.step === 2) {
        test.check(messages.conversations.length === 1, "conversations did not load")
        test.check(messages.conversations[0].preview === "fixture", "the full read did not replace the cached list")
        test.check(messages.contacts[0].name === "first", "contacts did not load")
        messages.openThread(messages.conversations[0])
      } else if (test.step === 3) {
        test.check(messages.messages[0].body === "fixture message", "thread did not load")
        for (var i = 0; i < 10; i++) messages.setThreadMessages(String(i), [{body:"cached",incoming:true,pending:false}])
        test.check(Object.keys(messages.messageCache).length === 5, "cache is unbounded")
        messages.open('{"deviceId":"second"}')
      } else if (test.step === 4) {
        test.check(messages.conversations[0].names[0] === "second", "device switch used old data")
        test.check(messages.messages.length === 0, "old phone messages survived switch")
        messages.openAttachment({unique:"one",partId:1,mimeType:"image/png"})
        messages.close()
      } else if (test.step === 5) {
        test.check(Object.keys(messages.attachmentPaths).length === 0 && !messages.viewerOpen,
                   "late attachment reopened or cached after close")
        messages.open('{"deviceId":"first"}')
        messages.close()
        messages.open('{"deviceId":"second"}')
      } else if (test.step === 6) {
        test.check(messages.contacts.length === 1 && messages.contacts[0].name === "second",
                   "immediate reopen left contacts missing or stale")
        test.check(messages.conversations.length === 1 && messages.conversations[0].names[0] === "second",
                   "immediate reopen left conversations missing or stale")
        messages.close()
        // A thread the cache does not have yet still opens once the full read has it.
        messages.open('{"deviceId":"late","threadId":8}')
      } else if (test.step === 7) {
        test.check(messages.selectedConversation && String(messages.selectedConversation.threadId) === "8",
                   "a thread missing from the cache was not opened after the full read")
        messages.close()
        console.log("omalink runtime tests passed")
        Qt.quit()
      }
      test.step++
    }
  }
}
