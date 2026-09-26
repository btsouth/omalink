import QtQuick
import Quickshell.Io

// Read-only provider transport. The caller validates the provider envelope in
// result.data, including its domain status and the helper's exitCode.
Item {
  id: root
  required property string helperPath
  property var currentWorker: null
  readonly property bool running: currentWorker !== null
  signal finished(var result)

  function byteLength(value) {
    try { return encodeURIComponent(value).replace(/%[0-9A-F]{2}/g, "x").length }
    catch (_) { return Infinity }
  }
  function failure(code) {
    var messages = {
      invalid_request: "The provider request is invalid or too large",
      invalid_response: "The provider returned an invalid response",
      response_too_large: "The provider response exceeded the size limit",
      request_failed: "The provider request could not be completed",
      request_timeout: "The provider request timed out"
    }
    return {ok:false, code:code, text:messages[code]}
  }
  function start(request) {
    if (running) return false
    var input = ""
    try {
      if (request !== null && typeof request === "object" && !Array.isArray(request))
        input = JSON.stringify(request)
    } catch (_) {}
    if (typeof input !== "string" || input === "" || byteLength(input) > 65536) {
      finished(failure("invalid_request"))
      return false
    }
    // A custom toJSON must not turn an object request into a scalar or list.
    var serialized = JSON.parse(input)
    if (serialized === null || typeof serialized !== "object" || Array.isArray(serialized)) {
      finished(failure("invalid_request"))
      return false
    }
    var worker = workerFactory.createObject(root, {pendingInput:input})
    if (!worker) {
      finished(failure("request_failed"))
      return false
    }
    currentWorker = worker
    worker.launch()
    return true
  }
  function complete(worker, result) {
    if (currentWorker !== worker) return
    currentWorker = null
    worker.retire()
    finished(result)
  }
  function cancel() {
    var worker = currentWorker
    currentWorker = null
    if (worker) worker.retire()
  }
  Component.onDestruction: cancel()

  Component {
    id: collectorFactory
    StdioCollector {
      required property var owner
      waitForEnd: false
      onDataChanged: owner.receive(data.byteLength)
      onStreamFinished: owner.endOutput(text, data.byteLength)
    }
  }
  Component {
    id: workerFactory
    Item {
      id: worker
      property string pendingInput: ""
      property string response: ""
      property var collector: null
      property bool outputReady: false
      property bool exitReady: false
      property int exitCode: -1
      property bool crashed: false
      property double startedAt: 0
      property bool retired: false
      readonly property bool current: root.currentWorker === worker && !retired

      function launch() {
        collector = collectorFactory.createObject(worker, {owner:worker})
        process.stdout = collector
        process.stdinEnabled = true
        process.command = ["timeout", "--kill-after=1s", "25s", root.helperPath]
        startedAt = Date.now()
        process.running = true
        deadline.start()
      }
      function receive(bytes) {
        if (!current) return
        // QByteArray is exposed as ArrayBuffer. Count raw bytes while streaming,
        // without repeatedly decoding or retaining another copy of the payload.
        if (bytes > 2097152)
          root.complete(worker, root.failure("response_too_large"))
      }
      function endOutput(text, bytes) {
        if (!current) return
        receive(bytes)
        if (!current) return
        response = text
        outputReady = true
        finishIfReady()
      }
      function finishIfReady() {
        if (!current || !outputReady || !exitReady) return
        if (crashed || (exitCode !== 0 && exitCode !== 1)) {
          var timedOut = exitCode === 124 || exitCode === 137 || (crashed && Date.now() - startedAt >= 25000)
          root.complete(worker, root.failure(timedOut ? "request_timeout" : "request_failed"))
          return
        }
        var data = null
        try { data = JSON.parse(response) } catch (_) {}
        if (data === null || typeof data !== "object" || Array.isArray(data)) {
          root.complete(worker, root.failure("invalid_response"))
          return
        }
        root.complete(worker, {ok:true, data:data, exitCode:exitCode})
      }
      function retire() {
        if (retired) return
        retired = true
        pendingInput = ""
        response = ""
        deadline.stop()
        process.stdout = null
        if (collector) { collector.destroy(); collector = null }
        if (exitReady) { worker.destroy(); return }
        // Give GNU timeout time to forward TERM and enforce its one-second
        // kill deadline. A replacement gets a separate worker and collector.
        process.running = false
        reap.start()
      }
      Timer {
        id: deadline
        interval: 27000
        onTriggered: if (worker.current) root.complete(worker, root.failure("request_timeout"))
      }
      Timer {
        id: reap
        interval: 2000
        onTriggered: {
          if (process.running) process.signal(9)
          worker.destroy()
        }
      }
      Process {
        id: process
        onStarted: {
          if (worker.retired) { running = false; return }
          write(worker.pendingInput)
          worker.pendingInput = ""
          stdinEnabled = false
        }
        onExited: function(code, status) {
          worker.exitCode = code
          worker.crashed = status !== 0
          worker.exitReady = true
          if (worker.retired) { worker.destroy(); return }
          worker.finishIfReady()
        }
      }
    }
  }
}
