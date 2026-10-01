import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  readonly property bool preview: Quickshell.env("OMALINK_MFA_PREVIEW") === "1"

  Plugin.MfaPopup {
    id: popup
    onCopiedIdChanged: if (!test.preview && copiedId > 0) {
      console.log("omalink MFA copy runtime passed")
      Qt.quit()
    }
  }

  Timer {
    interval: 400
    running: true
    onTriggered: {
      popup.showCode("004219")
      if (popup.entries.length !== 1 || popup.entries[0].code !== "004219")
        throw new Error("MFA toast did not retain the code")
      if (!test.preview) copyTimer.start()
    }
  }

  Timer {
    id: copyTimer
    interval: 700
    onTriggered: popup.copyCode(popup.entries[0].id, popup.entries[0].code)
  }

  Timer {
    interval: test.preview ? 30000 : 5000
    running: true
    onTriggered: {
      if (!test.preview) console.error("FAIL: MFA copy did not complete")
      Qt.quit()
    }
  }
}
