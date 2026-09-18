import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omalink.phone"
  // Per-screen target: with one bar per monitor, identical targets collide and
  // only one panel stays reachable — popup clicks then open the wrong monitor.
  readonly property var panelWindow: QsWindow.window
  readonly property string screenName: panelWindow && panelWindow.screen && panelWindow.screen.name
    ? String(panelWindow.screen.name) : ""
  ipcTarget: screenName !== "" ? "omalink.phone." + screenName : "omalink.phone"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: phone.connected ? foreground : dim
  readonly property var notifications: phone.devices.length > 0 && Array.isArray(phone.devices[0].notifications)
    ? Model.visibleNotifications(phone.devices[0].notifications, phone.notifySources) : []
  property string shareDeviceId: ""
  property string shareDeviceName: ""
  property string notifReplyId: ""
  property string notifReplyTitle: ""
  property var unreadRaw: []
  property var seenMap: ({})
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
    if (phone.devices.length === 0 || unreadProcess.running) return
    unreadProcess.command = [phone.helperPath, "conversations", phone.devices[0].id]
    unreadProcess.running = true
  }

  function refreshSeen() {
    if (seenProcess.running) return
    seenProcess.command = [phone.helperPath, "seen"]
    seenProcess.running = true
  }

  function markSeenEntries(conversations) {
    var args = [phone.helperPath, "mark-seen"]
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
    payload.deviceId = phone.devices[0].id
    root.close()
    bar.shell.summon("omalink.phone", JSON.stringify(payload))
  }

  Process {
    id: unreadProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.unreadRaw = Model.unreadConversations(Model.parseConversations(text))
    }
  }

  Process {
    id: seenProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.seenMap = Model.parseSeen(text)
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
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(480))

    Controls.ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true

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
  
        Text {
          visible: !phone.installed
          Layout.fillWidth: true
          text: "KDE Connect is required. Installation will be part of the guided OmaLink setup."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
  
        Text {
          visible: phone.installed && phone.devices.length === 0
          Layout.fillWidth: true
          text: "Open pairing, then approve this computer in the KDE Connect app on your Android phone."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
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
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
    
                  Text {
                    text: Model.batteryText(modelData)
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
                  tooltipText: "Send clipboard"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: phone.sendClipboard(modelData.id)
                }
    
                Button {
                  iconText: "󰌷"
                  tooltipText: "Send text or link"
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
                  tooltipText: "Ring phone"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: phone.ring(modelData.id)
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
                    text: "NOW PLAYING · " + media.player
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
                    text: Model.mediaTitle(media)
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
                    text: Model.mediaSubtitle(media)
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
                  iconText: media.isPlaying ? "󰏤" : "󰐊"
                  tooltipText: media.isPlaying ? "Pause" : "Play"
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
                visible: media.canSeek && media.length > 0
                Layout.fillWidth: true
                spacing: Style.space(8)
  
                Text {
                  text: Model.mediaTime(mediaProgress.dragging ? mediaProgress.liveValue : media.position)
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
                  maximum: Math.max(1000, media.length)
                  step: 1000
                  integer: true
                  value: media.position
                  onReleased: function(v) { phone.mediaSeek(modelData.id, v) }
                }
  
                Text {
                  text: Model.mediaTime(media.length)
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
                  value: media.volume
                  onReleased: function(v) { phone.mediaVolume(modelData.id, v) }
                }
  
                Text {
                  text: Math.round(mediaVolume.dragging ? mediaVolume.liveValue : media.volume) + "%"
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
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.openMessages({})
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
              Layout.fillWidth: true
              placeholderText: "Text or https://…"
              foreground: root.foreground
              font.family: root.fontFamily
              onAccepted: if (text.trim() !== "") {
                phone.shareText(root.shareDeviceId, text.trim())
                root.shareDeviceId = ""
              }
            }
  
            Button {
              text: "Send"
              enabled: shareField.text.trim() !== ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: {
                phone.shareText(root.shareDeviceId, shareField.text.trim())
                root.shareDeviceId = ""
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
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.markSeenEntries(root.unreadConversations)
          }
        }
  
        ListView {
          visible: root.unreadConversations.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, Style.space(150))
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.unreadConversations
  
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
          visible: root.notifications.length > 0
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
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: phone.dismissAllNotifications(phone.devices[0].id)
          }
        }
  
        ListView {
          visible: root.notifications.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, Style.space(190))
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.notifications
  
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
              onClicked: phone.dismissNotification(phone.devices[0].id, modelData.id)
            }
          }
        }
      }

      ColumnLayout {
        visible: root.notifReplyId !== ""
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
            Layout.fillWidth: true
            placeholderText: "Reply"
            foreground: root.foreground
            font.family: root.fontFamily
            onAccepted: if (text.trim() !== "") {
              phone.replyToNotification(phone.devices[0].id, root.notifReplyId, text.trim())
              root.notifReplyId = ""
            }
          }

          Button {
            text: "Send"
            enabled: notifReplyField.text.trim() !== ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: {
              phone.replyToNotification(phone.devices[0].id, root.notifReplyId, notifReplyField.text.trim())
              root.notifReplyId = ""
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

      }
    }
  }
}
