import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int sent: 0
  property int ticks: 0
  property int quietTicks: 0
  property bool initialized: false
  property var outcomes: []
  readonly property string exactBody: "  private fixture\ntext 😀 café  "
  readonly property var modes: ["accepted", "rejected", "malformed", "wrongexit"]
  readonly property var expected: ["accepted", "not-submitted", "unconfirmed", "unconfirmed"]

  function check(condition, message) {
    if (!condition) {
      console.error("FAIL: " + message)
      Qt.quit()
      throw new Error(message)
    }
  }
  function request(body, mode) {
    return {version:1, operation:"share", deviceId:mode, body:body}
  }

  Plugin.PrivateRequest {
    id: sender
    helperPath: Qt.resolvedUrl("bin/omalink").toString().replace(/^file:\/\//, "")
    onFinished: function(outcome) {
      test.outcomes = test.outcomes.concat([outcome])
    }
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      test.ticks++
      test.check(test.ticks < 180, "private request timed out")
      if (!test.initialized) {
        for (var body of ["", "😀".repeat(2049), "invalid\u0000text"]) {
          test.check(!sender.start(test.request(body, "invalid")), "invalid body started a helper")
          test.check(!sender.running, "invalid body left sender busy")
          test.check(test.outcomes[test.outcomes.length - 1].state === "not-submitted",
                     "invalid body was not classified as local rejection")
        }
        test.check(test.outcomes.length === 3, "invalid body emitted repeated completion")
        test.outcomes = []
        test.initialized = true
      }
      test.check(test.outcomes.length <= test.sent, "unexpected completion or automatic retry")
      if (test.outcomes.length < test.sent || sender.running) return
      if (test.sent > 0) {
        test.check(test.outcomes[test.sent - 1].state === test.expected[test.sent - 1],
                   "wrong result for " + test.modes[test.sent - 1])
        test.check(sender.pendingInput === "" && sender.response === "", "completed request retained payload")
      }
      if (test.sent === test.modes.length) {
        if (++test.quietTicks < 8) return
        console.log("omalink private request runtime tests passed")
        Qt.quit()
        return
      }
      var mode = test.modes[test.sent]
      test.check(sender.start(test.request(test.exactBody, mode)), "valid request did not start")
      test.sent++
      test.check(sender.running, "start did not synchronously reserve sender")
      test.check(!sender.start(test.request("duplicate body", "duplicate")), "duplicate start was accepted")
      test.check(test.outcomes.length === test.sent - 1, "duplicate start emitted a misleading outcome")
    }
  }
}
