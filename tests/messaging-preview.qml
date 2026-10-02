import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "." as Plugin

// Synthetic data only. Interactive visual/keyboard fixture for omabox.
ShellRoot {
  id: fixture
  function messageWindow() {
    for (var i = 0; i < messages.data.length; i++) {
      if (messages.data[i].objectName === "messagesAppWindow") return messages.data[i]
    }
    return null
  }
  function findItem(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findItem(children[i], name)
      if (found) return found
    }
    return null
  }
  QtObject {
    id: fakeShell
    function updateEntryInline(id, value) { return true }
    property var barConfig: ({layout:{center:[{id:"omarchy.clock",format:"dddd HH:mm"}]}})
    property bool reject: false
    function summon(id, value) { return !reject && messages.open(value) }
  }
  QtObject {
    id: fakeBar
    property QtObject shell: fakeShell
    property color foreground: Color.foreground
    property color barForeground: Color.foreground
    property color urgent: Color.urgent
    property string fontFamily: Style.font.family
    property int height: 30
    property int barSize: 30
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property string position: "top"
    property var activePopout: false
    function requestPopout(item) { activePopout = item }
    function releasePopout(item) { activePopout = false }
    function hideTooltip(item) {}
  }
  PanelWindow {
    implicitWidth: 400; implicitHeight: 35
    anchors { top: true; left: true }
    Plugin.Panel {
      id: panel
      manageIpc: false
      bar: fakeBar
      settings: ({selectedDeviceId: "fixture", selectedDeviceName: "Test phone"})
    }
  }
  Plugin.Messages { id: messages; shell: fakeShell }
  IpcHandler {
    target: "omalink-review"
    function clockFormat(format: string): void {
      fakeShell.barConfig = {layout:{center:[{id:"omarchy.clock",format:format}]}}
    }
    function timestamp(): string {
      var item = fixture.findItem(fixture.messageWindow().contentItem, "messageTimestamp")
      return item ? item.text : ""
    }
    function ready(): string { return messages.messages.length > 0 ? "yes" : "no" }
    function session(): string {
      var window = fixture.messageWindow()
      return JSON.stringify({opened: messages.opened, draft: messages.replyText,
        generation: messages.generation, composing: messages.composing, followingLatest: messages.followingLatest,
        threadId: messages.selectedConversation ? messages.selectedConversation.threadId : null,
        composeBody:messages.composeText, recipient:messages.recipientQuery, savedCompose:messages.newMessageDraft,
        closePrompt:messages.closeConfirmationOpen, hasDrafts:messages.hasUnsentDrafts, rows: messages.messages.length, operations: messages.sendOperations.length,
        caches: Object.keys(messages.messageCache).length, drafts: Object.keys(messages.replyDrafts).length, wide: messages.wideLayout,
        visible: window ? window.visible : false, minimized: window ? window.minimized : false})
    }
    function choose(threadId: int): bool {
      messages.selectThread({threadId:threadId, names:[threadId === 7 ? "Alex" : "Maya"], addresses:["+1555000000" + threadId]})
      return messages.selectedConversation !== null && messages.selectedConversation.threadId === threadId
    }
    function compose(): void { messages.startCompose() }
    function composeDraft(number: string, body: string): void {
      messages.startCompose()
      messages.recipientQuery = number
      messages.recipientNumber = number
      messages.composeText = body
    }
    function requestClose(): void { messages.requestClose() }
    function keepEditing(): void { messages.keepEditing() }
    function discardDrafts(): void { messages.close() }
    function settings(): void { panel.showSettings = !panel.showSettings }

    function conversations(): void { messages.showConversations() }
    function older(): void {
      var list = fixture.findItem(fixture.messageWindow().contentItem, "messageHistoryList")
      messages.followingLatest = false
      list.positionViewAtBeginning()
    }
    function refresh(): void { messages.refresh() }
    function ui(): string {
      var window = fixture.messageWindow()
      var result = {}
      for (var name of ["replyComposer", "recipientInput", "messageHistoryList"]) {
        var item = fixture.findItem(window.contentItem, name)
        if (!item) continue
        var point = item.mapToItem(window.contentItem, 0, 0)
        result[name] = {x:point.x, y:point.y, width:item.width, height:item.height,
          focus:item.activeFocus, focusOnPress:item.activeFocusOnPress, focusPolicy:item.focusPolicy, visible:item.visible, enabled:item.enabled, contentY:item.contentY || 0,
          contentHeight:item.contentHeight || 0, originY:item.originY || 0, atYEnd:item.atYEnd || false}
      }
      return JSON.stringify(result)
    }
    function draft(text: string): void { messages.replyText = text }
    function summon(): bool { return messages.open('{"deviceId":"fixture","deviceName":"Test phone"}') }
    function summonThread(): bool { return messages.open('{"deviceId":"fixture","deviceName":"Test phone","threadId":7}') }
    function minimize(value: bool): void { fixture.messageWindow().minimized = value }
    function navigation(): string {
      return JSON.stringify({panelOpen: panel.opened, messagesOpen: messages.opened,
        threadId: messages.selectedConversation ? messages.selectedConversation.threadId : null,
        rows: messages.messages.length, entries: panel.messageEntries.length, error: messages.error,
        loading:messages.loading, readingHistory:messages.readingHistory,
        notificationOnly: panel.messageEntries.length > 0 && !!panel.messageEntries[0].notificationOnly})
    }
    function reject(value: bool): void { fakeShell.reject = value }
    function fallback(): void { messages.close(); panel.open(); panel.unreadRaw = [] }
    function activateRow(): bool {
      function find(item) {
        if (!item) return null
        if (item.objectName === "unreadContentList") return item
        var children = item.data || item.children || []
        for (var i = 0; i < children.length; i++) {
          var found = find(children[i])
          if (found) return found
        }
        if (item.contentItem) {
          if (item.contentItem.length !== undefined) {
            for (var c = 0; c < item.contentItem.length; c++) {
              var content = find(item.contentItem[c])
              if (content) return content
            }
          } else return find(item.contentItem)
        }
        return null
      }
      var list = find(panel)
      var row = list ? list.itemAtIndex(0) : null
      if (!row) return false
      row.open()
      return true
    }
    function clear(): void { panel.clearMessageEntries(panel.messageEntries) }
    function inbox(): void { messages.close(); panel.open() }
    function peekInbox(): void { panel.close(); panel.open() }
    function thread(): void { bootstrapPanel.stop(); panel.close(); messages.open('{"deviceId":"fixture","deviceName":"Test phone","threadId":7}') }
    function pending(): void {
      var operation = messages.prepareSend(messages.selectedConversation, "", "On my way!", true)
      if (operation) messages.finishSend(operation.id, {state:"accepted"})
    }
  }
  Timer { id: bootstrapPanel; interval: 800; running: true; onTriggered: if (!messages.opened) panel.open() }
}
