import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  property bool checkedBusyEdit: false
  function check(condition, message) {
    if (!condition) {
      console.error("FAIL: " + message)
      Qt.quit()
      throw new Error(message)
    }
  }
  function next() { step++; ticks = 0 }
  Plugin.Messages {
    id: messages
    sendConfirmationTimeoutMs: 900
    sendReconcileIntervalMs: 70
  }
  Timer {
    interval: 80
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      test.ticks++
      test.check(test.ticks < 80, "step timed out: " + test.step)
      if (test.step === 0) {
        messages.open('{"deviceId":"old"}')
        test.next()
      } else if (test.step === 1 && messages.conversations.length) {
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 2 && messages.messages.length) {
        messages.replyText = "repeat"
        messages.sendReply()
        test.check(messages.latestSend.state === "submitting", "send skipped submitting state")
        test.next()
      } else if (test.step === 3 && !messages.sending) {
        test.check(messages.latestSend.state === "accepted", "exit zero claimed confirmation")
        test.check(messages.replyText === "", "accepted draft was not cleared")
        test.next()
      } else if (test.step === 4 && messages.latestSend.state === "unconfirmed") {
        if (!test.checkedBusyEdit) {
          test.check(messages.messages.length === 2, "old identical history hid local send")
          test.check(messages.messages[1].sendState === "unconfirmed", "reply did not terminate unconfirmed")
          messages.openThread({threadId:8, addresses:["+15550000008"], names:["Other recipient"]})
          messages.editSend(messages.latestSend)
          test.check(messages.selectedConversation.threadId === 8 && messages.replyText === "",
                     "Edit copy placed a message in another recipient's loading conversation")
          test.checkedBusyEdit = true
          return
        }
        if (messages.loading) return
        messages.editSend(messages.latestSend)
        test.check(messages.replyText === "repeat" && messages.selectedConversation.threadId === 7,
                   "unconfirmed text cannot be restored to its original recipient")
        messages.close()
        messages.open('{"deviceId":"confirm"}')
        test.next()
      } else if (test.step === 5 && messages.conversations.length) {
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 6 && messages.messages.length) {
        messages.replyText = "  exact\ntext 😀  "
        messages.sendReply()
        test.next()
      } else if (test.step === 7 && messages.latestSend.state === "confirmed-in-history") {
        test.check(messages.messages.length === 2, "confirmation duplicated bubble")
        test.check(messages.messages[1].sendState === "confirmed-in-history", "history did not label confirmation")
        messages.close()
        messages.open('{"deviceId":"old"}')
        test.next()
      } else if (test.step === 8 && messages.conversations.length) {
        messages.startCompose()
        messages.recipientQuery = "+15550000002"
        messages.recipientNumber = "+15550000002"
        messages.composeText = "brand new thread"
        messages.sendNewMessage()
        test.next()
      } else if (test.step === 9 && !messages.sending) {
        test.check(messages.latestSend.state === "accepted", "new send exit zero claimed confirmation")
        test.next()
      } else if (test.step === 10 && messages.latestSend.state === "unconfirmed") {
        var local = messages.conversations.find(function(row) { return !!row.localOperationId })
        test.check(local !== undefined, "new unresolved conversation disappeared")
        messages.openThread(local)
        test.check(messages.messages[0].body === "brand new thread", "new unconfirmed body is unavailable")
        // A second provisional conversation must not reuse the first null ID.
        var second = Object.assign({}, messages.latestSend)
        second.id = "other-local"
        second.number = "+15550000003"
        second.body = "other recipient body"
        second.conversation = {threadId:null, addresses:[second.number], names:["Other new person"]}
        messages.updateSendOperations(messages.sendOperations.concat([second]))
        var other = messages.conversations.find(function(row) { return row.localOperationId === "other-local" })
        messages.openThread(other)
        test.check(messages.messages.length === 1 && messages.messages[0].body === "other recipient body",
                   "provisional conversation showed another recipient's body")
        messages.close()
        messages.open('{"deviceId":"unknown"}')
        test.next()
      } else if (test.step === 11 && messages.conversations.length) {
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 12 && messages.messages.length) {
        messages.replyText = "keep this text"
        messages.sendReply()
        test.next()
      } else if (test.step === 13 && !messages.sending) {
        test.check(messages.latestSend.state === "unconfirmed", "unknown transport failure was called definite failure")
        test.check(messages.replyText === "keep this text", "failed helper lost draft")
        messages.startCompose()
        messages.recipientNumber = "invalid"
        messages.composeText = "invalid destination text"
        messages.sendNewMessage()
        test.check(messages.latestSend.state === "failed" && !messages.sending, "local rejection was submitted")
        test.check(messages.composeText === "invalid destination text", "local rejection lost draft")
        messages.close()
        messages.open('{"deviceId":"slow"}')
        test.next()
      } else if (test.step === 14 && messages.conversations.length) {
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 15 && messages.messages.length) {
        messages.replyText = "late completion"
        messages.sendReply()
        messages.close()
        messages.open('{"deviceId":"slow"}')
        test.next()
      } else if (test.step === 16 && !messages.sending) {
        test.check(messages.sendOperations.length === 0, "late send restored cleared local state")
        test.check(messages.replyText === "" && messages.composeText === "", "late send repopulated draft")
        messages.close()
        test.check(Object.keys(messages.messageCache).length === 0, "cache survived close")
        messages.open('{"deviceId":"partial"}')
        test.next()
      } else if (test.step === 17 && messages.conversations.length) {
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 18 && messages.messages.length) {
        messages.replyText = "partial history result"
        messages.sendReply()
        test.next()
      } else if (test.step === 19 && !messages.sending) {
        messages.refresh()
        test.next()
      } else if (test.step === 20) {
        test.check(messages.latestSend.state !== "confirmed-in-history",
                   "failed history read confirmed a send from partial output")
        if (messages.latestSend.state !== "unconfirmed") return
        messages.close()
        console.log("omalink send runtime tests passed")
        Qt.quit()
      }
    }
  }
}
