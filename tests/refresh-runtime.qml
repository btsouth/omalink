import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  property int events: 0
  property int statusRuns: 0
  property int baseline: 0
  function check(condition, message) {
    if (!condition) {
      console.error("FAIL: " + message)
      Qt.quit()
      throw new Error(message)
    }
  }
  Plugin.Service {
    id: phone
    settings: ({refreshIntervalSec: 300})
    onPhoneEvent: test.events++
    onRefreshingChanged: if (refreshing) test.statusRuns++
  }
  Plugin.Service { id: hidden; settings: ({refreshIntervalSec: 300, panelContent: "Hide"}) }
  Plugin.Service { id: quiet; settings: ({refreshIntervalSec: 300, notifyPopups: "Off"}) }
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      if (test.step === 0) {
        test.check(phone.notifyPopups === "sender", "message popups do not name the sender")
        test.check(hidden.notifyPopups === "on", "hidden panel content still names senders")
        test.check(quiet.notifyPopups === "off", "popups off was not passed on")
        test.check(!phone.refreshing && !phone.refreshQueued, "startup refreshes did not settle")
        // The second request arrives while the first read runs, as a
        // notification does, and must run afterwards instead of being dropped.
        test.baseline = test.statusRuns
        phone.refresh()
        phone.refresh()
        test.check(phone.refreshQueued, "a refresh during a read was not queued")
      } else if (test.step === 1) {
        test.check(test.statusRuns === test.baseline + 2, "queued refresh ran " + (test.statusRuns - test.baseline) + " reads")
        test.check(!phone.refreshing && !phone.refreshQueued, "a queued refresh was left behind")
      } else if (test.step === 3) {
        test.check(test.events === 1, "the watcher's notification was not signalled: " + test.events)
        console.log("omalink refresh runtime tests passed")
        Qt.quit()
      }
      test.step++
    }
  }
}
