import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int sent: 0
  property int ticks: 0
  property int quietTicks: 0
  property int phase: 0
  property var outcomes: []
  readonly property string exactBody: "  private provider fixture\ntext 😀 café  "
  readonly property var modes: ["accepted", "rejected", "malformed", "array", "wrongexit", "large", "unicodeLarge", "timeout"]
  readonly property var expected: ["accepted", "rejected", "invalid_response", "invalid_response", "request_failed", "response_too_large", "response_too_large", "request_timeout"]

  function check(condition, message) {
    if (!condition) {
      console.error("FAIL: " + message)
      Qt.quit()
      throw new Error(message)
    }
  }
  function request(mode) { return {version:1, operation:mode, body:exactBody} }
  function code(result) { return result.ok ? result.data.mode : result.code }
  Plugin.ProviderRequest {
    id: sender
    helperPath: Qt.resolvedUrl("bin/provider").toString().replace(/^file:\/\//, "")
    onFinished: function(result) { test.outcomes = test.outcomes.concat([result]) }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      test.check(++test.ticks < 1000, "provider request timed out")
      if (test.phase === 0) {
        for (var request of [null, [], "body", {toJSON:function() { return [] }}, {body:"😀".repeat(17000)}]) {
          test.check(!sender.start(request), "invalid request started a helper")
          test.check(!sender.running, "invalid request left sender busy")
          test.check(test.outcomes[test.outcomes.length - 1].code === "invalid_request", "invalid request classification")
        }
        test.check(test.outcomes.length === 5, "invalid requests emitted repeated completion")
        test.outcomes = []
        test.phase = 1
      }
      if (test.phase === 1) {
        test.check(test.outcomes.length <= test.sent, "unexpected completion")
        if (test.outcomes.length < test.sent || sender.running) return
        if (test.sent > 0) {
          test.check(test.code(test.outcomes[test.sent - 1]) === test.expected[test.sent - 1], "wrong result for " + test.modes[test.sent - 1])
          if (test.sent === 2) test.check(test.outcomes[1].exitCode === 1, "provider error envelope lost exit code")
        }
        if (test.sent < test.modes.length) {
          test.check(sender.start(test.request(test.modes[test.sent])), "valid request did not start")
          test.sent++
          test.check(sender.running, "start did not synchronously reserve sender")
          test.check(!sender.start(test.request("duplicate")), "duplicate start was accepted")
          return
        }
        test.check(sender.start(test.request("cancel")), "cancel fixture did not start")
        test.phase = 2
      } else if (test.phase === 2) {
        // Wait for actual helper output before cancelling a live process.
        if (!sender.currentWorker.collector || sender.currentWorker.collector.text.indexOf("cancel") === -1) return
        sender.cancel()
        test.check(!sender.running && sender.currentWorker === null, "cancel retained current request")
        test.check(sender.start(test.request("replacement")), "cancel prevented immediate replacement")
        test.phase = 3
      } else if (test.phase === 3) {
        if (sender.running) return
        test.check(test.outcomes.length === 9, "cancelled request emitted a stale result")
        test.check(test.outcomes[8].ok && test.outcomes[8].data.mode === "replacement", "replacement got cancelled data")
        test.phase = 4
      } else if (test.phase === 4) {
        test.check(test.outcomes.length === 9, "late cancelled completion or retry")
        if (++test.quietTicks < 30) return
        console.log("omalink provider request runtime tests passed")
        Qt.quit()
      }
    }
  }
}
