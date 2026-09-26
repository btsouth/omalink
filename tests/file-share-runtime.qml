import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function next() { step++; ticks = 0 }
  FloatingWindow {
    visible: true
    implicitWidth: 440
    implicitHeight: 500
    color: "#171717"
    Plugin.FileShare {
      id: files
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 15 }
      deviceId: "old"
      deviceName: "Pixel"
      canShare: true
      useNativeDialog: false
    }
  }
  Timer {
    interval: 70
    running: true
    repeat: true
    onTriggered: {
      test.ticks++
      test.check(test.ticks < 80, "step timeout " + test.step)
      if (test.step === 0) {
        var moveOnly = {hasUrls:true, supportedActions:Qt.MoveAction, accepted:true, action:Qt.MoveAction}
        files.beginDrop(moveOnly)
        test.check(!moveOnly.accepted, "move-only drag accepted")
        var copy = {hasUrls:true, supportedActions:Qt.CopyAction | Qt.MoveAction, accepted:false, action:Qt.MoveAction}
        files.beginDrop(copy)
        test.check(copy.accepted && copy.action === Qt.CopyAction, "move proposal not overridden")
        var drop = {supportedActions:Qt.CopyAction | Qt.MoveAction, urls:["file:///tmp/a"], accepted:false, chosen:Qt.IgnoreAction,
          accept:function(action) { this.accepted = true; this.chosen = action }}
        files.finishDrop(drop)
        test.check(drop.accepted && drop.chosen === Qt.CopyAction && !files.sending, "drop did not remain a copy-only draft")
        files.invalidateSelection()
        files.beginDrop(copy)
        files.deviceId = "changedDuringDrag"
        drop.accepted = false
        drop.chosen = Qt.IgnoreAction
        files.finishDrop(drop)
        test.check(!drop.accepted && files.selectedPaths.length === 0, "stale drag routed to new phone")
        files.deviceId = "old"
        var oldRoute = files.route()
        files.deviceId = "new"
        files.deviceName = "Galaxy"
        test.check(!files.selectUrls(["file:///tmp/old"], oldRoute), "stale picker retargeted")
        files.deviceId = "old"
        test.check(!files.selectUrls(["file:///tmp/old"], oldRoute), "away/back accepted stale picker")
        files.deviceName = "Pixel"
        test.check(files.selectUrls(["file:///tmp/a%20%23%0A", "file:///tmp/b"], files.route()), "valid selection failed")
        test.check(files.selectedPaths.length === 2 && !files.sending, "selection dispatched automatically")
        files.removeFile(1)
        test.check(files.selectedPaths.length === 1, "remove failed")
        test.check(files.submit(), "submit failed")
        test.check(!files.submit(), "duplicate submit accepted")
        test.check(!files.selectUrls(["file:///tmp/extra"], files.route()), "inflight selection allowed")
        files.deviceId = "new"
        files.deviceName = "Galaxy"
        test.next()
      } else if (test.step === 1 && !files.sending) {
        test.check(files.statusState === "accepted", "success not accepted")
        test.check(files.statusDestinationName === "Pixel", "late completion relabeled")
        test.check(files.selectedPaths.length === 0, "old draft survived switch")
        test.check(!files.submit(), "accepted request could be resent")
        files.deviceId = "malformed"
        files.selectUrls(["file:///tmp/b"], files.route())
        files.submit()
        test.next()
      } else if (test.step === 2 && !files.sending) {
        test.check(files.statusState === "unconfirmed", "malformed output trusted")
        files.deviceId = "failure"
        files.selectUrls(["file:///tmp/b"], files.route())
        files.submit()
        test.next()
      } else if (test.step === 3 && !files.sending) {
        test.check(files.statusState === "failed", "preflight failure unrecognized")
        files.selectUrls(["file:///tmp/b"], files.route())
        files.canShare = false
        test.check(files.selectedPaths.length === 0 && !files.submit(), "offline draft could send")
        files.canShare = true
        files.openPicker()
        test.check(files.pickerRoute !== null, "picker route missing")
        files.deviceId = "other"
        test.check(files.pickerRoute === null && !files.pickerVisible, "picker survived phone switch")
        console.log("omalink file share runtime tests passed")
        Qt.quit()
      }
    }
  }
}
