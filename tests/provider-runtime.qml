import QtQuick
import Quickshell
import "." as Plugin
import "ProviderModel.js" as Providers

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  property string oldKey: ""
  property int oldGeneration: 0
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function next() { step++; ticks = 0 }
  Plugin.Messages { id: messages }
  Timer {
    interval: 80
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      test.ticks++
      test.check(test.ticks < 60, "step timed out: " + test.step)
      if (test.step === 0) {
        test.check(messages.open(JSON.stringify({endpoint:Providers.kdeEndpoint("old"),deviceId:"old"})), "explicit route rejected")
        test.check(messages.deviceId === "old", "route did not derive device ID")
        test.next()
      } else if (test.step === 1 && messages.conversations.length) {
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 2 && messages.messages.length) {
        test.oldKey = Providers.threadKey(Providers.kdeEndpoint("old"),"7")
        test.check(messages.messageCache[test.oldKey][0].body === "old history", "history cache lost endpoint scope")
        test.check(messages.messageCache["7"] === undefined, "history cached by bare thread ID")
        messages.replyText = "keep my draft"
        test.oldGeneration = messages.generation
        var valid = Providers.kdeEndpoint("old")
        var rejected = ["not json", "null", "[]", " ".repeat(65537),
          JSON.stringify({endpoint:{provider:"blueferry",instanceId:"local",deviceId:"old",accountId:null},deviceId:"old"}),
          JSON.stringify({endpoint:{provider:"blip",instanceId:"local",deviceId:"old",accountId:null},deviceId:"old"}),
          JSON.stringify({endpoint:Object.assign({},valid,{instanceId:"remote"}),deviceId:"old"}),
          JSON.stringify({endpoint:Object.assign({},valid,{accountId:"account"}),deviceId:"old"}),
          JSON.stringify({endpoint:null,deviceId:"old"}), JSON.stringify({endpoint:valid,deviceId:"new"})]
        for (var i = 0; i < rejected.length; i++)
          test.check(messages.open(rejected[i]) === false, "invalid route accepted: " + i)
        test.check(messages.deviceId === "old" && messages.generation === test.oldGeneration,
          "rejected route changed active identity or generation")
        test.check(messages.replyText === "keep my draft" && messages.messageCache[test.oldKey][0].body === "old history",
          "rejected route erased valid state")
        // Start a second old-phone read, which the helper deliberately delays.
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 3) {
        test.check(messages.open(JSON.stringify({endpoint:Providers.kdeEndpoint("new")})), "new local route rejected")
        test.check(messages.generation > test.oldGeneration && messages.messageCache[test.oldKey] === undefined,
          "phone switch retained old cache/generation")
        test.check(messages.replyText === "", "phone switch retained draft")
        test.next()
      } else if (test.step === 4 && messages.conversations.length) {
        messages.openThread(messages.conversations[0])
        test.next()
      } else if (test.step === 5 && messages.messages.length && test.ticks > 12) {
        var key = Providers.threadKey(Providers.kdeEndpoint("new"),"7")
        test.check(messages.deviceId === "new" && messages.messages[0].body === "new history", "late old read replaced new route")
        test.check(Object.keys(messages.messageCache).length === 1 && messages.messageCache[key][0].body === "new history",
          "same thread ID reused another endpoint's cache")
        test.check(messages.threadCacheKey(null) === "" && messages.threadCacheKey(undefined) === "", "provisional thread acquired cache identity")
        messages.close()
        test.check(!messages.opened && !messages.messages.length && !messages.sendOperations.length
          && !Object.keys(messages.messageCache).length, "close retained private history")
        test.check(messages.open('{"deviceId":"old"}'), "legacy summon rejected")
        test.next()
      } else if (test.step === 6 && messages.conversations.length) {
        test.check(messages.endpointKey === Providers.endpointKey(Providers.kdeEndpoint("old")), "legacy summon derived wrong identity")
        messages.close()
        console.log("omalink provider runtime tests passed")
        Qt.quit()
      }
    }
  }
}
