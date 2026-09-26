import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  readonly property var endpoint: ({provider:"blueferry",instanceId:"local",deviceId:"local-history",accountId:null})
  function check(value, message) {
    if (!value) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function next() { step++; ticks = 0 }
  function open(owner) { return messages.open(JSON.stringify({endpoint:endpoint,backendOwner:owner})) }
  QtObject {
    id: fakeShell
    property var barConfig: ({layout:{right:[{id:"omalink.phone",blueFerryHistory:"Off"}]}})
  }
  Plugin.Messages { id: messages; shell:fakeShell }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      test.ticks++
      test.check(test.ticks < 70, "step timed out: " + test.step)
      if (test.step === 0) {
        test.check(!test.open(":1.10"), "disabled option accepted a direct summon")
        fakeShell.barConfig = ({layout:{right:[{id:"omalink.phone",blueFerryHistory:"On"}]}})
        test.check(test.open(":1.10"), "explicit BlueFerry route rejected")
        test.check(messages.readOnlyProvider, "BlueFerry view allowed mutation")
        messages.startCompose()
        messages.sendNewMessage()
        messages.sendReply()
        messages.openAttachment({unique:"nope",partId:1,mimeType:"image/png"})
        messages.openAttachmentExternally("/tmp/nope")
        test.check(!messages.composing && !messages.sending, "read-only commands changed compose state")
        test.next()
      } else if (test.step === 1 && messages.conversations.length && messages.contacts.length) {
        test.check(messages.conversations[0].threadId === "group:雪:1", "opaque thread key altered")
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 2 && messages.messages.length) {
        test.check(messages.messages[0].body === "  Exact <b>text</b> 😀  ", "message body changed")
        test.check(messages.messages[0].sender === "Fixture sender", "group sender lost")
        test.check(messages.sendOperations.length === 0, "read generated send activity")
        if (Quickshell.env("OMALINK_PREVIEW") === "messages") { stop(); return }
        messages.providerFailure({code:"thread_unavailable",error:"Conversation removed"}, false)
        test.check(!messages.selectedConversation && messages.messages.length === 0
          && Object.keys(messages.messageCache).length === 0 && messages.conversations.length === 0,
          "unavailable thread retained private data")
        // A delayed read must not repopulate the Android route.
        messages.openThread({threadId:"group:雪:1",names:["Fixture group"],addresses:[],unread:true})
        test.next()
      } else if (test.step === 3) {
        messages.open('{"deviceId":"android"}')
        test.check(!messages.readOnlyProvider && messages.contacts.length === 0, "provider switch retained contacts")
        test.next()
      } else if (test.step === 4 && messages.conversations.length && test.ticks > 10) {
        test.check(messages.conversations[0].names[0] === "Android fixture", "late BlueFerry read replaced Android data")
        test.check(messages.contacts[0].name === "Android contact", "late BlueFerry contacts leaked")
        test.check(messages.messages.length === 0 && Object.keys(messages.messageCache).length === 0, "history survived provider switch")
        test.check(test.open(":1.11"), "replacement fixture route did not open")
        test.next()
      } else if (test.step === 5 && messages.providerInvalidated) {
        test.check(messages.error.indexOf("restarted") !== -1, "owner change lacked recovery guidance")
        test.check(messages.contacts.length === 0 && messages.messages.length === 0 && messages.conversations.length === 0,
                   "owner change retained history")
        test.check(test.open(":1.12"), "new valid owner could not reopen")
        test.next()
      } else if (test.step === 6 && messages.contacts.length && messages.conversations.length) {
        messages.showProviderContacts()
        test.next()
      } else if (test.step === 7 && messages.contacts.length && test.ticks > 3) {
        test.check(messages.browsingContacts && messages.visibleProviderContacts.length === 1, "cached contacts view missing")
        messages.searchText = "Fixture"
        test.check(messages.visibleProviderContacts.length === 1, "contact filter lost valid result")
        if (Quickshell.env("OMALINK_PREVIEW") === "contacts") { stop(); return }
        fakeShell.barConfig = ({layout:{right:[{id:"omalink.phone",blueFerryHistory:"Off"}]}})
        test.check(messages.contacts.length === 0 && messages.messages.length === 0 && !messages.opened, "opting out retained private data")
        test.check(!test.open(":1.12"), "opting out still allowed direct summon")
        console.log("omalink BlueFerry runtime tests passed")
        Qt.quit()
      }
    }
  }
}
