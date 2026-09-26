import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.Commons
import "." as Plugin
ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  function check(condition,message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function next() { step++;ticks=0 }
  Plugin.BlueFerryService { id: service; panelOpen:true }
  PanelWindow {
    visible: Quickshell.env("OMALINK_PREVIEW") === "card"
    width: 380
    height: 450
    color: Color.popups.background
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      Plugin.BlueFerryCard { service:service; Layout.fillWidth:true }
      Item { Layout.fillHeight:true }
    }
  }
  Timer {
    interval:80; running:true; repeat:true
    onTriggered: {
      test.ticks++
      test.check(test.ticks<60,"step timed out " + test.step)
      if (test.step===0 && test.ticks>3) {
        test.check(!service.enabled && !service.refreshing && !service.canReadHistory,"not off by default")
        service.enabled=true
        test.next()
      } else if (test.step===1 && service.canReadHistory) {
        test.check(service.backendOwner===":1.10" && service.snapshot.connection==="ready","first route metadata wrong")
        if (Quickshell.env("OMALINK_PREVIEW") === "card") { stop(); return }
        service.enabled=false
        test.check(service.snapshot===null && !service.canReadHistory,"disable retained snapshot")
        service.panelOpen=false
        service.enabled=true
        test.next()
      } else if (test.step===2 && test.ticks>3) {
        test.check(!service.refreshing && service.snapshot===null,"closed panel queried backend")
        service.panelOpen=true
        test.next()
      } else if (test.step===3 && service.snapshot) {
        test.check(!service.canReadHistory && service.snapshot.storage==="locked" && service.backendOwner===":1.11","locked owner state wrong")
        test.check(service.storageText.indexOf("wallet")!==-1,"wallet guidance absent")
        service.refresh()
        test.next()
      } else if (test.step===4 && !service.refreshing && service.canReadHistory) {
        test.check(service.snapshot.connection==="offline","offline retained history disabled")
        service.refresh()
        test.next()
      } else if (test.step===5 && test.ticks>2) {
        test.check(service.refreshing,"slow status completed too early")
        service.enabled=false
        test.next()
      } else if (test.step===6 && test.ticks>12) {
        test.check(service.snapshot===null && !service.refreshing && service.backendOwner==="","late read survived disabling")
        console.log("BlueFerry service runtime tests passed")
        Qt.quit()
      }
    }
  }
}
