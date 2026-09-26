import QtQuick
import Quickshell.Io
import "PrivateText.js" as PrivateText

Item {
  id: root
  required property string helperPath
  property bool active: false
  readonly property bool running: active || worker.running
  property string pendingInput: ""
  property string response: ""
  property bool outputReady: false
  property bool exitReady: false
  property int exitCode: -1
  signal finished(var outcome)

  function start(request) {
    if (running) return false
    pendingInput = PrivateText.serialize(request)
    if (pendingInput === "") {
      finished({state:"not-submitted", code:"invalid_body", text:qsTr("Use between 1 and 8192 bytes of text without NUL characters")})
      return false
    }
    response = ""
    outputReady = false
    exitReady = false
    active = true
    worker.stdinEnabled = true
    worker.command = ["timeout", "--kill-after=1s", "25s", helperPath, "text-stdin"]
    worker.running = true
    deadline.restart()
    return true
  }

  // Closing a view can forget an unsent input without claiming to cancel a
  // request already written to the helper. No body is stored in the command.
  function forgetPayload() { pendingInput = "" }

  function finishIfReady() {
    if (!active || !outputReady || !exitReady) return
    active = false
    deadline.stop()
    pendingInput = ""
    var result = PrivateText.outcome(response, exitCode)
    response = ""
    finished(result)
  }

  Timer {
    id: deadline
    interval: 27000
    onTriggered: {
      if (!root.active) return
      root.active = false
      root.pendingInput = ""
      root.response = ""
      worker.running = false
      root.finished(PrivateText.outcome("", -1))
    }
  }
  Process {
    id: worker
    onStarted: {
      write(root.pendingInput)
      root.pendingInput = ""
      stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.response = text
        root.outputReady = true
        root.finishIfReady()
      }
    }
    onExited: function(code) {
      root.exitCode = code
      root.exitReady = true
      root.finishIfReady()
    }
  }
}
