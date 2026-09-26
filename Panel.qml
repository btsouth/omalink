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
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: phone.connected ? foreground : dim
  readonly property bool notificationsReady: phone.canUseCapability(activePhoneId, "notifications") && !!phone.selectedDevice
  readonly property var activePhoneRules: phone.notifyRulesFor(activePhoneId)
  readonly property var notifications: notificationsReady && Array.isArray(phone.selectedDevice.notifications)
    ? NotificationPolicy.visibleNotifications(phone.selectedDevice.notifications, phone.notifySources, activePhoneRules) : []
  readonly property var notificationSources: notificationsReady
    ? NotificationPolicy.normalizeSources(phone.selectedDevice.notificationSources) : null
  readonly property var notificationAppRows: notificationsReady ? NotificationPolicy.appRows(notificationSources, activePhoneRules) : []
  readonly property var notificationSummary: NotificationPolicy.summaryLines(notificationSources, notifications.length,
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
    if (opened && messagesReady) { refreshSeen(); refreshUnread() }
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

  function openMessages(payload) {
    if (!messagesReady || !phone.selectedEndpoint) return
    payload.endpoint = phone.selectedEndpoint
    payload.deviceId = activePhoneId
    payload.deviceName = phone.selectedDeviceName
    root.close()
    bar.shell.summon("omalink.phone", JSON.stringify(payload))
  }

  Process {
    id: unreadProcess
    property string deviceId: ""
    property int generation: -1
    readonly property bool current: root.messagesReady && deviceId === root.activePhoneId && generation === root.selectionGeneration
    onExited: if (!current && root.opened) Qt.callLater(root.refreshUnread)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (unreadProcess.current) root.unreadRaw = Model.unreadConversations(Model.parseConversations(text))
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(480))

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
  
        PanelHero {
          Layout.fillWidth: true
          title: "OmaLink"
          meta: phone.actionStatus !== "" ? phone.actionStatus : phone.statusText
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: phone.connected ? 1.0 : 0.55
          iconComponent: Component {
            Text {
              text: "󰄜"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }
  
        BlueFerryCard {
          Layout.fillWidth: true
          visible: root.blueFerryEnabled
          service: blueFerry
          onOpenHistory: function(endpoint, backendOwner) { root.openBlueFerryHistory(endpoint, backendOwner) }
        }

        Text {
          visible: phone.statusReady && !phone.installed && !phone.statusFailed
          Layout.fillWidth: true
          text: "Install kdeconnect, jq and python-dbus, then open pairing to connect your phone."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
  
        Text {
          visible: phone.installed && !phone.statusFailed && phone.devices.length === 0 && root.activePhoneId === ""
          Layout.fillWidth: true
          text: qsTr("Open KDE Connect on your Android phone or iPhone, then open pairing. Keep the iPhone app open during setup. KDE Connect messaging requires Android. Optional BlueFerry history is available separately in widget settings.")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          visible: phone.installed && root.activePhoneId !== "" && !root.activePhoneReady
          Layout.fillWidth: true
          text: phone.setupText(phone.selectedDevice)
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Button {
          visible: phone.statusFailed || (root.activePhoneId !== "" && !root.activePhoneReady)
          text: qsTr("Refresh connection")
          enabled: !phone.refreshing
          focusable: true
          Accessible.role: Accessible.Button
          Accessible.name: text
          onClicked: phone.refresh()
        }
  
        Text {
          Layout.fillWidth: true
          text: phone.freshnessText + (phone.backendVersion !== "" ? " · KDE Connect " + phone.backendVersion : "")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Text {
          visible: phone.discoveryTruncated
          Layout.fillWidth: true
          text: qsTr("Showing up to 8 devices. Open Manage devices to see all devices.")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Repeater {
          model: phone.devices
  
          Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: deviceColumn.implicitHeight + Style.space(16)
            color: Style.selectedFillFor(root.foreground, Color.accent)
            radius: Style.cornerRadius
  
            ColumnLayout {
              id: deviceColumn
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(10)

              Button {
                Layout.fillWidth: true
                text: root.activePhoneId === modelData.id ? qsTr("Selected phone") : qsTr("Use this phone")
                selected: root.activePhoneId === modelData.id
                enabled: phone.canSelectDevice(modelData.id)
                focusable: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Use %1 for messages and notifications").arg(modelData.name)
                onClicked: root.selectDevice(modelData.id)
              }
  
              RowLayout {
                id: deviceRow
                Layout.fillWidth: true
                spacing: Style.space(8)
    
                Text {
                  text: "󰄜"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
    
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
    
                  Text {
                    text: modelData.name
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
    
                  Text {
                    text: phone.canUseDevice(modelData.id) ? Model.batteryText(modelData) : phone.connectionText(modelData)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
    
                  RowLayout {
                    visible: Model.connectivityText(modelData) !== "" || Model.signalStrength(modelData) >= 0
                    spacing: Style.space(5)
    
                    Text {
                      visible: text !== ""
                      text: Model.connectivityText(modelData)
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
    
                    SignalBars {
                      visible: strength >= 0
                      strength: Model.signalStrength(modelData)
                      activeColor: root.foreground
                    }
                  }
                }
    
                Button {
                  iconText: "󰅌"
                  tooltipText: phone.canUseCapability(modelData.id, "clipboard") ? qsTr("Send clipboard") : phone.capabilityText(modelData.id, "clipboard")
                  enabled: phone.canUseCapability(modelData.id, "clipboard")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: phone.sendClipboard(modelData.id)
                }
    
                Button {
                  iconText: "󰌷"
                  tooltipText: phone.canUseCapability(modelData.id, "sharing") ? qsTr("Send text or link") : phone.capabilityText(modelData.id, "sharing")
                  enabled: phone.canUseCapability(modelData.id, "sharing")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: {
                    root.shareDeviceId = modelData.id
                    root.shareDeviceName = modelData.name
                    shareField.text = ""
                    Qt.callLater(function() { shareField.forceActiveFocus() })
                  }
                }
    
                Button {
                  iconText: "󰏲"
                  tooltipText: phone.canUseCapability(modelData.id, "ring") ? qsTr("Ring phone") : phone.capabilityText(modelData.id, "ring")
                  enabled: phone.canUseCapability(modelData.id, "ring")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: phone.ring(modelData.id)
                }
              }
  
              Button {
                visible: root.activePhoneId === modelData.id
                text: root.showCapabilities ? qsTr("Hide phone setup") : qsTr("Phone setup and capabilities")
                focusable: true
                Accessible.role: Accessible.Button
                Accessible.name: text
                onClicked: root.showCapabilities = !root.showCapabilities
              }

              ColumnLayout {
                visible: root.activePhoneId === modelData.id && root.showCapabilities
                Layout.fillWidth: true
                spacing: Style.space(4)

                Text {
                  Layout.fillWidth: true
                  text: phone.setupText(modelData)
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }

                Repeater {
                  model: [{key: "messaging", label: qsTr("Messages")},
                    {key: "sharing", label: qsTr("Files, text and links")},
                    {key: "clipboard", label: qsTr("Clipboard")},
                    {key: "notifications", label: qsTr("Notifications")},
                    {key: "ring", label: qsTr("Ring")},
                    {key: "media", label: qsTr("Media controls")}]
                  Text {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.label + ": " + phone.capabilityText(root.activePhoneId, modelData.key)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }
                }
              }

            // Media controls for the phone's active player. The mprisremote
            // plugin emits no change signals, so this section advances from the
            // panel's regular polling (3s while open) rather than push events.
            // Compact by design: the header lives in the track-info column, and
            // the thin MediaBar sliders keep seek and volume to one line each.
            ColumnLayout {
              id: mediaSection
              visible: phone.mediaControls && Model.hasMedia(modelData)
              enabled: phone.canUseCapability(modelData.id, "media")
              Layout.fillWidth: true
              spacing: Style.space(4)

              // Never null: the bindings below evaluate even while this section
              // is hidden, which is what filled the journal with
              // "Cannot read property 'volume' of null".
              readonly property var media: Model.mediaState(modelData)
  
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)
  
                Item {
                  Layout.preferredWidth: Style.space(36)
                  Layout.preferredHeight: Style.space(36)

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

                  Text {
                    anchors.centerIn: parent
                    visible: parent.artSource === ""
                    text: "󰝚"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                  }
                }
  
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
  
                  Text {
                    Layout.fillWidth: true
                    text: "NOW PLAYING · " + mediaSection.media.player
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                    elide: Text.ElideRight
                  }
  
                  Text {
                    Layout.fillWidth: true
                    text: Model.mediaTitle(mediaSection.media)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }
  
                  Text {
                    visible: text !== ""
                    Layout.fillWidth: true
                    text: Model.mediaSubtitle(mediaSection.media)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
  
                PanelActionButton {
                  iconText: "󰒮"
                  tooltipText: "Previous track"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: phone.mediaAction(modelData.id, "Previous")
                }
  
                PanelActionButton {
                  iconText: mediaSection.media.isPlaying ? "󰏤" : "󰐊"
                  tooltipText: mediaSection.media.isPlaying ? "Pause" : "Play"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: phone.mediaAction(modelData.id, "PlayPause")
                }
  
                PanelActionButton {
                  iconText: "󰒭"
                  tooltipText: "Next track"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: phone.mediaAction(modelData.id, "Next")
                }
              }
  
              RowLayout {
                visible: mediaSection.media.canSeek && mediaSection.media.length > 0
                Layout.fillWidth: true
                spacing: Style.space(8)
  
                Text {
                  text: Model.mediaTime(mediaProgress.dragging ? mediaProgress.liveValue : mediaSection.media.position)
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
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
                  onReleased: function(v) { phone.mediaSeek(modelData.id, v) }
                }
  
                Text {
                  text: Model.mediaTime(mediaSection.media.length)
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
  
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)
  
                Text {
                  text: "󰕾"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
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
                  onReleased: function(v) { phone.mediaVolume(modelData.id, v) }
                }
  
                Text {
                  text: Math.round(mediaVolume.dragging ? mediaVolume.liveValue : mediaSection.media.volume) + "%"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
          }
        }

        RowLayout {
          visible: phone.installed || phone.devices.length > 0
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.space(8)

          Button {
            visible: phone.installed
            text: phone.devices.length === 0 ? "Open pairing" : "Manage devices"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: phone.openPairing()
          }

          Button {
            visible: phone.devices.length > 0
            iconText: "󰍩"
            text: "Messages"
            enabled: root.messagesReady
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Open messages for %1").arg(phone.selectedDeviceName)
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.openMessages({})
          }
        }

        Button {
          text: root.showFiles ? qsTr("Hide file sharing") : qsTr("Share files")
          visible: root.activePhoneId !== ""
          focusable: true
          Accessible.role: Accessible.Button
          Accessible.name: text
          onClicked: root.showFiles = !root.showFiles
        }

        FileShare {
          id: fileShare
          visible: root.showFiles
          Layout.fillWidth: true
          deviceId: phone.selectedDeviceId
          deviceName: phone.selectedDeviceName
          canShare: phone.canUseCapability(phone.selectedDeviceId, "sharing")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onRequestFinished: phone.refresh()
        }

        Button {
          text: root.showDiagnostics ? qsTr("Hide diagnostics") : qsTr("Connection diagnostics")
          focusable: true
          Accessible.role: Accessible.Button
          Accessible.name: text
          onClicked: {
            root.showDiagnostics = !root.showDiagnostics
            if (root.showDiagnostics) phone.loadDiagnostics()
          }
        }

        ColumnLayout {
          visible: root.showDiagnostics
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            Layout.fillWidth: true
            text: phone.diagnosticsStatus
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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
                border.color: root.dim
                radius: Style.cornerRadius
              }
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.WrapAnywhere
              color: root.foreground
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              Accessible.name: qsTr("Redacted connection diagnostics")
            }
          }
          Button {
            text: qsTr("Refresh diagnostics")
            enabled: !phone.diagnosticsBusy
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            onClicked: phone.loadDiagnostics()
          }
        }

        ColumnLayout {
          visible: root.shareDeviceId !== ""
          Layout.fillWidth: true
          spacing: Style.space(6)

          Text {
            text: "Send text or link to " + root.shareDeviceName
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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
              font.family: root.fontFamily
              onAccepted: if (text.trim() !== "" && !phone.actionBusy && phone.canUseCapability(root.shareDeviceId, "sharing")) {
                if (phone.shareText(root.shareDeviceId, text)) root.shareDeviceId = ""
              }
            }
  
            Button {
              text: "Send"
              enabled: shareField.text.trim() !== "" && !phone.actionBusy && phone.canUseCapability(root.shareDeviceId, "sharing")
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: {
                if (phone.shareText(root.shareDeviceId, shareField.text)) root.shareDeviceId = ""
              }
            }
  
            Button {
              text: "Cancel"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.shareDeviceId = ""
            }
          }
        }
  
        Text {
          visible: root.panelContentHidden
          Layout.fillWidth: true
          text: qsTr("Message previews and notification contents are hidden. Counts remain visible. Open Messages to read a conversation, or change Panel message content in widget settings.")
          wrapMode: Text.Wrap
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        RowLayout {
          visible: root.unreadConversations.length > 0
          Layout.fillWidth: true
  
          Text {
            Layout.fillWidth: true
            text: "UNREAD MESSAGES · " + root.unreadConversations.length
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }
  
          Button {
            text: "Clear"
            visible: !root.panelContentHidden
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.markSeenEntries(root.unreadConversations)
          }
        }
  
        ListView {
          objectName: "unreadContentList"
          visible: !root.panelContentHidden && root.unreadConversations.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, Style.space(150))
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.panelContentHidden ? [] : root.unreadConversations
  
          Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
  
          delegate: Rectangle {
            required property var modelData
            width: ListView.view.width
            implicitHeight: unreadRow.implicitHeight + Style.space(16)
            color: Style.selectedFillFor(root.foreground, Color.accent)
            radius: Style.cornerRadius
  
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.markSeenEntries([modelData])
                root.openMessages({ threadId: modelData.threadId })
              }
            }
  
            RowLayout {
              id: unreadRow
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(8)
  
              Text {
                text: "󰍩"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
  
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)
  
                Text {
                  Layout.fillWidth: true
                  text: Model.conversationTitle(modelData)
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
  
                Text {
                  visible: text !== ""
                  Layout.fillWidth: true
                  text: Model.previewText(modelData)
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
  
        RowLayout {
          visible: root.notificationSectionVisible
          Layout.fillWidth: true
  
          Text {
            Layout.fillWidth: true
            text: "PHONE NOTIFICATIONS · " + root.notifications.length
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }
  
          Button {
            text: "Clear all"
            visible: !root.panelContentHidden && root.notifications.length > 0
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: phone.dismissAllNotifications(root.activePhoneId)
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
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }
        }

        ListView {
          objectName: "notificationContentList"
          visible: !root.panelContentHidden && root.notifications.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, Style.space(190))
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.panelContentHidden ? [] : root.notifications
  
          Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
  
          delegate: Rectangle {
            required property var modelData
            width: ListView.view.width
            implicitHeight: notificationRow.implicitHeight + Style.space(16)
            color: Style.selectedFillFor(root.foreground, Color.accent)
            radius: Style.cornerRadius
  
            MouseArea {
              visible: modelData.isConversation
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openMessages({ conversationHint: modelData.title })
            }

          RowLayout {
            id: notificationRow
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Item {
              Layout.preferredWidth: Style.space(28)
              Layout.preferredHeight: Style.space(28)

              // The phone picks this icon, so it is only loaded as a verified
              // local file and only decoded at thumbnail size.
              readonly property string iconSource: Model.localImageSource(modelData.iconPath)

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
                text: "󰂚"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              Text {
                Layout.fillWidth: true
                text: modelData.appName
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                text: Model.notificationDisplayTitle(modelData)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                visible: text !== ""
                Layout.fillWidth: true
                text: Model.notificationDisplayText(modelData)
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }

            Button {
              visible: modelData.replyable
              text: "Reply"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                root.notifReplyId = modelData.replyId
                root.notifReplyDeviceId = root.activePhoneId
                root.notifReplyTitle = modelData.title !== "" ? modelData.title : modelData.appName
                notifReplyField.text = ""
                Qt.callLater(function() { notifReplyField.forceActiveFocus() })
              }
            }

            PanelActionButton {
              visible: modelData.dismissable
              iconText: "󰅖"
              tooltipText: "Dismiss on phone"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: phone.dismissNotification(root.activePhoneId, modelData.id)
            }
          }
        }
      }

      ColumnLayout {
        visible: !root.panelContentHidden && root.notifReplyId !== ""
        Layout.fillWidth: true
        spacing: Style.space(6)

        Text {
          text: "Reply to " + root.notifReplyTitle
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          TextField {
            id: notifReplyField
            objectName: "notificationReplyField"
            Layout.fillWidth: true
            placeholderText: "Reply"
            foreground: root.foreground
            font.family: root.fontFamily
            onAccepted: if (!root.panelContentHidden && text.trim() !== "" && !phone.actionBusy && phone.canUseCapability(root.notifReplyDeviceId, "notifications")) {
              if (phone.replyToNotification(root.notifReplyDeviceId, root.notifReplyId, text)) root.notifReplyId = ""
            }
          }

          Button {
            text: "Send"
            enabled: !root.panelContentHidden && notifReplyField.text.trim() !== "" && !phone.actionBusy && phone.canUseCapability(root.notifReplyDeviceId, "notifications")
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: {
              if (!root.panelContentHidden && phone.replyToNotification(root.notifReplyDeviceId, root.notifReplyId, notifReplyField.text)) root.notifReplyId = ""
            }
          }

          Button {
            text: "Cancel"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.notifReplyId = ""
          }
        }
      }

        Button {
          objectName: "notificationAppsButton"
          visible: !root.panelContentHidden && root.notificationSectionVisible
          text: root.showNotificationApps ? qsTr("Hide notification apps") : qsTr("Notification apps")
          focusable: true
          Accessible.role: Accessible.Button
          Accessible.name: text
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.showNotificationApps = !root.showNotificationApps
        }

        // App names are notification metadata, so the list follows Panel
        // message content. Its delegate model is emptied while hidden.
        ColumnLayout {
          objectName: "notificationAppList"
          visible: !root.panelContentHidden && root.showNotificationApps && root.notificationSectionVisible
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: qsTr("Apps in the phone's current notifications, from up to 100 checked. This is not a list of installed apps. Mute hides an app in OmaLink only: the panel, popups and Clear all. The phone and KDE Connect are unchanged.")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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
              spacing: Style.space(2)

              Text {
                Layout.fillWidth: true
                text: appRow.label
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                text: appRow.detail + " · " + appRow.status
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }

              ButtonGroup {
                id: ruleButtons
                options: [{value: "default", label: qsTr("Default"), tooltip: qsTr("Use the Notification sources setting")},
                  {value: "allow", label: qsTr("Allow"), tooltip: qsTr("Always list this app")},
                  {value: "mute", label: qsTr("Mute"), tooltip: qsTr("Hide this app in OmaLink")}]
                value: appRow.rule
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                Accessible.role: Accessible.Grouping
                Accessible.name: qsTr("Notification rule for %1").arg(appRow.label)
                onChanged: function(value) { root.setNotificationRule(appRow.key, value, appRow.label) }
              }
            }
          }

          Button {
            visible: Object.keys(root.activePhoneRules).length > 0
            text: qsTr("Reset app rules for this phone")
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.resetNotificationRules()
          }
        }

      }
    }
  }
}
