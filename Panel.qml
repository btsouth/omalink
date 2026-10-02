import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "NotificationPolicy.js" as NotificationPolicy

Panel {
  id: root
  moduleName: "omalink.phone"
  // Per-screen target: with one bar per monitor, identical targets collide and
  // only one panel stays reachable, so popup clicks open the wrong monitor.
  readonly property var panelWindow: QsWindow.window
  readonly property string screenName: panelWindow && panelWindow.screen && panelWindow.screen.name
    ? String(panelWindow.screen.name) : ""
  ipcTarget: screenName !== "" ? "omalink.phone." + screenName : "omalink.phone"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color panelBackground: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
  readonly property color dim: mix(foreground, panelBackground, 0.72)
  readonly property color muted: mix(foreground, panelBackground, 0.8)
  readonly property string readingFontFamily: "Sans Serif"
  readonly property int bodySize: Math.max(15, Style.font.body)
  readonly property int labelSize: Math.max(13, Style.font.caption)
  property bool showSettings: false

  function mix(front, back, amount) {
    return Qt.rgba(front.r * amount + back.r * (1 - amount),
      front.g * amount + back.g * (1 - amount), front.b * amount + back.b * (1 - amount), 1)
  }

  function avatarText(conversation) {
    var title = Model.conversationTitle(conversation).trim()
    var words = title.split(/\s+/)
    return (words.length > 1 ? words[0].charAt(0) + words[words.length - 1].charAt(0) : title.slice(0, 2)).toUpperCase()
  }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: phone.connected ? foreground : dim
  readonly property bool notificationsReady: phone.canUseCapability(activePhoneId, "notifications") && !!phone.selectedDevice
  readonly property var activePhoneRules: phone.notifyRulesFor(activePhoneId)
  readonly property var phoneNotifications: notificationsReady && Array.isArray(phone.selectedDevice.notifications)
    ? NotificationPolicy.visibleNotifications(phone.selectedDevice.notifications, phone.notifySources, activePhoneRules) : []
  readonly property var inbox: messagesReady ? Model.messageInbox(unreadConversations, phoneNotifications)
    : {messages: unreadConversations, notifications: phoneNotifications}
  readonly property var messageEntries: inbox.messages
  readonly property var notifications: inbox.notifications
  readonly property var notificationSources: notificationsReady
    ? NotificationPolicy.normalizeSources(phone.selectedDevice.notificationSources) : null
  readonly property var notificationAppRows: notificationsReady ? NotificationPolicy.appRows(notificationSources, activePhoneRules) : []
  readonly property var notificationSummary: NotificationPolicy.summaryLines(notificationSources, phoneNotifications.length,
    !panelContentHidden && notifications.length > 0)
  readonly property bool notificationSectionVisible: notifications.length > 0 || notificationAppRows.length > 0
    || (notificationSources !== null && notificationSources.examined > 0)
  property bool showNotificationApps: false
  readonly property bool panelContentHidden: settings.panelContent !== undefined
    && String(settings.panelContent) !== "Show"
  onPanelContentHiddenChanged: {
    syncNotificationApps()
    if (panelContentHidden) {
      notifReplyId = ""
      notifReplyDeviceId = ""
      notifReplyTitle = ""
      if (notifReplyField) notifReplyField.text = ""
    }
  }
  property string shareDeviceId: ""
  property string shareDeviceName: ""
  property string notifReplyId: ""
  property string notifReplyTitle: ""
  property string notifReplyDeviceId: ""
  property var unreadRaw: []
  property var seenMap: ({})
  property int selectionGeneration: 0
  readonly property string activePhoneId: phone.selectedDeviceId
  readonly property bool activePhoneReady: phone.selectedDeviceReady
  readonly property bool messagesReady: phone.canUseCapability(activePhoneId, "messaging")
  property bool showDiagnostics: false
  property bool showCapabilities: false
  property bool showFiles: false
  readonly property bool blueFerryEnabled: String(settings.blueFerryHistory || "Off") === "On"
  // The phone list only matters when there is a choice to make.
  readonly property bool showPhoneList: phone.devices.length > 1
    || (phone.devices.length === 1 && phone.devices[0].id !== activePhoneId)
  readonly property string heroTitle: activePhoneId !== "" ? phone.selectedDeviceName : "OmaLink"
  readonly property string heroMeta: {
    if (!phone.statusReady) return qsTr("Checking…")
    if (phone.statusFailed) return qsTr("Status unavailable")
    if (!phone.installed) return qsTr("KDE Connect not installed")
    if (phone.stale) return qsTr("Status outdated")
    if (activePhoneId === "") return phone.devices.length > 0 ? qsTr("Choose a phone") : qsTr("No phone connected")
    var device = phone.selectedDevice
    if (!activePhoneReady || !device) return phone.connectionText(device)
    var parts = [qsTr("Connected")]
    if (device.battery && device.battery.charge !== null && device.battery.charge !== undefined)
      parts.push(Model.batteryText(device))
    if (Model.connectivityText(device) !== "") parts.push(Model.connectivityText(device))
    return parts.join(" · ")
  }

  function toggleShareText() {
    if (shareDeviceId !== "") {
      shareDeviceId = ""
      return
    }
    if (!phone.canUseCapability(activePhoneId, "sharing")) return
    showFiles = false
    shareDeviceId = activePhoneId
    shareDeviceName = phone.selectedDeviceName
    shareField.text = ""
    Qt.callLater(function() { shareField.forceActiveFocus() })
  }

  function toggleFiles() {
    showFiles = !showFiles
    if (showFiles) shareDeviceId = ""
  }

  function openBlueFerryHistory(endpoint, backendOwner) {
    if (!blueFerryEnabled || !blueFerry.canReadHistory || backendOwner !== blueFerry.backendOwner) return
    root.close()
    bar.shell.summon("omalink.phone", JSON.stringify({endpoint:endpoint, backendOwner:backendOwner,
      deviceName:"BlueFerry local history"}))
  }
  onMessagesReadyChanged: invalidatePhoneReads()
  onActivePhoneIdChanged: {
    shareDeviceId = ""
    shareDeviceName = ""
    notifReplyId = ""
    notifReplyDeviceId = ""
    notifReplyTitle = ""
    shareField.text = ""
    notifReplyField.text = ""
    invalidatePhoneReads()
  }
  onActivePhoneReadyChanged: invalidatePhoneReads()

  function invalidatePhoneReads() {
    selectionGeneration++
    unreadRaw = []
    seenMap = ({})
    if (opened && messagesReady) { refreshSeen(); refreshUnreadCached(); refreshUnread() }
  }

  // An undefined change removes that key from the saved entry.
  function persistEntry(changes, unsavedText) {
    var entry = {}
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var change in changes) {
      if (changes[change] === undefined) delete entry[change]
      else entry[change] = changes[change]
    }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      // The host returns false for a successful no-op too, not just a missing
      // entry. It does not expose a synchronous disk-write acknowledgement.
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    else
      phone.actionStatus = unsavedText
  }

  function persistSelection(deviceId, deviceName) {
    if (!Model.validDeviceId(deviceId)) return
    persistEntry({selectedDeviceId: deviceId, selectedDeviceName: String(deviceName).slice(0, 256)},
      qsTr("Phone selected for this session; could not save the preference."))
  }

  function persistNotificationRules(rules) {
    persistEntry({notifyAppRules: Object.keys(rules).length > 0 ? rules : undefined},
      qsTr("App rule applied for this session; could not save the preference."))
  }

  // Rules belong to the selected phone and only change what OmaLink shows.
  function setNotificationRule(key, state, label) {
    if (!Model.validDeviceId(activePhoneId)) return
    var rules = phone.notifyRulesWith(activePhoneId, key, state, label)
    if (rules === null) {
      phone.actionStatus = qsTr("Could not save this app rule. OmaLink keeps up to 100 app rules on up to 16 phones.")
      return
    }
    persistNotificationRules(rules)
  }

  // Rows are updated in place by key, so a rule change or a new notification
  // does not rebuild them and take keyboard focus away. App names are
  // notification metadata: the model is emptied while content is hidden.
  function syncNotificationApps() {
    var rows = panelContentHidden || !showNotificationApps ? [] : notificationAppRows
    for (var i = 0; i < rows.length; i++) {
      var row = {key: rows[i].key, label: rows[i].label, detail: NotificationPolicy.appRowDetail(rows[i]),
        status: NotificationPolicy.appRowStatus(rows[i]), rule: rows[i].state}
      var found = -1
      for (var j = i; j < notificationAppModel.count && found === -1; j++)
        if (notificationAppModel.get(j).key === row.key) found = j
      if (found === -1) notificationAppModel.insert(i, row)
      else {
        if (found !== i) notificationAppModel.move(found, i, 1)
        notificationAppModel.set(i, row)
      }
    }
    if (notificationAppModel.count > rows.length)
      notificationAppModel.remove(rows.length, notificationAppModel.count - rows.length)
  }
  onNotificationAppRowsChanged: syncNotificationApps()
  onShowNotificationAppsChanged: syncNotificationApps()

  ListModel { id: notificationAppModel }

  function resetNotificationRules() {
    if (Model.validDeviceId(activePhoneId)) persistNotificationRules(phone.notifyRulesWithout(activePhoneId))
  }

  function selectDevice(deviceId) {
    var device = Model.deviceById(phone.devices, deviceId)
    if (device && phone.canSelectDevice(deviceId)) persistSelection(device.id, device.name)
  }
  readonly property var unreadConversations: Model.filterUnseenUnread(unreadRaw, seenMap)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      phone.refresh()
      refreshSeen()
      refreshUnreadCached()
      refreshUnread()
    }
  }

  function refreshUnread() {
    if (!messagesReady || unreadProcess.running) return
    unreadProcess.deviceId = activePhoneId
    unreadProcess.generation = selectionGeneration
    unreadProcess.command = [phone.helperPath, "conversations", activePhoneId]
    unreadProcess.running = true
  }

  // KDE Connect's cached thread list, read without asking the phone. It keeps
  // unread messages current while the panel is closed, so opening it or
  // clicking a popup shows them at once.
  function refreshUnreadCached() {
    if (!messagesReady) return
    if (unreadCachedProcess.running) { unreadCachedQueued = true; return }
    unreadCachedQueued = false
    unreadCachedProcess.deviceId = activePhoneId
    unreadCachedProcess.generation = selectionGeneration
    unreadCachedProcess.command = [phone.helperPath, "conversations-cached", activePhoneId]
    unreadCachedProcess.running = true
  }

  property bool unreadCachedQueued: false

  // Both reads end by reading the daemon's cache, so whichever finishes last
  // has the newest list.
  function applyUnread(text) {
    unreadRaw = Model.unreadConversations(Model.parseConversations(text))
  }

  Connections {
    target: phone
    function onMessageEvent(deviceId) {
      if (deviceId === root.activePhoneId) root.refreshUnreadCached()
    }
    function onPhoneEvent() {
      root.refreshUnreadCached()
      // A text's notification can arrive just before the message itself.
      unreadFollowUp.restart()
    }
  }

  Timer {
    id: unreadFollowUp
    interval: 2000
    repeat: false
    onTriggered: root.refreshUnreadCached()
  }

  function refreshSeen() {
    if (!messagesReady || seenProcess.running) return
    seenProcess.deviceId = activePhoneId
    seenProcess.generation = selectionGeneration
    seenProcess.command = [phone.helperPath, "seen", activePhoneId]
    seenProcess.running = true
  }

  function markSeenEntries(conversations) {
    if (!messagesReady) return
    var args = [phone.helperPath, "mark-seen", activePhoneId]
    var updated = {}
    for (var key in seenMap) updated[key] = seenMap[key]
    var found = false
    for (var i = 0; i < conversations.length; i++) {
      var conversation = conversations[i]
      if (!conversation || conversation.threadId === null || conversation.threadId === undefined) continue
      var timestamp = Math.round(Number(conversation.timestamp) || 0)
      args.push(String(conversation.threadId))
      args.push(String(timestamp))
      updated[String(conversation.threadId)] = timestamp
      found = true
    }
    if (!found) return
    seenMap = updated
    Quickshell.execDetached(args)
  }

  function clearMessageEntries(entries) {
    markSeenEntries(entries)
    var ids = []
    entries.forEach(function(entry) { ids = ids.concat(entry.notificationIds || []) })
    phone.dismissNotifications(root.activePhoneId, ids)
  }

  function openMessages(payload) {
    if (!messagesReady || !phone.selectedEndpoint) return false
    payload.endpoint = phone.selectedEndpoint
    payload.deviceId = activePhoneId
    payload.deviceName = phone.selectedDeviceName
    if (!bar || !bar.shell || !bar.shell.summon("omalink.phone", JSON.stringify(payload))) {
      phone.actionStatus = qsTr("Could not open Messages. Please try again.")
      return false
    }
    root.close()
    return true
  }

  function openMessageEntry(entry) {
    if (!entry) return false
    return openMessages(entry.notificationOnly
      ? {conversationHint: Model.conversationTitle(entry)} : {threadId: entry.threadId})
  }

  Process {
    id: unreadProcess
    property string deviceId: ""
    property int generation: -1
    readonly property bool current: root.messagesReady && deviceId === root.activePhoneId && generation === root.selectionGeneration
    onExited: if (!current && root.opened) Qt.callLater(root.refreshUnread)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (unreadProcess.current) root.applyUnread(text)
    }
  }

  Process {
    id: unreadCachedProcess
    property string deviceId: ""
    property int generation: -1
    readonly property bool current: root.messagesReady && deviceId === root.activePhoneId && generation === root.selectionGeneration
    onExited: if (!current || root.unreadCachedQueued) Qt.callLater(root.refreshUnreadCached)
    stdout: StdioCollector {
      waitForEnd: true
      // A cold cache is empty, not proof that nothing is unread.
      onStreamFinished: if (unreadCachedProcess.current && Model.parseConversations(text).length > 0)
        root.applyUnread(text)
    }
  }

  Process {
    id: seenProcess
    property string deviceId: ""
    property int generation: -1
    readonly property bool current: root.messagesReady && deviceId === root.activePhoneId && generation === root.selectionGeneration
    onExited: if (!current && root.opened) Qt.callLater(root.refreshSeen)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (seenProcess.current) root.seenMap = Model.parseSeen(text)
    }
  }

  Timer {
    interval: 10000
    repeat: true
    running: root.opened
    onTriggered: root.refreshUnread()
  }

  Service {
    id: phone
    settings: root.settings
    panelOpen: root.opened
    onSelectionSuggested: function(deviceId, deviceName) { root.persistSelection(deviceId, deviceName) }
    onMfaCodeReceived: function(code) { if (phone.notifyPopups !== "off") mfaPopup.showCode(code) }
    onNotifyPopupsChanged: if (notifyPopups === "off" && mfaPopup) mfaPopup.clear()
  }

  MfaPopup {
    id: mfaPopup
    barPosition: root.bar ? root.bar.position : "top"
    barSize: root.bar ? root.bar.barSize : 0
  }

  BlueFerryService {
    id: blueFerry
    enabled: root.blueFerryEnabled
    panelOpen: root.opened
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄜"
    foreground: root.iconColor
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) phone.refresh()
      else root.toggle()
    }
  }

  Rectangle {
    visible: root.notifications.length > 0
    anchors.top: button.top
    anchors.right: button.right
    anchors.topMargin: Style.space(2)
    width: Style.space(6)
    height: width
    radius: width / 2
    color: Color.accent
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    // Let the native picker receive pointer and keyboard input above the layer panel.
    open: root.opened && !fileShare.pickerVisible
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(900))

    Controls.ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      contentWidth: availableWidth

      // The content outgrows the fitted height when the phone has many
      // notifications; scroll instead of clipping the bottom buttons.
      Binding {
        target: scrollArea.contentItem
        property: "interactive"
        value: content.implicitHeight > scrollArea.height
      }

      ColumnLayout {
        id: content
        width: scrollArea.availableWidth
        spacing: Style.space(12)

        // The selected phone is the subject of the panel, so it is the hero.
        Item {
          id: hero
          Layout.fillWidth: true
          implicitHeight: Math.max(Style.space(52), heroLabels.implicitHeight, ringButton.implicitHeight)

          Rectangle {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(50)
            height: width
            radius: Style.space(14)
            color: root.mix(Color.accent, root.panelBackground, 0.12)
            Text {
              anchors.centerIn: parent
              text: "󰄜"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(26)
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: ringButton.visible ? ringButton.left : parent.right
            anchors.rightMargin: ringButton.visible ? Style.space(12) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.heroTitle
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.readingFontFamily
              font.pixelSize: Math.max(22, Style.font.title)
              font.bold: true
              elide: Text.ElideRight
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                id: heroMetaText
                width: Math.min(implicitWidth, parent.width - (heroSignal.visible ? heroSignal.width + parent.spacing : 0))
                text: root.heroMeta
                textFormat: Text.PlainText
                color: root.muted
                font.family: root.readingFontFamily
                font.pixelSize: root.labelSize
                font.bold: false
                elide: Text.ElideRight
              }

              SignalBars {
                id: heroSignal
                visible: root.activePhoneReady && strength >= 0
                anchors.verticalCenter: heroMetaText.verticalCenter
                width: Style.space(14)
                height: Style.space(10)
                strength: Model.signalStrength(phone.selectedDevice)
                activeColor: root.muted
              }
            }
          }

          PanelActionButton {
            id: ringButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.activePhoneId !== "" && phone.installed
            iconText: "󰏲"
            tooltipText: enabled ? qsTr("Ring phone") : phone.capabilityText(root.activePhoneId, "ring")
            enabled: phone.canUseCapability(root.activePhoneId, "ring") && !phone.actionBusy
            focusable: true
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Ring %1").arg(phone.selectedDeviceName)
            onClicked: phone.ring(root.activePhoneId)
          }
        }

        Text {
          visible: phone.actionStatus !== ""
          Layout.fillWidth: true
          text: phone.actionStatus
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.readingFontFamily
          font.pixelSize: root.labelSize
          wrapMode: Text.Wrap
          Accessible.role: Accessible.StaticText
          Accessible.name: text
        }

        Text {
          visible: phone.statusReady && !phone.installed && !phone.statusFailed
          Layout.fillWidth: true
          text: qsTr("Install kdeconnect, jq and python-dbus, then open pairing to connect your phone.")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.readingFontFamily
          font.pixelSize: root.bodySize
          wrapMode: Text.Wrap
        }

        Text {
          visible: phone.installed && !phone.statusFailed && phone.devices.length === 0 && root.activePhoneId === ""
          Layout.fillWidth: true
          text: qsTr("Open KDE Connect on your Android phone or iPhone, then open pairing. Keep the iPhone app open during setup. KDE Connect messaging requires Android.")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.readingFontFamily
          font.pixelSize: root.bodySize
          wrapMode: Text.Wrap
        }

        Text {
          visible: phone.installed && root.activePhoneId !== "" && !root.activePhoneReady
          Layout.fillWidth: true
          text: phone.setupText(phone.selectedDevice)
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.readingFontFamily
          font.pixelSize: root.bodySize
          wrapMode: Text.Wrap
        }

        Button {
          visible: phone.statusFailed || (root.activePhoneId !== "" && !root.activePhoneReady)
          text: phone.refreshing ? qsTr("Refreshing…") : qsTr("Refresh connection")
          iconText: "󰑐"
          enabled: !phone.refreshing
          opacity: enabled ? 1.0 : 0.5
          bordered: true
          focusable: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.role: Accessible.Button
          Accessible.name: text
          onClicked: phone.refresh()
        }

        Button {
          visible: phone.installed && phone.devices.length === 0 && root.activePhoneId === ""
          text: qsTr("Open pairing")
          iconText: "󰌘"
          bordered: true
          focusable: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.role: Accessible.Button
          Accessible.name: text
          onClicked: phone.openPairing()
        }

        // Fixed-width wrapper: the cells size from the row width, so the grid's
        // own implicit width must not feed back into the column layout.
        Item {
          visible: root.activePhoneId !== "" && phone.installed
          Layout.fillWidth: true
          implicitHeight: actionGrid.implicitHeight

          Grid {
            id: actionGrid
            width: parent.width
            columns: 2
            spacing: Style.space(8)
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: actionGrid.cellWidth
              fontSize: root.labelSize
              verticalPadding: Style.space(10)
              iconText: "󰍩"
              text: root.messageEntries.length > 0 ? qsTr("Messages · %1").arg(root.messageEntries.length) : qsTr("Messages")
              tooltipText: root.messagesReady ? "" : phone.capabilityText(root.activePhoneId, "messaging")
              enabled: root.messagesReady
              opacity: enabled ? 1.0 : 0.5
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Open messages for %1").arg(phone.selectedDeviceName)
              onClicked: root.openMessages({})
            }

            Button {
              width: actionGrid.cellWidth
              fontSize: root.labelSize
              verticalPadding: Style.space(10)
              iconText: "󰅌"
              text: qsTr("Clipboard")
              tooltipText: enabled ? qsTr("Send the desktop clipboard to the phone") : phone.capabilityText(root.activePhoneId, "clipboard")
              enabled: phone.canUseCapability(root.activePhoneId, "clipboard") && !phone.actionBusy
              opacity: enabled ? 1.0 : 0.5
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Send clipboard to %1").arg(phone.selectedDeviceName)
              onClicked: phone.sendClipboard(root.activePhoneId)
            }

            Button {
              width: actionGrid.cellWidth
              fontSize: root.labelSize
              verticalPadding: Style.space(10)
              iconText: "󰌷"
              text: qsTr("Text or link")
              tooltipText: enabled ? "" : phone.capabilityText(root.activePhoneId, "sharing")
              selected: root.shareDeviceId !== ""
              enabled: root.shareDeviceId !== "" || phone.canUseCapability(root.activePhoneId, "sharing")
              opacity: enabled ? 1.0 : 0.5
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Send text or link to %1").arg(phone.selectedDeviceName)
              onClicked: root.toggleShareText()
            }

            Button {
              width: actionGrid.cellWidth
              fontSize: root.labelSize
              verticalPadding: Style.space(10)
              iconText: "󰈔"
              text: qsTr("Files")
              tooltipText: fileShare.canShare ? "" : phone.capabilityText(root.activePhoneId, "sharing")
              selected: root.showFiles
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Share files with %1").arg(phone.selectedDeviceName)
              onClicked: root.toggleFiles()
            }
          }
        }

        ColumnLayout {
          visible: root.shareDeviceId !== ""
          Layout.fillWidth: true
          spacing: Style.space(6)

          Text {
            Layout.fillWidth: true
            text: qsTr("To %1").arg(root.shareDeviceName)
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.readingFontFamily
            font.pixelSize: root.labelSize
            elide: Text.ElideRight
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
              id: shareField
              objectName: "shareTextField"
              Layout.fillWidth: true
              placeholderText: "Text or https://…"
              foreground: root.foreground
              font.family: root.readingFontFamily
              onAccepted: if (text.trim() !== "" && !phone.actionBusy && phone.canUseCapability(root.shareDeviceId, "sharing")) {
                if (phone.shareText(root.shareDeviceId, text)) root.shareDeviceId = ""
              }
            }

            Button {
              text: qsTr("Send")
              enabled: shareField.text.trim() !== "" && !phone.actionBusy && phone.canUseCapability(root.shareDeviceId, "sharing")
              opacity: enabled ? 1.0 : 0.5
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Send text to %1").arg(root.shareDeviceName)
              onClicked: {
                if (phone.shareText(root.shareDeviceId, shareField.text)) root.shareDeviceId = ""
              }
            }
          }
        }

        FileShare {
          id: fileShare
          visible: root.showFiles && root.activePhoneId !== ""
          Layout.fillWidth: true
          deviceId: phone.selectedDeviceId
          deviceName: phone.selectedDeviceName
          canShare: phone.canUseCapability(phone.selectedDeviceId, "sharing")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onRequestFinished: phone.refresh()
        }

        // Media controls for the selected phone's active player. The
        // mprisremote plugin emits no change signals, so this section advances
        // from the panel's regular polling (3s while open), not push events.
        ColumnLayout {
          id: mediaSection
          visible: phone.mediaControls && Model.hasMedia(phone.selectedDevice)
          enabled: phone.canUseCapability(root.activePhoneId, "media")
          Layout.fillWidth: true
          spacing: Style.space(8)

          // Never null: the bindings below evaluate even while this section
          // is hidden, which is what filled the journal with
          // "Cannot read property 'volume' of null".
          readonly property var media: Model.mediaState(phone.selectedDevice)

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          PanelSectionHeader {
            Layout.fillWidth: true
            text: mediaSection.media.player !== "" ? qsTr("NOW PLAYING · %1").arg(String(mediaSection.media.player).toUpperCase()) : qsTr("NOW PLAYING")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Math.max(12, Style.font.caption)
            elide: Text.ElideRight
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)

            Item {
              Layout.preferredWidth: Style.space(40)
              Layout.preferredHeight: Style.space(40)

              // Album art comes from the phone, so it is only loaded as a
              // verified local file and only decoded at thumbnail size.
              readonly property string artSource: Model.localImageSource(mediaSection.media.albumArt)

              Image {
                anchors.fill: parent
                visible: parent.artSource !== ""
                source: parent.artSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 128
                sourceSize.height: 128
              }

              Rectangle {
                anchors.fill: parent
                visible: parent.artSource === ""
                color: Style.hoverFillFor(root.foreground, Color.accent)
                radius: Style.cornerRadius

                Text {
                  anchors.centerIn: parent
                  text: "󰝚"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(1)

              Text {
                Layout.fillWidth: true
                text: Model.mediaTitle(mediaSection.media)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.readingFontFamily
                font.pixelSize: root.bodySize
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                visible: text !== ""
                Layout.fillWidth: true
                text: Model.mediaSubtitle(mediaSection.media)
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.readingFontFamily
                font.pixelSize: root.labelSize
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              iconText: "󰒮"
              tooltipText: qsTr("Previous track")
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: tooltipText
              onClicked: phone.mediaAction(root.activePhoneId, "Previous")
            }

            PanelActionButton {
              iconText: mediaSection.media.isPlaying ? "󰏤" : "󰐊"
              tooltipText: mediaSection.media.isPlaying ? qsTr("Pause") : qsTr("Play")
              focusable: true
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: tooltipText
              onClicked: phone.mediaAction(root.activePhoneId, "PlayPause")
            }

            PanelActionButton {
              iconText: "󰒭"
              tooltipText: qsTr("Next track")
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: tooltipText
              onClicked: phone.mediaAction(root.activePhoneId, "Next")
            }
          }

          RowLayout {
            visible: mediaSection.media.canSeek && mediaSection.media.length > 0
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              Layout.preferredWidth: Style.space(34)
              text: Model.mediaTime(mediaProgress.dragging ? mediaProgress.liveValue : mediaSection.media.position)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.readingFontFamily
              font.pixelSize: root.labelSize
            }

            MediaBar {
              id: mediaProgress
              Layout.fillWidth: true
              bar: root.bar
              minimum: 0
              maximum: Math.max(1000, mediaSection.media.length)
              step: 1000
              integer: true
              value: mediaSection.media.position
              onReleased: function(v) { phone.mediaSeek(root.activePhoneId, v) }
            }

            Text {
              Layout.preferredWidth: Style.space(34)
              horizontalAlignment: Text.AlignRight
              text: Model.mediaTime(mediaSection.media.length)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.readingFontFamily
              font.pixelSize: root.labelSize
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              Layout.preferredWidth: Style.space(34)
              text: "󰕾"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.bodySize
            }

            MediaBar {
              id: mediaVolume
              Layout.fillWidth: true
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: mediaSection.media.volume
              onReleased: function(v) { phone.mediaVolume(root.activePhoneId, v) }
            }

            Text {
              Layout.preferredWidth: Style.space(34)
              horizontalAlignment: Text.AlignRight
              text: Math.round(mediaVolume.dragging ? mediaVolume.liveValue : mediaSection.media.volume) + "%"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.readingFontFamily
              font.pixelSize: root.labelSize
            }
          }
        }

        ColumnLayout {
          visible: root.panelContentHidden && (root.messageEntries.length > 0 || root.notificationSectionVisible)
          Layout.fillWidth: true
          spacing: Style.space(8)

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          Text {
            Layout.fillWidth: true
            text: qsTr("Message previews and notification contents are hidden. Counts remain visible. Open Messages to read a conversation, or change Panel message content in widget settings.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.dim
            font.family: root.readingFontFamily
            font.pixelSize: root.labelSize
          }
        }

        ColumnLayout {
          visible: root.messageEntries.length > 0
          Layout.fillWidth: true
          spacing: Style.space(8)

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          RowLayout {
            Layout.fillWidth: true

            PanelSectionHeader {
              Layout.fillWidth: true
              text: qsTr("MESSAGES · %1").arg(root.messageEntries.length)
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Math.max(12, Style.font.caption)
            }

            Button {
              text: qsTr("Clear")
              enabled: !phone.actionBusy
              visible: !root.panelContentHidden
              focusable: true
              fontSize: Math.max(12, root.labelSize - 1)
              verticalPadding: Style.space(2)
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Clear messages in OmaLink and dismiss their phone notifications")
              onClicked: root.clearMessageEntries(root.messageEntries)
            }
          }

          ListView {
            objectName: "unreadContentList"
            visible: !root.panelContentHidden && root.messageEntries.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, Style.space(252))
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: root.panelContentHidden ? [] : root.messageEntries

            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

            delegate: CursorSurface {
              id: unreadItem
              required property var modelData
              width: ListView.view.width
              implicitHeight: Math.max(Style.space(76), unreadRow.implicitHeight + Style.space(20))
              hasCursor: unreadMouse.containsMouse || activeFocus
              foreground: root.foreground
              activeFocusOnTab: true
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Open conversation with %1").arg(Model.conversationTitle(modelData))
              Keys.onReturnPressed: open()
              Keys.onEnterPressed: open()
              Keys.onSpacePressed: open()

              function open() {
                root.openMessageEntry(modelData)
              }

              MouseArea {
                id: unreadMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: unreadItem.open()
              }

              RowLayout {
                id: unreadRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)

                Rectangle {
                  Layout.alignment: Qt.AlignVCenter
                  Layout.preferredWidth: Style.space(40)
                  Layout.preferredHeight: Style.space(40)
                  radius: Style.space(12)
                  color: root.mix(Color.accent, root.panelBackground, 0.12)
                  Text {
                    anchors.centerIn: parent
                    text: root.avatarText(unreadItem.modelData)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.readingFontFamily
                    font.pixelSize: root.bodySize
                    font.bold: true
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(8)

                    Text {
                      Layout.fillWidth: true
                      text: Model.conversationTitle(unreadItem.modelData)
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.readingFontFamily
                      font.pixelSize: root.bodySize
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      text: Model.relativeTime(unreadItem.modelData.timestamp, phone.clockNow)
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.readingFontFamily
                      font.pixelSize: root.labelSize
                    }
                  }

                  Text {
                    visible: text !== ""
                    Layout.fillWidth: true
                    text: Model.previewText(unreadItem.modelData)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.readingFontFamily
                    font.pixelSize: root.labelSize
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }

        ColumnLayout {
          visible: root.notifications.length > 0 || root.notificationSummary.length > 0
          Layout.fillWidth: true
          spacing: Style.space(8)

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          RowLayout {
            Layout.fillWidth: true

            PanelSectionHeader {
              Layout.fillWidth: true
              text: root.notifications.length > 0 ? qsTr("NOTIFICATIONS · %1").arg(root.notifications.length)
                : qsTr("NOTIFICATIONS")
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Math.max(12, Style.font.caption)
            }

            Button {
              text: qsTr("Clear all")
              visible: !root.panelContentHidden && root.notifications.length > 0
              focusable: true
              fontSize: Math.max(12, root.labelSize - 1)
              verticalPadding: Style.space(2)
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: qsTr("Dismiss all listed notifications on the phone")
              onClicked: phone.dismissAllNotifications(root.activePhoneId)
            }
          }

          ListView {
            objectName: "notificationContentList"
            visible: !root.panelContentHidden && root.notifications.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, Style.space(230))
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: root.panelContentHidden ? [] : root.notifications

            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

            delegate: CursorSurface {
              id: notificationItem
              required property var modelData
              width: ListView.view.width
              implicitHeight: notificationRow.implicitHeight + Style.space(20)
              hasCursor: notificationMouse.containsMouse || activeFocus
              foreground: root.foreground
              activeFocusOnTab: modelData.isConversation
              Accessible.role: modelData.isConversation ? Accessible.Button : Accessible.ListItem
              Accessible.name: modelData.appName + ": " + Model.notificationDisplayTitle(modelData)
              Keys.onReturnPressed: if (modelData.isConversation) open()
              Keys.onEnterPressed: if (modelData.isConversation) open()

              function open() { root.openMessages({ conversationHint: modelData.title }) }

              MouseArea {
                id: notificationMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: notificationItem.modelData.isConversation ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (notificationItem.modelData.isConversation) notificationItem.open()
              }

              RowLayout {
                id: notificationRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(4)
                spacing: Style.space(10)

                Item {
                  Layout.alignment: Qt.AlignTop
                  Layout.preferredWidth: Style.space(24)
                  Layout.preferredHeight: Style.space(24)

                  // The phone picks this icon, so it is only loaded as a verified
                  // local file and only decoded at thumbnail size.
                  readonly property string iconSource: Model.localImageSource(notificationItem.modelData.iconPath)

                  Image {
                    anchors.fill: parent
                    visible: parent.iconSource !== ""
                    source: parent.iconSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize.width: 96
                    sourceSize.height: 96
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: parent.iconSource === ""
                    text: notificationItem.modelData.isConversation ? "󰍩" : "󰂚"
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.readingFontFamily
                    font.pixelSize: Style.font.icon
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  Text {
                    Layout.fillWidth: true
                    text: notificationItem.modelData.appName
                    textFormat: Text.PlainText
                    color: root.muted
                    font.family: root.readingFontFamily
                    font.pixelSize: root.labelSize
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: Model.notificationDisplayTitle(notificationItem.modelData)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.readingFontFamily
                    font.pixelSize: root.bodySize
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: text !== ""
                    Layout.fillWidth: true
                    text: Model.notificationDisplayText(notificationItem.modelData)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.readingFontFamily
                    font.pixelSize: root.labelSize
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }
                }

                PanelActionButton {
                  Layout.alignment: Qt.AlignTop
                  visible: notificationItem.modelData.replyable
                  iconText: "󰑚"
                  tooltipText: qsTr("Reply")
                  focusable: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  Accessible.role: Accessible.Button
                  Accessible.name: qsTr("Reply to %1").arg(Model.notificationDisplayTitle(notificationItem.modelData))
                  onClicked: {
                    root.notifReplyId = notificationItem.modelData.replyId
                    root.notifReplyDeviceId = root.activePhoneId
                    root.notifReplyTitle = notificationItem.modelData.title !== "" ? notificationItem.modelData.title : notificationItem.modelData.appName
                    notifReplyField.text = ""
                    Qt.callLater(function() { notifReplyField.forceActiveFocus() })
                  }
                }

                PanelActionButton {
                  Layout.alignment: Qt.AlignTop
                  visible: notificationItem.modelData.dismissable
                  iconText: "󰅖"
                  tooltipText: qsTr("Dismiss on phone")
                  focusable: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  Accessible.role: Accessible.Button
                  Accessible.name: qsTr("Dismiss %1 on the phone").arg(Model.notificationDisplayTitle(notificationItem.modelData))
                  onClicked: phone.dismissNotification(root.activePhoneId, notificationItem.modelData.id)
                }
              }
            }
          }

          ColumnLayout {
            visible: !root.panelContentHidden && root.notifReplyId !== ""
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: qsTr("Reply to %1").arg(root.notifReplyTitle)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.readingFontFamily
              font.pixelSize: root.labelSize
              elide: Text.ElideRight
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              TextField {
                id: notifReplyField
                objectName: "notificationReplyField"
                Layout.fillWidth: true
                placeholderText: qsTr("Reply")
                foreground: root.foreground
                font.family: root.readingFontFamily
                onAccepted: if (!root.panelContentHidden && text.trim() !== "" && !phone.actionBusy && phone.canUseCapability(root.notifReplyDeviceId, "notifications")) {
                  if (phone.replyToNotification(root.notifReplyDeviceId, root.notifReplyId, text)) root.notifReplyId = ""
                }
              }

              Button {
                text: qsTr("Send")
                enabled: !root.panelContentHidden && notifReplyField.text.trim() !== "" && !phone.actionBusy && phone.canUseCapability(root.notifReplyDeviceId, "notifications")
                opacity: enabled ? 1.0 : 0.5
                bordered: true
                focusable: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  if (!root.panelContentHidden && phone.replyToNotification(root.notifReplyDeviceId, root.notifReplyId, notifReplyField.text)) root.notifReplyId = ""
                }
              }

              PanelActionButton {
                iconText: "󰅖"
                tooltipText: qsTr("Cancel reply")
                focusable: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                Accessible.role: Accessible.Button
                Accessible.name: tooltipText
                onClicked: root.notifReplyId = ""
              }
            }
          }

          Repeater {
            model: root.notificationSectionVisible ? root.notificationSummary : []

            Text {
              required property string modelData
              Layout.fillWidth: true
              text: modelData
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.readingFontFamily
              font.pixelSize: root.labelSize
              wrapMode: Text.Wrap
            }
          }


        }

        ColumnLayout {
          visible: root.blueFerryEnabled
          Layout.fillWidth: true
          spacing: Style.space(8)

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          BlueFerryCard {
            Layout.fillWidth: true
            service: blueFerry
            foreground: root.foreground
            fontFamily: root.fontFamily
            onOpenHistory: function(endpoint, backendOwner) { root.openBlueFerryHistory(endpoint, backendOwner) }
          }
        }

        ColumnLayout {
          visible: root.showPhoneList
          Layout.fillWidth: true
          spacing: Style.space(8)

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          PanelSectionHeader {
            text: qsTr("PHONES · %1").arg(phone.devices.length)
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Math.max(12, Style.font.caption)
          }

          Text {
            visible: phone.discoveryTruncated
            Layout.fillWidth: true
            text: qsTr("Showing up to 8 devices. Open Manage devices to see all devices.")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.readingFontFamily
            font.pixelSize: root.labelSize
            wrapMode: Text.Wrap
          }

          Repeater {
            model: root.showPhoneList ? phone.devices : []

            CursorSurface {
              id: phoneRow
              required property var modelData
              readonly property bool isSelected: root.activePhoneId === modelData.id
              Layout.fillWidth: true
              implicitHeight: phoneRowContent.implicitHeight + Style.space(12)
              hasCursor: phoneRowMouse.containsMouse && !isSelected
              current: isSelected
              foreground: root.foreground

              MouseArea {
                id: phoneRowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !phoneRow.isSelected && phone.canSelectDevice(phoneRow.modelData.id)
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.selectDevice(phoneRow.modelData.id)
              }

              RowLayout {
                id: phoneRowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)

                Text {
                  text: "󰄜"
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: phone.canUseDevice(phoneRow.modelData.id) ? 1.0 : 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  Text {
                    Layout.fillWidth: true
                    text: phoneRow.modelData.name
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.readingFontFamily
                    font.pixelSize: root.bodySize
                    font.bold: phoneRow.isSelected
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: phone.canUseDevice(phoneRow.modelData.id) ? Model.batteryText(phoneRow.modelData) : phone.connectionText(phoneRow.modelData)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.readingFontFamily
                    font.pixelSize: root.labelSize
                    elide: Text.ElideRight
                  }
                }

                Text {
                  visible: phoneRow.isSelected
                  text: qsTr("In use")
                  textFormat: Text.PlainText
                  color: root.muted
                  font.family: root.readingFontFamily
                  font.pixelSize: root.labelSize
                  font.bold: true
                }

                Button {
                  visible: !phoneRow.isSelected
                  text: qsTr("Use")
                  enabled: phone.canSelectDevice(phoneRow.modelData.id)
                  opacity: enabled ? 1.0 : 0.5
                  bordered: true
                  focusable: true
                  fontSize: root.labelSize
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  Accessible.role: Accessible.Button
                  Accessible.name: qsTr("Use %1 for messages and notifications").arg(phoneRow.modelData.name)
                  onClicked: root.selectDevice(phoneRow.modelData.id)
                }
              }
            }
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Button {
            Layout.fillWidth: true
            visible: phone.devices.length > 0 || root.activePhoneId !== ""
            iconText: "󰒓"
            text: qsTr("Manage devices")
            fontSize: root.labelSize
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: phone.openPairing()
          }
          Button {
            objectName: "phoneSettingsButton"
            Layout.fillWidth: true
            iconText: "󰒓"
            text: qsTr("Settings")
            selected: root.showSettings
            fontSize: root.labelSize
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            Accessible.role: Accessible.Button
            Accessible.name: root.showSettings ? qsTr("Hide phone settings") : qsTr("Show phone settings")
            onClicked: root.showSettings = !root.showSettings
          }
        }
        ColumnLayout {
          visible: root.showSettings
          Layout.fillWidth: true
          spacing: Style.space(8)
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)
            Button {
              visible: root.activePhoneId !== ""
              iconText: root.showCapabilities ? "󰅀" : "󰅂"
              text: qsTr("Setup")
              selected: root.showCapabilities
              fontSize: root.labelSize
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: root.showCapabilities ? qsTr("Hide phone setup") : qsTr("Phone setup and capabilities")
              onClicked: root.showCapabilities = !root.showCapabilities
            }

            Button {
              iconText: root.showDiagnostics ? "󰅀" : "󰅂"
              text: qsTr("Diagnostics")
              selected: root.showDiagnostics
              fontSize: root.labelSize
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: root.showDiagnostics ? qsTr("Hide diagnostics") : qsTr("Connection diagnostics")
              onClicked: {
                root.showDiagnostics = !root.showDiagnostics
                if (root.showDiagnostics) phone.loadDiagnostics()
              }
            }
          }
          Button {
            objectName: "notificationAppsButton"
            visible: !root.panelContentHidden && root.notificationSectionVisible
            Layout.fillWidth: true
            leftAlign: true
            iconText: root.showNotificationApps ? "󰅀" : "󰅂"
            text: qsTr("Notification apps")
            fontSize: root.labelSize
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            Accessible.role: Accessible.Button
            Accessible.name: root.showNotificationApps ? qsTr("Hide notification apps") : qsTr("Show notification apps")
            onClicked: root.showNotificationApps = !root.showNotificationApps
          }

          // App names are notification metadata, so the list follows Panel
          // message content. Its delegate model is emptied while hidden.
          ColumnLayout {
            objectName: "notificationAppList"
            visible: !root.panelContentHidden && root.showNotificationApps && root.notificationSectionVisible
            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
              Layout.fillWidth: true
              text: qsTr("Apps in the phone's current notifications, from up to 100 checked. This is not a list of installed apps. Mute hides an app in OmaLink only: the panel, popups and Clear all. The phone and KDE Connect are unchanged.")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.readingFontFamily
              font.pixelSize: root.labelSize
              wrapMode: Text.Wrap
            }

            Repeater {
              id: notificationAppRepeater
              objectName: "notificationAppRepeater"
              model: notificationAppModel

              ColumnLayout {
                id: appRow
                required property string key
                required property string label
                required property string detail
                required property string status
                required property string rule
                readonly property Item ruleGroup: ruleButtons
                Layout.fillWidth: true
                spacing: Style.space(4)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    Layout.fillWidth: true
                    text: appRow.label
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.readingFontFamily
                    font.pixelSize: root.bodySize
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  ButtonGroup {
                    id: ruleButtons
                    options: [{value: "default", label: qsTr("Default"), tooltip: qsTr("Use the Notification sources setting")},
                      {value: "allow", label: qsTr("Allow"), tooltip: qsTr("Always list this app")},
                      {value: "mute", label: qsTr("Mute"), tooltip: qsTr("Hide this app in OmaLink")}]
                    value: appRow.rule
                    spacing: Style.space(4)
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Math.max(12, root.labelSize - 1)
                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Notification rule for %1").arg(appRow.label)
                    onChanged: function(value) { root.setNotificationRule(appRow.key, value, appRow.label) }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: appRow.detail + " · " + appRow.status
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.readingFontFamily
                  font.pixelSize: root.labelSize
                  wrapMode: Text.Wrap
                }
              }
            }

            Button {
              visible: Object.keys(root.activePhoneRules).length > 0
              text: qsTr("Reset app rules for this phone")
              bordered: true
              focusable: true
              fontSize: root.labelSize
              Accessible.role: Accessible.Button
              Accessible.name: text
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.resetNotificationRules()
            }
          }
        }

        ColumnLayout {
          visible: root.showSettings && root.activePhoneId !== "" && root.showCapabilities
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: phone.setupText(phone.selectedDevice)
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.readingFontFamily
            font.pixelSize: root.labelSize
            wrapMode: Text.Wrap
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(4)

            Repeater {
              model: [{key: "messaging", label: qsTr("Messages")},
                {key: "sharing", label: qsTr("Files, text and links")},
                {key: "clipboard", label: qsTr("Clipboard")},
                {key: "notifications", label: qsTr("Notifications")},
                {key: "ring", label: qsTr("Ring")},
                {key: "media", label: qsTr("Media controls")}]

              Text {
                required property var modelData
                required property int index
                Layout.row: index
                Layout.column: 0
                text: modelData.label
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.readingFontFamily
                font.pixelSize: root.labelSize
              }
            }

            Repeater {
              model: ["messaging", "sharing", "clipboard", "notifications", "ring", "media"]

              Text {
                required property string modelData
                required property int index
                Layout.row: index
                Layout.column: 1
                Layout.fillWidth: true
                text: phone.capabilityText(root.activePhoneId, modelData)
                textFormat: Text.PlainText
                color: phone.canUseCapability(root.activePhoneId, modelData) ? root.dim : root.foreground
                font.family: root.readingFontFamily
                font.pixelSize: root.labelSize
                wrapMode: Text.Wrap
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: phone.freshnessText + (phone.backendVersion !== "" ? " · KDE Connect " + phone.backendVersion : "")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.readingFontFamily
            font.pixelSize: root.labelSize
            wrapMode: Text.Wrap
          }
        }

        ColumnLayout {
          visible: root.showSettings && root.showDiagnostics
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: phone.diagnosticsStatus
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.readingFontFamily
            font.pixelSize: root.labelSize
            wrapMode: Text.Wrap
          }

          Controls.ScrollView {
            id: diagnosticsScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(160)
            contentWidth: availableWidth
            visible: phone.diagnosticsText !== ""
            clip: true

            Controls.TextArea {
              width: diagnosticsScroll.availableWidth
              text: phone.diagnosticsText
              readOnly: true
              selectByMouse: true
              selectionColor: Color.accent
              selectedTextColor: Color.background
              background: Rectangle {
                color: Color.background
                border.color: Style.normalBorderFor(root.foreground, Color.accent)
                radius: Style.cornerRadius
              }
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.WrapAnywhere
              color: root.foreground
              font.family: "monospace"
              font.pixelSize: root.labelSize
              Accessible.name: qsTr("Redacted connection diagnostics")
            }
          }

          Button {
            text: qsTr("Refresh diagnostics")
            iconText: "󰑐"
            enabled: !phone.diagnosticsBusy
            opacity: enabled ? 1.0 : 0.5
            bordered: true
            focusable: true
            fontSize: root.labelSize
            foreground: root.foreground
            fontFamily: root.fontFamily
            Accessible.role: Accessible.Button
            Accessible.name: text
            onClicked: phone.loadDiagnostics()
          }
        }
      }
    }
  }
}
