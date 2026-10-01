import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "ProviderModel.js" as Providers
import "BlueFerryModel.js" as BlueFerry
import "SendState.js" as SendState
import "PrivateText.js" as PrivateText

Item {
  id: root

  // The shell injects its public, reactive bar settings into overlay plugins.
  property var shell: null
  readonly property bool blueFerryEnabled: BlueFerry.enabledInBar(shell ? shell.barConfig : null)
  onBlueFerryEnabledChanged: if (!blueFerryEnabled && readOnlyProvider) close()
  property bool opened: false
  onOpenedChanged: messagesWindow.visible = opened
  property int generation: 0
  property var endpoint: null
  readonly property string endpointKey: Providers.endpointKey(endpoint)
  readonly property string deviceId: endpoint ? endpoint.deviceId : ""
  property string deviceName: ""
  property string backendOwner: ""
  readonly property bool readOnlyProvider: endpoint !== null && endpoint.provider === "blueferry"
  property bool providerInvalidated: false
  property bool browsingContacts: false
  property string contactsError: ""
  readonly property var visibleProviderContacts: searchText.trim() === "" ? contacts : Model.filterContacts(contacts, searchText)
  property var conversations: []
  property var contacts: []
  property var selectedConversation: null
  property bool composing: false
  property string recipientQuery: ""
  property string recipientNumber: ""
  property string pendingNewBody: ""
  property var historyConversations: []
  property var sendOperations: []
  property int nextSendId: 0
  property int sendConfirmationTimeoutMs: 30000
  property int sendReconcileIntervalMs: 1800
  readonly property var latestSend: sendOperations.length ? sendOperations[sendOperations.length - 1] : null
  property alias replyText: replyField.text
  property alias composeText: composeMessage.text
  property var messages: []
  property var messageCache: ({})
  property var cacheOrder: []
  property string loadingThreadId: ""
  property bool sending: false
  property string pendingReply: ""
  property string pendingThreadId: ""
  property string searchText: ""
  property string pendingOpenTitle: ""
  property string pendingOpenThreadId: ""
  property bool loading: false
  // The generation whose thread list came from a full conversations read.
  property int conversationsAppliedGeneration: -1
  property string error: ""
  property var attachmentPaths: ({})
  property string attachmentFetchUnique: ""
  property string attachmentFetchMode: ""
  property bool viewerOpen: false
  property string viewerPath: ""
  property string viewerStatus: ""
  property double nowMs: Date.now()
  property bool followingLatest: true
  property bool eventReadQueued: false
  property bool cachedReadIsEvent: false
  property bool historyEventPending: false

  readonly property var filteredConversations: Model.filterConversations(conversations, searchText)
  readonly property var filteredContacts: Model.filterContacts(contacts, recipientQuery).slice(0, 8)

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helperPath: pluginDir + "/bin/omalink"
  readonly property color foreground: Color.foreground
  readonly property color windowBackground: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
  readonly property color dim: blend(foreground, windowBackground, 0.72)
  readonly property color separator: blend(foreground, windowBackground, 0.13)
  readonly property color sidebarBackground: blend(foreground, windowBackground, 0.035)
  readonly property color incomingBackground: blend(foreground, windowBackground, 0.07)
  readonly property color outgoingBackground: blend(Color.accent, windowBackground, 0.15)
  readonly property string readingFontFamily: "Sans Serif"
  readonly property int bodySize: Math.max(16, Style.font.body)
  readonly property int labelSize: Math.max(13, Style.font.caption)
  readonly property bool compactHeight: messagesWindow.height < Style.space(600)
  readonly property bool wideLayout: messagesWindow.width >= Style.space(900)
  property var replyDrafts: ({})
  property var draftOrder: []

  function blend(front, back, amount) {
    return Qt.rgba(front.r * amount + back.r * (1 - amount),
      front.g * amount + back.g * (1 - amount), front.b * amount + back.b * (1 - amount), 1)
  }

  function initials(conversation) {
    var title = Model.conversationTitle(conversation || {}).trim()
    var words = title.split(/\s+/)
    return (words.length > 1 ? words[0].charAt(0) + words[words.length - 1].charAt(0) : title.slice(0, 2)).toUpperCase()
  }

  function draftKey(conversation) {
    if (!conversation) return ""
    return conversation.threadId === null || conversation.threadId === undefined
      ? (conversation.localOperationId ? endpointKey + "/draft/" + conversation.localOperationId : "")
      : threadCacheKey(conversation.threadId)
  }

  // Navigation retains at most five drafts in this endpoint's memory-only session.
  function rememberDraft() {
    if (!selectedConversation) return
    var key = draftKey(selectedConversation)
    if (!key) return
    var order = draftOrder.filter(function(item) { return item !== key }).concat([key]).slice(-5)
    var next = {}
    for (var i = 0; i < order.length; i++) next[order[i]] = order[i] === key ? replyText : replyDrafts[order[i]] || ""
    replyDrafts = next
    draftOrder = order
  }

  function selectThread(conversation) {
    if (sending || threadProcess.running) return
    composing = false
    browsingContacts = false
    closeViewer()
    openThread(conversation)
  }
  readonly property string fontFamily: Style.font.family

  function dayLabel(timestamp) {
    var date = new Date(Number(timestamp))
    var today = new Date(nowMs)
    if (date.toDateString() === today.toDateString()) return qsTr("Today")
    today.setDate(today.getDate() - 1)
    if (date.toDateString() === today.toDateString()) return qsTr("Yesterday")
    return Qt.formatDate(date, "ddd, MMM d, yyyy")
  }

  function displayMessages(rows) {
    var previousY = messageList.contentY
    var anchorIndex = messageList.indexAt(1, previousY + 1)
    var anchorItem = messageList.itemAtIndex(anchorIndex)
    var anchor = anchorItem && messages[anchorIndex] ? {
      row: messages[anchorIndex], index: anchorIndex, offset: anchorItem.mapToItem(messageList, 0, 0).y
    } : null
    var currentGeneration = generation
    var currentThread = selectedConversation ? draftKey(selectedConversation) : ""
    messages = rows
    if (!followingLatest) Qt.callLater(function() {
      if (!root.opened || root.followingLatest || root.generation !== currentGeneration
          || !root.selectedConversation || root.draftKey(root.selectedConversation) !== currentThread) return
      function sameRow(row) {
        return row && anchor && row.body === anchor.row.body
          && Number(row.timestamp) === Number(anchor.row.timestamp) && row.incoming === anchor.row.incoming
      }
      var target = anchor ? (sameRow(rows[anchor.index]) ? anchor.index : rows.findIndex(sameRow)) : -1
      if (target < 0) {
        messageList.contentY = messageList.originY + Math.max(0, Math.min(
          previousY - messageList.originY, messageList.contentHeight - messageList.height))
        return
      }
      // Realize the same row before restoring its screen position. ListView's
      // origin can change when it recycles delegates, even for an append.
      messageList.positionViewAtIndex(target, ListView.Beginning)
      messageList.forceLayout()
      Qt.callLater(function() {
        if (!root.opened || root.followingLatest || root.generation !== currentGeneration
            || !root.selectedConversation || root.draftKey(root.selectedConversation) !== currentThread) return
        var item = messageList.itemAtIndex(target)
        if (item) messageList.contentY += item.mapToItem(messageList, 0, 0).y - anchor.offset
      })
    })
  }

  function open(payloadJson) {
    if (typeof payloadJson !== "string" || payloadJson.length > 65536) return false
    var payload
    try { payload = JSON.parse(payloadJson) } catch (parseError) { return false }
    var nextEndpoint = Providers.messageEndpointFromPayload(payload)
    if (!nextEndpoint || (nextEndpoint.provider === "blueferry" && !blueFerryEnabled)) return false
    var nextKey = Providers.endpointKey(nextEndpoint)
    if (sending && nextKey !== endpointKey) return false
    var nextOwner = nextEndpoint.provider === "blueferry" ? payload.backendOwner : ""
    // A panel summon can bring back a long-lived window. Keep its current
    // conversation, draft and scroll position when no new target was requested.
    var sameSession = opened && nextKey === endpointKey && backendOwner === nextOwner
    var sameThread = selectedConversation && payload.threadId !== undefined && payload.threadId !== null
      && String(payload.threadId) === String(selectedConversation.threadId)
    if (sameSession && (sameThread || ((payload.threadId === undefined || payload.threadId === null) && !payload.conversationHint))) {
      presentWindow()
      return true
    }
    if (!opened || nextKey !== endpointKey || backendOwner !== nextOwner) close()
    endpoint = nextEndpoint
    backendOwner = nextOwner
    providerInvalidated = false
    deviceName = String(payload.deviceName || deviceId).slice(0, 256)
    pendingOpenTitle = String(payload.conversationHint || "")
    pendingOpenThreadId = payload.threadId === undefined || payload.threadId === null
      ? "" : String(payload.threadId)
    searchText = ""
    opened = true
    presentWindow()
    refreshContacts()
    refreshCachedConversations()
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    return true
  }

  function presentWindow() {
    messagesWindow.visible = true
    messagesWindow.minimized = false
    // The shell shares one app ID across its windows. Match both that ID and
    // our stable title, leaving tiling, placement and pinning to the compositor.
    var windows = ToplevelManager.toplevels.values
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].appId === Quickshell.appId && windows[i].title === messagesWindow.title) {
        windows[i].activate()
        break
      }
    }
  }

  function close() {
    opened = false
    eventReadQueued = false
    historyEventPending = false
    messageEvents.stop()
    generation++
    ferryThreads.cancel()
    ferryMessages.cancel()
    ferryContacts.cancel()
    browsingContacts = false
    contactsError = ""
    newMessageProcess.forgetPayload()
    replyProcess.forgetPayload()
    conversationProcess.running = false
    cachedConversationProcess.running = false
    contactProcess.running = false
    threadProcess.running = false
    threadProcess.result = null
    attachmentProcess.running = false
    replyField.text = ""
    replyDrafts = ({})
    draftOrder = []
    composeMessage.text = ""
    loading = false
    conversations = []
    contacts = []
    selectedConversation = null
    composing = false
    recipientQuery = ""
    recipientNumber = ""
    pendingNewBody = ""
    historyConversations = []
    sendOperations = []
    sendSyncProcess.running = false
    sendSyncProcess.result = null
    reconcileSends.stop()
    messages = []
    messageCache = ({})
    cacheOrder = []
    loadingThreadId = ""
    searchText = ""
    pendingOpenTitle = ""
    pendingOpenThreadId = ""
    attachmentPaths = ({})
    attachmentFetchUnique = ""
    attachmentFetchMode = ""
    closeViewer()
    pendingReply = ""
    pendingThreadId = ""
    error = ""
  }

  function refresh() {
    if (readOnlyProvider && browsingContacts) { refreshContacts(); return }
    if (composing) return
    if (selectedConversation) {
      openThread(selectedConversation)
      return
    }
    refreshConversations()
  }

  function refreshConversations() {
    if (!opened || deviceId === "" || conversationProcess.running || providerInvalidated) return
    if (readOnlyProvider) {
      if (ferryThreads.running) return
      if (!selectedConversation) loading = true
      error = ""
      ferryThreads.generation = generation
      ferryThreads.start(providerRequest("threads"))
      return
    }
    if (!selectedConversation) loading = true
    error = ""
    conversationProcess.command = [helperPath, "conversations", deviceId]
    conversationProcess.generation = generation
    conversationProcess.running = true
  }

  // Shows KDE Connect's cached thread list right away. The full read, which
  // asks the phone for anything newer, replaces it when it finishes.
  function refreshCachedConversations(eventRead) {
    if (!opened || deviceId === "" || readOnlyProvider || cachedConversationProcess.running || providerInvalidated) return
    cachedReadIsEvent = eventRead === true
    cachedConversationProcess.command = [helperPath, "conversations-cached", deviceId]
    cachedConversationProcess.generation = generation
    cachedConversationProcess.running = true
  }

  function applyMessageEvent(text) {
    var fetched = Model.parseConversations(text)
    if (fetched.length === 0) return
    historyConversations = fetched
    updateSendOperations(SendState.bindThreads(sendOperations, fetched))
    if (!selectedConversation || composing) return
    if (threadProcess.running) { historyEventPending = true; return }
    var latest = Model.findConversationByThreadId(fetched, selectedConversation.threadId)
    if (!latest) return
    var history = messageCache[threadCacheKey(latest.threadId)] || []
    var known = history.some(function(row) {
      return Number(row.timestamp) === Number(latest.timestamp)
        && String(row.body || "") === String(latest.preview || "")
        && row.incoming === latest.incoming
    })
    if (!known) openThread(latest)
  }

  Process {
    id: messageWatch
    command: [root.helperPath, "--popups", "off", "watch-messages"]
    running: root.opened && !root.readOnlyProvider
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).trim() === "changed " + root.deviceId && !messageEvents.running) messageEvents.start()
      }
    }
    onExited: if (root.opened && !root.readOnlyProvider) messageWatchRestart.restart()
  }

  Timer {
    id: messageWatchRestart
    interval: 5000
    onTriggered: if (root.opened && !root.readOnlyProvider) messageWatch.running = true
  }

  Timer {
    id: messageEvents
    interval: 120
    onTriggered: {
      if (!root.opened) return
      if (cachedConversationProcess.running) root.eventReadQueued = true
      else root.refreshCachedConversations(true)
    }
  }

  // The cached list can lack a thread that only just arrived, so a thread
  // waiting to open stays pending until the full read if the cache misses it.
  function applyConversationList(text, complete) {
    var fetched = Model.parseConversations(text)
    historyConversations = fetched
    updateSendOperations(SendState.bindThreads(sendOperations, fetched))
    if (pendingOpenThreadId !== "" || pendingOpenTitle !== "") {
      var target = Model.findConversationByThreadId(conversations, pendingOpenThreadId)
      if (!target && pendingOpenTitle !== "")
        target = Model.findConversationByTitle(conversations, pendingOpenTitle)
      if (!target && !complete) return
      pendingOpenThreadId = ""
      pendingOpenTitle = ""
      if (target && !selectedConversation && !composing) openThread(target)
    }
  }

  function refreshContacts() {
    if (!opened || deviceId === "" || contactProcess.running || providerInvalidated) return
    if (readOnlyProvider) {
      if (ferryContacts.running) return
      contactsError = ""
      ferryContacts.generation = generation
      ferryContacts.start(providerRequest("contacts"))
      return
    }
    contactProcess.command = [helperPath, "contacts", deviceId]
    contactProcess.generation = generation
    contactProcess.running = true
  }

  function openThread(conversation) {
    if (!opened || !conversation || threadProcess.running || providerInvalidated) return
    if (readOnlyProvider) {
      if (!Providers.threadKey(endpoint, conversation.threadId)) return
      ferryMessages.cancel()
      selectedConversation = conversation
      browsingContacts = false
      messages = messageCache[threadCacheKey(conversation.threadId)] || []
      loading = messages.length === 0
      error = ""
      ferryMessages.generation = generation
      ferryMessages.threadId = conversation.threadId
      var request = providerRequest("messages")
      request.threadId = conversation.threadId
      ferryMessages.start(request)
      return
    }
    var threadId = String(conversation.threadId)
    var changingThread = !selectedConversation
      || String(selectedConversation.threadId) !== threadId
      || String(selectedConversation.localOperationId || "") !== String(conversation.localOperationId || "")
    if (changingThread) {
      rememberDraft()
      replyField.text = replyDrafts[draftKey(conversation)] || ""
    }
    selectedConversation = conversation
    if (changingThread) followingLatest = true
    if (changingThread) displayMessages(SendState.messages(messageCache[threadCacheKey(conversation.threadId)] || [], conversation, sendOperations))
    if (conversation.threadId === null || conversation.threadId === undefined) {
      loading = false
      return
    }
    loading = messages.length === 0
    loadingThreadId = threadId
    error = ""
    threadProcess.command = [helperPath, "messages", deviceId, threadId]
    threadProcess.generation = generation
    threadProcess.result = null
    threadProcess.running = true
  }

  function threadCacheKey(threadId) {
    return threadId === null || threadId === undefined
      ? "" : Providers.threadKey(endpoint, String(threadId))
  }

  function setThreadMessages(threadId, nextMessages) {
    var key = threadCacheKey(threadId)
    if (!key) return
    var history = SendState.historyOnly(nextMessages)
    displayMessages(SendState.messages(history, selectedConversation, sendOperations))
    var order = cacheOrder.filter(function(item) { return item !== key }).concat([key]).slice(-5)
    var updatedCache = {}
    for (var i = 0; i < order.length; i++) {
      if (order[i] !== key) updatedCache[order[i]] = messageCache[order[i]]
    }
    updatedCache[key] = history
    cacheOrder = order
    messageCache = updatedCache
  }

  function showConversations() {
    rememberDraft()
    if (readOnlyProvider) ferryMessages.cancel()
    browsingContacts = false
    searchText = ""
    selectedConversation = null
    composing = false
    recipientQuery = ""
    recipientNumber = ""
    messages = []
    replyField.text = ""
    error = ""
    Qt.callLater(root.refresh)
  }

  function startCompose() {
    if (readOnlyProvider) return
    rememberDraft()
    selectedConversation = null
    composing = true
    recipientQuery = ""
    recipientNumber = ""
    error = ""
    composeMessage.text = ""
    Qt.callLater(function() { recipientField.forceActiveFocus() })
  }

  function chooseContact(contact) {
    recipientQuery = String(contact.name || contact.number || "")
    recipientNumber = String(contact.number || "")
    Qt.callLater(function() { composeMessage.forceActiveFocus() })
  }

  function updateSendOperations(next) {
    sendOperations = next
    conversations = SendState.conversations(historyConversations, sendOperations)
    if (selectedConversation && selectedConversation.localOperationId) {
      var bound = sendOperations.find(function(item) { return item.id === root.selectedConversation.localOperationId })
      if (bound && bound.threadId !== "") selectedConversation = bound.conversation
    }
    if (selectedConversation)
      displayMessages(SendState.messages(messageCache[threadCacheKey(selectedConversation.threadId)] || [], selectedConversation, sendOperations))
  }

  function replaceSend(operation) {
    updateSendOperations(sendOperations.map(function(item) { return item.id === operation.id ? operation : item }))
  }

  function observeHistory(threadId, history) {
    historyConversations = SendState.updateThreadPreview(historyConversations, threadId, history)
    updateSendOperations(SendState.reconcile(sendOperations, deviceId, threadId, history))
  }

  function prepareSend(conversation, number, body, valid) {
    // Drop old confirmations first; unresolved text stays available until close.
    var retained = SendState.pruneConfirmed(sendOperations)
    if (retained.length >= 100) {
      error = "Local send activity is full. Copy any messages you need before closing this window."
      return null
    }
    var operation = SendState.create(String(++nextSendId), deviceId, conversation, number,
                                     body, Date.now(), messageCache[threadCacheKey(conversation && conversation.threadId)])
    if (!valid) operation.state = "failed"
    updateSendOperations(retained.concat([operation]))
    if (!valid) {
      error = "Check the phone connection, recipient and message length (maximum 8192 UTF-8 bytes)."
      return null
    }
    return operation
  }

  function finishSend(operationId, outcome) {
    var exitCode = outcome.state === "accepted" ? 0 : 1
    var operation = sendOperations.find(function(item) { return item.id === operationId })
    if (!operation) return
    var finished = SendState.finish(operation, exitCode, Date.now(), sendConfirmationTimeoutMs)
    if (outcome.state === "not-submitted") finished.state = "failed"
    replaceSend(finished)
    if (outcome.state !== "accepted") error = outcome.text
    if (exitCode === 0) {
      if (finished.threadId !== "") {
        var history = messageCache[threadCacheKey(finished.threadId)]
        if (history) updateSendOperations(SendState.reconcile(sendOperations, deviceId, finished.threadId, history))
      }
      reconcileSends.start()
      Qt.callLater(root.reconcileNextSend)
    }
  }

  function reconcileNextSend() {
    updateSendOperations(SendState.expire(sendOperations, Date.now()))
    var pending = sendOperations.filter(function(item) { return item.state === "accepted" })
    if (pending.length === 0) {
      reconcileSends.stop()
      sendSyncProcess.running = false
      return
    }
    if (sendSyncProcess.running) return
    // Round-robin reads prevent a slow/new thread starving another send.
    pending.sort(function(left, right) { return left.attempts - right.attempts })
    var operation = Object.assign({}, pending[0])
    operation.attempts++
    replaceSend(operation)
    sendSyncProcess.operationId = operation.id
    sendSyncProcess.threadId = operation.threadId
    sendSyncProcess.generation = generation
    sendSyncProcess.result = null
    sendSyncProcess.command = operation.threadId === ""
      ? [helperPath, "conversations", operation.deviceId]
      : [helperPath, "messages", operation.deviceId, operation.threadId]
    sendSyncProcess.running = true
  }

  function editSend(operation) {
    if (!operation || !opened || sending || threadProcess.running) return
    if (operation.threadId !== "" && operation.conversation) {
      composing = false
      openThread(operation.conversation)
      replyField.text = operation.body
      Qt.callLater(function() { replyField.forceActiveFocus() })
    } else {
      startCompose()
      recipientQuery = operation.number
      recipientNumber = operation.number
      composeMessage.text = operation.body
      Qt.callLater(function() { composeMessage.forceActiveFocus() })
    }
  }

  function sendNewMessage() {
    if (readOnlyProvider) return
    var destination = recipientNumber !== "" ? recipientNumber : recipientField.text.trim()
    var message = composeMessage.text
    if (destination === "" || message.trim() === "" || sending || newMessageProcess.running || replyProcess.running || !opened) return
    var conversation = SendState.exactConversation(historyConversations, destination)
      || {threadId: null, addresses: [destination], names: [recipientNumber !== "" ? recipientQuery : destination]}
    var valid = /^[A-Za-z0-9]{1,128}$/.test(deviceId)
      && /^[+0-9().\s-]+$/.test(destination) && destination.replace(/[^0-9]/g, "").length >= 3
      && PrivateText.byteLength(message) <= 8192 && message.indexOf("\u0000") === -1
    var operation = prepareSend(conversation, destination, message, valid)
    if (!operation) return
    sending = true
    pendingNewBody = message
    error = ""
    newMessageProcess.operationId = operation.id
    newMessageProcess.generation = generation
    newMessageProcess.start({version:1, operation:"sms", deviceId:deviceId, destination:destination, body:message})
  }

  // Every route that opens a phone attachment outside OmaLink goes through the
  // helper, which refuses files that would run and detaches the viewer.
  function openAttachmentExternally(path) {
    if (readOnlyProvider) return
    if (path === "" || openProcess.running) return
    openProcess.command = [helperPath, "attachment-open", String(path)]
    openProcess.generation = generation
    openProcess.running = true
  }

  function openAttachment(attachment) {
    if (readOnlyProvider) return
    if (!attachment) return
    var unique = String(attachment.unique || "")
    if (unique === "") return
    var isImage = Model.attachmentKind(attachment.mimeType) === "image"
    var cached = attachmentPaths["$" + unique] || ""
    if (attachmentProcess.running && attachmentFetchUnique !== unique) {
      error = "Still fetching another attachment…"
      return
    }
    if (isImage) {
      viewerOpen = true
      viewerStatus = ""
      viewerPath = cached
    }
    if (cached !== "") {
      if (!isImage) root.openAttachmentExternally(cached)
      return
    }
    if (attachmentProcess.running) {
      if (attachmentFetchUnique !== unique) error = "Still fetching another attachment…"
      return
    }
    error = ""
    attachmentFetchUnique = unique
    attachmentFetchMode = isImage ? "view" : "open"
    attachmentProcess.command = [helperPath, "attachment", deviceId, String(attachment.partId), unique,
      isImage ? "image" : "file"]
    attachmentProcess.generation = generation
    attachmentProcess.running = true
  }

  function closeViewer() {
    viewerOpen = false
    viewerPath = ""
    viewerStatus = ""
  }

  function sendReply() {
    if (readOnlyProvider) return
    var message = replyField.text
    if (!selectedConversation || message.trim() === "" || sending || newMessageProcess.running || replyProcess.running || !opened) return
    var threadId = selectedConversation.threadId
    var valid = /^[A-Za-z0-9]{1,128}$/.test(deviceId) && threadId !== null
      && /^[0-9]+$/.test(String(threadId)) && PrivateText.byteLength(message) <= 8192 && message.indexOf("\u0000") === -1
    var operation = prepareSend(selectedConversation, "", message, valid)
    if (!operation) return
    sending = true
    pendingReply = message
    pendingThreadId = String(threadId)
    error = ""
    replyProcess.operationId = operation.id
    replyProcess.generation = generation
    replyProcess.start({version:1, operation:"reply", deviceId:deviceId, threadId:String(threadId), body:message})
  }

  Timer {
    interval: root.selectedConversation ? 15000 : 30000
    repeat: true
    running: root.opened
    onTriggered: {
      root.nowMs = Date.now()
      root.refresh()
    }
  }

  function providerRequest(operation) {
    return {version:1, operation:operation, endpoint:endpoint, expectedOwner:backendOwner}
  }

  function providerFailure(result, contactOnly) {
    if (result.code === "thread_unavailable" && selectedConversation) {
      var threadId = selectedConversation.threadId
      var key = threadCacheKey(threadId)
      var nextCache = {}
      for (var cached in messageCache) if (cached !== key) nextCache[cached] = messageCache[cached]
      messageCache = nextCache
      cacheOrder = cacheOrder.filter(function(item) { return item !== key })
      historyConversations = historyConversations.filter(function(item) { return item.threadId !== threadId })
      conversations = historyConversations
      selectedConversation = null
      messages = []
      error = result.error
      return
    }
    if (["backend_changed", "backend_unavailable", "api_incompatible", "storage_unavailable",
         "authorization_required", "invalid_response"].indexOf(result.code) !== -1) {
      generation++
      ferryThreads.cancel()
      ferryMessages.cancel()
      ferryContacts.cancel()
      providerInvalidated = true
      historyConversations = []
      conversations = []
      selectedConversation = null
      pendingOpenTitle = ""
      pendingOpenThreadId = ""
      messages = []
      messageCache = ({})
      cacheOrder = []
      contacts = []
      loading = false
      error = result.error + " " + qsTr("Close and reopen BlueFerry history after resolving this.")
      contactsError = error
    } else if (contactOnly) contactsError = result.error
    else error = result.error
  }

  function showProviderContacts() {
    if (!readOnlyProvider || providerInvalidated) return
    ferryMessages.cancel()
    selectedConversation = null
    messages = []
    browsingContacts = true
    searchText = ""
    refreshContacts()
  }

  ProviderRequest {
    id: ferryThreads
    helperPath: root.pluginDir + "/bin/omalink-blueferry"
    property int generation: -1
    onFinished: function(transport) {
      if (!root.opened || !root.readOnlyProvider || generation !== root.generation) return
      var result = BlueFerry.result(transport, "threads", root.backendOwner)
      root.loading = false
      if (!result.ok) { root.providerFailure(result, false); return }
      root.historyConversations = result.items
      root.conversations = result.items
      if (root.pendingOpenThreadId !== "") {
        var target = result.items.find(function(item) { return item.threadId === root.pendingOpenThreadId })
        root.pendingOpenThreadId = ""
        if (target && !root.selectedConversation && !root.browsingContacts) root.openThread(target)
      }
    }
  }

  ProviderRequest {
    id: ferryMessages
    helperPath: root.pluginDir + "/bin/omalink-blueferry"
    property int generation: -1
    property string threadId: ""
    onFinished: function(transport) {
      if (!root.opened || !root.readOnlyProvider || generation !== root.generation
          || !root.selectedConversation || root.selectedConversation.threadId !== threadId) return
      var result = BlueFerry.result(transport, "messages", root.backendOwner)
      root.loading = false
      if (!result.ok) { root.providerFailure(result, false); return }
      root.setThreadMessages(threadId, result.items)
    }
  }

  ProviderRequest {
    id: ferryContacts
    helperPath: root.pluginDir + "/bin/omalink-blueferry"
    property int generation: -1
    onFinished: function(transport) {
      if (!root.opened || !root.readOnlyProvider || generation !== root.generation) return
      var result = BlueFerry.result(transport, "contacts", root.backendOwner)
      if (!result.ok) { root.providerFailure(result, true); return }
      root.contacts = result.items
      root.contactsError = ""
    }
  }

  Process {
    id: conversationProcess
    property int generation: -1
    readonly property bool current: root.opened && generation === root.generation
    stdout: SplitParser {
      onRead: function(text) {
        if (!conversationProcess.current) return
        cachedConversationProcess.running = false
        root.conversationsAppliedGeneration = root.generation
        root.applyConversationList(text, true)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (conversationProcess.current && String(text || "").trim() !== "") root.error = "Could not load messages"
    }
    onExited: function(exitCode) {
      if (!conversationProcess.current) { if (root.opened) Qt.callLater(root.refreshConversations); return }
      root.loading = false
      if (exitCode !== 0) root.error = "Could not load messages"
    }
  }

  Process {
    id: cachedConversationProcess
    property int generation: -1
    readonly property bool current: root.opened && generation === root.generation
    stdout: SplitParser {
      onRead: function(text) {
        // Never replace a list the full read already delivered.
        if (!cachedConversationProcess.current) return
        if (root.cachedReadIsEvent) { root.applyMessageEvent(text); return }
        if (root.conversationsAppliedGeneration === root.generation) return
        var fetched = Model.parseConversations(text)
        if (fetched.length === 0) return
        root.applyConversationList(text, false)
        if (!root.selectedConversation) root.loading = false
      }
    }
    onExited: {
      if (root.eventReadQueued && root.opened) {
        root.eventReadQueued = false
        messageEvents.restart()
      }
    }
  }

  Process {
    id: contactProcess
    property int generation: -1
    readonly property bool current: root.opened && generation === root.generation
    stdout: SplitParser {
      onRead: function(text) { if (contactProcess.current) root.contacts = Model.parseContacts(text) }
    }
    onExited: if (root.opened && !current) Qt.callLater(root.refreshContacts)
  }

  PrivateRequest {
    id: newMessageProcess
    helperPath: root.helperPath
    property int generation: -1
    property string operationId: ""
    readonly property bool current: root.opened && generation === root.generation
    onFinished: function(outcome) {
      root.sending = false
      if (!current) { root.pendingNewBody = ""; return }
      root.finishSend(operationId, outcome)
      if (outcome.state === "accepted" && root.composing && composeMessage.text === root.pendingNewBody) {
        root.composing = false
        root.recipientQuery = ""
        root.recipientNumber = ""
        composeMessage.text = ""
      }
      root.pendingNewBody = ""
    }
  }

  Timer {
    id: reconcileSends
    interval: root.sendReconcileIntervalMs
    repeat: true
    onTriggered: root.reconcileNextSend()
  }

  Process {
    id: sendSyncProcess
    property int generation: -1
    property string operationId: ""
    property string threadId: ""
    property var result: null
    property bool outputFinished: false
    property bool didExit: false
    property int resultExitCode: -1
    onRunningChanged: if (running) { result = null; outputFinished = false; didExit = false }
    function applyResult() {
      if (!outputFinished || !didExit) return
      outputFinished = false
      var exitCode = resultExitCode

      if (!current) return
      if (exitCode === 0 && result !== null) {
        if (threadId === "") {
          root.historyConversations = result
          root.updateSendOperations(SendState.bindThreads(root.sendOperations, result))
        } else {
          root.observeHistory(threadId, result)
          if (root.selectedConversation && String(root.selectedConversation.threadId) === threadId
              && (result.length > 0 || root.messages.length === 0))
            root.setThreadMessages(threadId, result)
        }
      }
      result = null
      // Every send receives at most six explicit reconciliation reads.
      root.updateSendOperations(root.sendOperations.map(function(item) {
        if (item.id !== sendSyncProcess.operationId || item.state !== "accepted" || item.attempts < 6) return item
        var expired = Object.assign({}, item)
        expired.state = "unconfirmed"
        return expired
      }))
    }
    readonly property bool current: root.opened && generation === root.generation
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!sendSyncProcess.current) return
        try {
          var parsed = JSON.parse(String(text))
          if (Array.isArray(parsed)) sendSyncProcess.result = parsed
        } catch (parseError) { /* A failed read is not empty phone history. */ }
        sendSyncProcess.outputFinished = true
        sendSyncProcess.applyResult()
      }
    }
    onExited: function(exitCode) {
      resultExitCode = exitCode
      didExit = true
      applyResult()
    }
  }

  PrivateRequest {
    id: replyProcess
    helperPath: root.helperPath
    property int generation: -1
    property string operationId: ""
    readonly property bool current: root.opened && generation === root.generation
    onFinished: function(outcome) {
      root.sending = false
      if (!current) { root.pendingReply = ""; root.pendingThreadId = ""; return }
      root.finishSend(operationId, outcome)
      if (outcome.state === "accepted" && root.selectedConversation
          && String(root.selectedConversation.threadId) === root.pendingThreadId)
        replyField.text = ""
      root.pendingReply = ""
      root.pendingThreadId = ""
    }
  }

  Process {
    id: attachmentProcess
    property int generation: -1
    readonly property bool current: root.opened && generation === root.generation
    stdout: SplitParser {
      onRead: function(text) {
        if (!attachmentProcess.current) return
        // Only the trailing newline comes off: a trailing space is part of the
        // phone's file name.
        var path = String(text || "").replace(/[\r\n]+$/, "")
        if (path === "") return
        var unique = root.attachmentFetchUnique
        var updated = {}
        for (var key in root.attachmentPaths) updated[key] = root.attachmentPaths[key]
        updated["$" + unique] = path
        root.attachmentPaths = updated
        if (root.attachmentFetchMode === "view") {
          if (root.viewerOpen && root.viewerPath === "") root.viewerPath = path
        } else {
          root.openAttachmentExternally(path)
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (!attachmentProcess.current) return
      if (exitCode !== 0) {
        if (root.viewerOpen && root.viewerPath === "") root.viewerOpen = false
        root.error = "Could not fetch the attachment from the phone"
      }
    }
  }

  Process {
    id: openProcess
    property int generation: -1
    readonly property bool current: root.opened && generation === root.generation
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!openProcess.current) return
        var message = String(text || "").trim()
        if (message !== "") root.error = message
      }
    }
    onExited: function(exitCode) {
      if (!openProcess.current) return
      if (exitCode !== 0 && root.error === "") root.error = "OmaLink will not open this file"
    }
  }

  Process {
    id: saveProcess
    property int generation: -1
    readonly property bool current: root.opened && generation === root.generation
    stdout: SplitParser {
      onRead: function(text) {
        if (!saveProcess.current) return
        var target = String(text || "").trim()
        if (target !== "") root.viewerStatus = "Saved to " + target
      }
    }
    onExited: function(exitCode) {
      if (!saveProcess.current) return
      if (exitCode !== 0) root.viewerStatus = "Could not save the image"
    }
  }

  Process {
    id: threadProcess
    property int generation: -1
    property var result: null
    property bool outputFinished: false
    property bool didExit: false
    property int resultExitCode: -1
    onRunningChanged: if (running) { result = null; outputFinished = false; didExit = false }
    function applyResult() {
      if (!outputFinished || !didExit) return
      outputFinished = false
      var exitCode = resultExitCode

      if (!current) { result = null; return }
      root.loading = false
      if (exitCode !== 0 || result === null) {
        root.error = "Could not load conversation"
      } else if (root.selectedConversation
                 && String(root.selectedConversation.threadId) === root.loadingThreadId
                 && (result.length > 0 || root.messages.length === 0)) {
        root.observeHistory(root.loadingThreadId, result)
        root.setThreadMessages(root.loadingThreadId, result)
        // Opening a row is navigation. Only mark it seen after its history
        // loaded successfully, and never dismiss the phone notification here.
        if (result.length > 0 && root.selectedConversation.unread)
          Quickshell.execDetached([root.helperPath, "mark-seen", root.deviceId,
            root.loadingThreadId, String(Math.round(Number(root.selectedConversation.timestamp) || 0))])
      }
      result = null
      if (root.historyEventPending) {
        root.historyEventPending = false
        messageEvents.start()
      }
    }
    readonly property bool current: root.opened && generation === root.generation
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!threadProcess.current) return
        try {
          var parsed = JSON.parse(String(text))
          if (Array.isArray(parsed)) threadProcess.result = parsed
        } catch (parseError) { /* Reject malformed or incomplete history. */ }
        threadProcess.outputFinished = true
        threadProcess.applyResult()
      }
    }
    onExited: function(exitCode) {
      resultExitCode = exitCode
      didExit = true
      applyResult()
    }
  }

  FloatingWindow {
    id: messagesWindow
    objectName: "messagesAppWindow"
    visible: false
    title: "OmaLink Messages"
    color: root.windowBackground
    implicitWidth: Style.space(1080)
    implicitHeight: Style.space(740)
    minimumSize: Qt.size(Style.space(400), Style.space(420))
    // Only an explicit window close tears down history and local send state.
    // Losing focus or minimizing must leave the session alone.
    onClosed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: {
        if (root.viewerOpen) root.closeViewer()
        else if (root.selectedConversation || root.composing || root.browsingContacts) root.showConversations()
        else root.close()
      }
      Keys.onPressed: function(event) {
        if ((!root.selectedConversation || root.wideLayout) && !root.composing && (event.key === Qt.Key_Slash
            || (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)))) {
          (root.browsingContacts ? providerFilter : searchField).forceActiveFocus()
          event.accepted = true
        } else if (!root.selectedConversation && !root.composing && event.key === Qt.Key_PageDown) {
          conversationList.contentY = Math.min(
            Math.max(0, conversationList.contentHeight - conversationList.height),
            conversationList.contentY + conversationList.height * 0.85)
          event.accepted = true
        } else if (!root.selectedConversation && !root.composing && event.key === Qt.Key_PageUp) {
          conversationList.contentY = Math.max(0, conversationList.contentY - conversationList.height * 0.85)
          event.accepted = true
        } else if (!root.selectedConversation && !root.composing && event.key === Qt.Key_Home) {
          conversationList.positionViewAtBeginning()
          event.accepted = true
        } else if (!root.selectedConversation && !root.composing && event.key === Qt.Key_End) {
          conversationList.positionViewAtEnd()
          event.accepted = true
        } else if (event.key === Qt.Key_R) {
          root.refresh()
          event.accepted = true
        }
      }

      Rectangle {
        anchors.fill: parent
        color: root.windowBackground

        RowLayout {
          anchors.fill: parent
          spacing: 0
          Rectangle {
            Layout.preferredWidth: root.wideLayout ? Style.space(300) : -1
            Layout.fillWidth: !root.wideLayout
            Layout.fillHeight: true
            visible: root.wideLayout || (!root.selectedConversation && !root.composing && !root.browsingContacts)
            color: root.sidebarBackground

            Rectangle { anchors.right: parent.right; height: parent.height; width: 1; color: root.separator; visible: root.wideLayout }
            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(18)
              spacing: Style.space(18)
              Text {
                text: "OMALINK"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Math.max(11, Style.font.caption)
                font.letterSpacing: 2
              }
              RowLayout {
                Layout.fillWidth: true
                Text {
                  Layout.fillWidth: true
                  text: qsTr("Messages")
                  color: root.foreground
                  font.family: root.readingFontFamily
                  font.pixelSize: Math.max(25, Style.font.display)
                  font.bold: true
                }
                PanelActionButton {
                  visible: !root.readOnlyProvider
                  enabled: !root.sending
                  iconText: "󰐕"
                  tooltipText: qsTr("New message")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.startCompose()
                }
                PanelActionButton {
                  visible: !root.wideLayout
                  iconText: "󰑐"
                  tooltipText: qsTr("Refresh")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.refresh()
                }
                PanelActionButton {
                  visible: !root.wideLayout
                  iconText: "󰅖"
                  tooltipText: qsTr("Close Messages")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.close()
                }
              }
              Text {
                visible: root.error !== "" || root.filteredConversations.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.error || (root.loading ? qsTr("Loading conversations…") : root.searchText ? qsTr("No matches") : qsTr("No conversations yet"))
                color: root.dim
                font.family: root.readingFontFamily
                font.pixelSize: root.labelSize
              }
              RowLayout {
                visible: true
                Layout.fillWidth: true
                spacing: Style.space(8)

                TextField {
                  id: searchField
                focusPolicy: Qt.StrongFocus
                  Layout.fillWidth: true
                  placeholderText: qsTr("Search conversations")
                  text: root.searchText
                  foreground: root.foreground
                  font.family: root.readingFontFamily
                  font.pixelSize: root.bodySize - 1
                  verticalPadding: Style.space(12)
                  onTextChanged: root.searchText = text
                  Keys.onEscapePressed: {
                    if (text !== "") text = ""
                    else keyCatcher.forceActiveFocus()
                  }
                }

                PanelActionButton {
                  visible: root.searchText !== ""
                  iconText: "󰅖"
                  tooltipText: "Clear search"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: {
                    root.searchText = ""
                    searchField.forceActiveFocus()
                  }
                }
              }

              ListView {
                id: conversationList
                visible: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Style.space(6)
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                model: root.filteredConversations

                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

                delegate: Rectangle {
                  required property var modelData
                  width: ListView.view.width
                  height: Style.space(88)
                  activeFocusOnTab: true
                  Accessible.role: Accessible.Button
                  Accessible.name: Model.conversationTitle(modelData)
                  Keys.onReturnPressed: root.selectThread(modelData)
                  Keys.onSpacePressed: root.selectThread(modelData)
                  readonly property bool selected: root.selectedConversation !== null
                  && String(root.selectedConversation.threadId) === String(modelData.threadId)
                  border.width: activeFocus ? 1 : 0
                  border.color: Color.accent
                  color: selected ? root.outgoingBackground : rowMouse.containsMouse ? root.incomingBackground : "transparent"
                  radius: Style.space(12)

                  RowLayout {
                    id: row
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(10)

                    Rectangle {
                      width: Style.space(42)
                      height: width
                      radius: Style.space(12)
                      color: root.blend(Color.accent, root.sidebarBackground, 0.13)

                      Text {
                        anchors.centerIn: parent
                        text: root.initials(modelData)
                        textFormat: Text.PlainText
                        font.bold: true
                        color: root.foreground
                        font.family: root.readingFontFamily
                        font.pixelSize: root.bodySize - 1
                      }
                      Rectangle {
                        visible: !!modelData.unread
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: -Style.space(2)
                        width: Style.space(9); height: width; radius: width / 2
                        color: Color.accent
                        border.width: 2
                        border.color: root.sidebarBackground
                      }
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(6)

                      RowLayout {
                        Layout.fillWidth: true
                        Text {
                          Layout.fillWidth: true
                          text: Model.conversationTitle(modelData)
                          textFormat: Text.PlainText
                          color: root.foreground
                          font.family: root.readingFontFamily
                          font.pixelSize: root.bodySize - 1
                          font.bold: true
                          elide: Text.ElideRight
                        }
                        Text {
                          text: modelData.sendState === "unconfirmed" ? "Unconfirmed"
                          : modelData.sendState === "failed" ? "Not submitted"
                          : modelData.sendState ? "Pending"
                          : Model.relativeTime(modelData.timestamp, root.nowMs)
                          textFormat: Text.PlainText
                          color: root.dim
                          font.family: root.readingFontFamily
                          font.pixelSize: Math.max(11, root.labelSize - 1)
                        }
                      }

                      Text {
                        Layout.fillWidth: true
                        text: (modelData.incoming ? "" : "You: ") + Model.previewText(modelData)
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.readingFontFamily
                        font.pixelSize: root.labelSize
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                      }
                    }
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.selectThread(modelData)
                    }
                  }
                }
              }


              Rectangle { Layout.fillWidth: true; height: 1; color: root.separator }
              Text {
                Layout.fillWidth: true
                text: root.readOnlyProvider ? qsTr("BlueFerry · Local history") : root.deviceName
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.labelSize
              }
            }
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.wideLayout || root.selectedConversation !== null || root.composing || root.browsingContacts
            color: root.windowBackground
            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(24)
              anchors.leftMargin: Math.max(Style.space(24), (parent.width - Style.space(760)) / 2)
              anchors.rightMargin: anchors.leftMargin
              spacing: Style.space(root.compactHeight ? 10 : 16)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(12)
                PanelActionButton {
                  visible: (!root.wideLayout && root.selectedConversation !== null) || root.composing || root.browsingContacts
                  iconText: "󰁍"
                  tooltipText: "Back to conversations"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.showConversations()
                }

                Rectangle {
                  visible: root.selectedConversation !== null
                  width: Style.space(46); height: width; radius: Style.space(14)
                  color: root.outgoingBackground
                  Text {
                    anchors.centerIn: parent
                    text: root.initials(root.selectedConversation)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.readingFontFamily
                    font.pixelSize: root.bodySize
                    font.bold: true
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: root.selectedConversation
                  ? Model.conversationTitle(root.selectedConversation)
                  : (root.browsingContacts ? qsTr("Contacts") : root.composing ? "New message" : "Messages")
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.readingFontFamily
                  font.pixelSize: Math.max(23, Style.font.display)
                  font.bold: true
                }

                Button {
                  fontSize: root.bodySize - 1
                  visible: !root.wideLayout && !root.readOnlyProvider && root.selectedConversation === null && !root.composing
                  text: "New message"
                  enabled: !root.readOnlyProvider
                  foreground: root.foreground
                  fontFamily: root.readingFontFamily
                  bordered: true
                  onClicked: root.startCompose()
                }

                Button {
                  fontSize: root.bodySize - 1
                  visible: root.readOnlyProvider && !root.browsingContacts && root.selectedConversation === null
                  text: qsTr("Contacts")
                  enabled: !root.providerInvalidated
                  focusable: true
                  onClicked: root.showProviderContacts()
                }

                PanelActionButton {
                  visible: !root.composing
                  enabled: !root.providerInvalidated
                  iconText: "󰑐"
                  tooltipText: "Refresh"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.refresh()
                }

                PanelActionButton {
                  iconText: "󰅖"
                  tooltipText: qsTr("Close. Clears local activity; submitted sends may still finish.")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.close()
                }
              }

              Text {
                Layout.fillWidth: true
                text: root.readOnlyProvider ? qsTr("BlueFerry local history · Experimental") : qsTr("KDE Connect · %1").arg(root.deviceName)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.dim
                font.family: root.readingFontFamily
                font.pixelSize: root.labelSize
              }

              Text {
                visible: root.readOnlyProvider
                Layout.fillWidth: true
                text: qsTr("Read-only, limited history observed by BlueFerry. It may be incomplete and is not tied to your selected KDE Connect phone. Viewing does not mark messages read.")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: root.dim
                font.family: root.readingFontFamily
                font.pixelSize: root.labelSize
              }

              Rectangle { Layout.fillWidth: true; height: 1; color: root.separator }

              Item {
                visible: root.wideLayout && !root.selectedConversation && !root.composing && !root.browsingContacts
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                  anchors.centerIn: parent
                  width: Math.min(parent.width, Style.space(340))
                  spacing: Style.space(16)
                  Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: Style.space(76); height: width; radius: Style.space(22)
                    color: root.outgoingBackground
                    Text { anchors.centerIn: parent; text: "󰍩"; color: Color.accent; font.family: root.fontFamily; font.pixelSize: 32 }
                  }
                  Text {
                    Layout.fillWidth: true
                    text: qsTr("Select a conversation")
                    horizontalAlignment: Text.AlignHCenter
                    color: root.foreground
                    font.family: root.readingFontFamily
                    font.pixelSize: Math.max(23, Style.font.display)
                    font.bold: true
                  }
                  Text {
                    Layout.fillWidth: true
                    text: qsTr("Choose a thread on the left, or start a new message.")
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    color: root.dim
                    font.family: root.readingFontFamily
                    font.pixelSize: root.bodySize
                  }
                  Button {
                    visible: !root.readOnlyProvider
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("New message")
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.readingFontFamily
                    fontSize: root.bodySize
                    onClicked: root.startCompose()
                  }
                }
              }

              RowLayout {
                visible: root.latestSend !== null && root.selectedConversation === null
                Layout.fillWidth: true
                Text {
                  Layout.fillWidth: true
                  text: root.latestSend
                  ? (root.latestSend.conversation ? Model.conversationTitle(root.latestSend.conversation) : root.latestSend.number)
                  + ": " + SendState.label(root.latestSend.state) : ""
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  color: root.dim
                  font.family: root.readingFontFamily
                  font.pixelSize: root.labelSize
                }
                Button {
                  fontSize: root.bodySize - 1
                  text: "Edit copy"
                  visible: root.latestSend !== null && (root.latestSend.state === "failed" || root.latestSend.state === "unconfirmed")
                  enabled: !root.sending && !threadProcess.running
                  foreground: root.foreground
                  fontFamily: root.readingFontFamily
                  onClicked: root.editSend(root.latestSend)
                }
              }

              Text {
                visible: !root.browsingContacts && (root.selectedConversation !== null || root.composing) && (root.error !== "" || (!root.composing && (root.loading || (root.selectedConversation ? root.messages.length === 0 : root.filteredConversations.length === 0))))
                Layout.fillWidth: true
                text: root.error !== "" ? root.error : (root.loading ? "Loading…" : (root.selectedConversation ? "No messages" : (root.searchText === "" ? "No conversations" : "No matches")))
                color: root.dim
                font.family: root.readingFontFamily
                font.pixelSize: root.bodySize
                horizontalAlignment: Text.AlignHCenter
              }

              TextField {
                id: providerFilter
                focusPolicy: Qt.StrongFocus
                visible: root.browsingContacts
                Layout.fillWidth: true
                placeholderText: qsTr("Filter loaded contacts")
                text: root.searchText
                foreground: root.foreground
                font.family: root.readingFontFamily
                font.pixelSize: root.bodySize
                onTextChanged: root.searchText = text
              }

              Text {
                visible: root.browsingContacts
                Layout.fillWidth: true
                text: root.contactsError !== "" ? root.contactsError : ferryContacts.running ? qsTr("Loading contacts…")
                : root.visibleProviderContacts.length === 0 ? qsTr("No contacts in this loaded subset") : ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: root.dim
                font.family: root.readingFontFamily
                font.pixelSize: root.labelSize
              }

              ListView {
                visible: root.browsingContacts
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Style.space(8)
                model: root.visibleProviderContacts
                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
                delegate: Item {
                  required property var modelData
                  width: ListView.view.width
                  height: contactText.implicitHeight
                  TextEdit {
                    id: contactText
                    width: parent.width
                    text: modelData.name + "\n" + modelData.number
                    textFormat: TextEdit.PlainText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: root.foreground
                    font.family: root.readingFontFamily
                    font.pixelSize: root.bodySize
                    Accessible.name: modelData.name + ", " + modelData.number
                  }
                }
              }

              ListView {
                id: messageList
                objectName: "messageHistoryList"
                visible: root.selectedConversation !== null
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Style.space(3)
                model: root.messages
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
                onMovementStarted: root.followingLatest = false
                onMovementEnded: root.followingLatest = atYEnd || contentY - originY + height >= contentHeight - Style.space(24)
                function followEnd() {
                  if (root.followingLatest) Qt.callLater(function() {
                    if (root.opened && root.followingLatest) messageList.positionViewAtEnd()
                  })
                }
                onCountChanged: followEnd()
                onContentHeightChanged: followEnd()
                onHeightChanged: followEnd()

                delegate: Item {
                  required property var modelData
                  required property int index
                  property bool showSendDetails: false
                  readonly property bool beginsDay: index === 0 || !root.messages[index - 1] || new Date(Number(root.messages[index - 1].timestamp)).toDateString()
                  !== new Date(Number(modelData.timestamp)).toDateString()
                  readonly property bool endsRun: !root.messages[index + 1]
                  || root.messages[index + 1].incoming !== modelData.incoming
                    || new Date(Number(root.messages[index + 1].timestamp)).toDateString() !== new Date(Number(modelData.timestamp)).toDateString()
                  || Number(root.messages[index + 1].timestamp) - Number(modelData.timestamp) > 300000
                  width: ListView.view.width
                  height: dayHeader.height + (beginsDay ? Style.space(8) : 0)
                  + bubble.implicitHeight + (messageMeta.visible ? messageMeta.implicitHeight + Style.space(6) : 0) + (endsRun ? Style.space(16) : Style.space(2))
                  + (showSendDetails ? sendDetails.implicitHeight + Style.space(8) : 0)

                  Item {
                    id: dayHeader
                    visible: beginsDay
                    width: parent.width
                    height: visible ? Style.space(44) : 0
                    Rectangle {
                      anchors.centerIn: parent
                      width: dayText.implicitWidth + Style.space(28)
                      height: Style.space(26)
                      radius: height / 2
                      color: root.sidebarBackground
                      border.width: 1
                      border.color: root.separator
                      Text {
                        id: dayText
                        anchors.centerIn: parent
                        text: root.dayLabel(modelData.timestamp)
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.readingFontFamily
                        font.pixelSize: root.labelSize
                        font.weight: Font.Medium
                      }
                    }
                  }

                  Rectangle {
                    id: bubble
                    anchors.top: dayHeader.bottom
                    anchors.topMargin: beginsDay ? Style.space(8) : 0
                    readonly property var attachments: Model.messageAttachments(modelData)
                    readonly property bool incomingMessage: modelData.incoming
                    readonly property color contentColor: root.foreground
                    anchors.left: modelData.incoming ? parent.left : undefined
                    anchors.right: modelData.incoming ? undefined : parent.right
                    width: Math.min(
                    (attachments.length > 0
                    ? Math.max(messageText.implicitWidth, Style.space(210))
                    : messageText.implicitWidth) + Style.space(32),
                    Math.min(Style.space(480), parent.width * 0.88))
                    implicitHeight: messageColumn.implicitHeight + Style.space(24)
                    color: modelData.incoming ? root.incomingBackground : root.outgoingBackground
                    radius: Math.max(Style.cornerRadius, Style.space(14))
                    border.width: 0
                    border.color: Color.menu.selectedText

                    MouseArea {
                      anchors.fill: parent
                      acceptedButtons: Qt.RightButton
                      onClicked: {
                        messageText.selectAll()
                        messageText.copy()
                        messageText.deselect()
                      }
                    }

                    ColumnLayout {
                      id: messageColumn
                      anchors.fill: parent
                      anchors.margins: Style.space(12)
                      spacing: Style.space(6)

                      Repeater {
                        model: bubble.attachments

                        Item {
                          id: attachmentItem
                          required property var modelData
                          readonly property string kind: Model.attachmentKind(modelData.mimeType)
                          readonly property string thumbUri: Model.thumbnailUri(modelData)
                          readonly property bool showThumb: thumbUri !== "" && (kind === "image" || kind === "video")
                          readonly property bool fetching: attachmentProcess.running
                          && root.attachmentFetchUnique === String(modelData.unique || "")
                          readonly property int thumbWidth: Math.min(Style.space(210), bubble.width - Style.space(24))

                          Layout.preferredWidth: showThumb ? thumbWidth : -1
                          Layout.fillWidth: !showThumb
                          Layout.preferredHeight: showThumb
                          ? (thumbImage.status === Image.Ready && thumbImage.implicitWidth > 0
                          ? Math.min(Math.round(thumbWidth * thumbImage.implicitHeight / thumbImage.implicitWidth), Style.space(280))
                          : Style.space(140))
                          : tile.implicitHeight

                          ClippingRectangle {
                            visible: attachmentItem.showThumb
                            anchors.fill: parent
                            radius: Style.cornerRadius
                            color: "transparent"

                            Image {
                              id: thumbImage
                              anchors.fill: parent
                              source: attachmentItem.thumbUri
                              fillMode: Image.PreserveAspectCrop
                              asynchronous: true
                              sourceSize.width: 512
                              sourceSize.height: 512
                            }

                            Rectangle {
                              visible: attachmentItem.kind === "video" && !attachmentItem.fetching
                              anchors.centerIn: parent
                              width: Style.space(30)
                              height: width
                              radius: width / 2
                              color: Qt.rgba(0, 0, 0, 0.55)

                              Text {
                                anchors.centerIn: parent
                                text: "▶"
                                color: "white"
                                font.pixelSize: root.labelSize
                              }
                            }

                            Rectangle {
                              visible: attachmentItem.fetching
                              anchors.fill: parent
                              color: Qt.rgba(0, 0, 0, 0.45)

                              Text {
                                anchors.centerIn: parent
                                text: "Fetching…"
                                color: "white"
                                font.family: root.readingFontFamily
                                font.pixelSize: root.labelSize
                              }
                            }
                          }

                          Rectangle {
                            id: tile
                            visible: !attachmentItem.showThumb
                            anchors.fill: parent
                            implicitHeight: tileLabel.implicitHeight + Style.space(14)
                            radius: Style.cornerRadius
                            color: Qt.rgba(bubble.contentColor.r, bubble.contentColor.g, bubble.contentColor.b, 0.12)

                            Text {
                              id: tileLabel
                              anchors.verticalCenter: parent.verticalCenter
                              anchors.left: parent.left
                              anchors.leftMargin: Style.space(8)
                              text: attachmentItem.fetching
                              ? "Fetching…"
                              : Model.attachmentLabel(attachmentItem.modelData.mimeType)
                              textFormat: Text.PlainText
                              color: bubble.contentColor
                              font.family: root.readingFontFamily
                              font.pixelSize: root.labelSize
                              font.bold: true
                            }
                          }

                          MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openAttachment(attachmentItem.modelData)
                          }
                        }
                      }

                      Text {
                        visible: root.readOnlyProvider && !!modelData.sender
                        Layout.fillWidth: true
                        text: modelData.sender || ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: bubble.contentColor
                        font.family: root.readingFontFamily
                        font.pixelSize: root.labelSize
                      }
                      Text {
                        visible: root.readOnlyProvider && modelData.bodyTruncated === true
                        text: qsTr("Message shortened by the backend or display limit")
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: bubble.contentColor
                        font.family: root.readingFontFamily
                        font.pixelSize: root.labelSize
                      }
                      TextEdit {
                        id: messageText
                        visible: text !== ""
                        Layout.fillWidth: true
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        text: modelData.body !== ""
                        ? modelData.body
                        : (bubble.attachments.length === 0 && modelData.attachmentCount > 0 ? "Attachment" : "")
                        color: root.foreground
                        selectionColor: modelData.incoming ? Color.menu.selectedBackground : Color.popups.background
                        selectedTextColor: Color.menu.selectedText
                        font.family: root.readingFontFamily
                        font.pixelSize: root.bodySize
                        wrapMode: TextEdit.Wrap
                      }

                    }
                  }

                  RowLayout {
                    id: messageMeta
                    visible: endsRun || !!modelData.sendState
                    anchors.top: bubble.bottom
                    anchors.topMargin: Style.space(6)
                    anchors.left: modelData.incoming ? parent.left : undefined
                    anchors.right: modelData.incoming ? undefined : parent.right
                    spacing: Style.space(6)
                    Text {
                      text: Qt.formatTime(new Date(modelData.timestamp), "hh:mm")
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.readingFontFamily
                      font.pixelSize: root.labelSize
                    }
                    Button {
                      visible: !!modelData.sendState
                      text: SendState.label(modelData.sendState)
                      tooltipText: SendState.detail(modelData.sendState)
                      focusable: true
                      fontSize: root.labelSize
                      horizontalPadding: Style.space(2)
                      verticalPadding: 0
                      foreground: root.foreground
                      fontFamily: root.readingFontFamily
                      onClicked: showSendDetails = !showSendDetails
                    }
                    Button {
                      visible: !!modelData.localSend && (modelData.sendState === "failed" || modelData.sendState === "unconfirmed")
                      text: qsTr("Edit copy")
                      focusable: true
                      fontSize: root.labelSize
                      verticalPadding: 0
                      foreground: root.foreground
                      fontFamily: root.readingFontFamily
                      enabled: !root.sending && !threadProcess.running
                      onClicked: root.editSend(root.sendOperations.find(function(item) { return item.id === modelData.operationId }))
                    }
                  }
                  Text {
                    id: sendDetails
                    visible: showSendDetails
                    anchors.top: messageMeta.bottom
                    anchors.topMargin: Style.space(8)
                    anchors.right: parent.right
                    width: parent.width * 0.78
                    text: SendState.detail(modelData.sendState)
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: root.dim
                    font.family: root.readingFontFamily
                    font.pixelSize: root.labelSize
                  }
                }
              }
              Button {
                fontSize: root.bodySize - 1
                visible: root.selectedConversation !== null && !root.followingLatest
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Latest messages ↓")
                foreground: root.foreground
                fontFamily: root.readingFontFamily
                focusable: true
                onClicked: { root.followingLatest = true; messageList.positionViewAtEnd() }
              }

              ColumnLayout {
                visible: root.composing
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Style.space(root.compactHeight ? 8 : 12)

                Text {
                  visible: !root.compactHeight
                  text: "TO"
                  color: root.dim
                  font.family: root.readingFontFamily
                  font.pixelSize: root.labelSize
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                TextField {
                  id: recipientField
                  focusPolicy: Qt.StrongFocus
                  objectName: "recipientInput"
                  Layout.fillWidth: true
                  enabled: !root.sending
                  placeholderText: "Contact name or phone number"
                  text: root.recipientQuery
                  foreground: root.foreground
                  font.family: root.readingFontFamily
                  font.pixelSize: root.bodySize
                  verticalPadding: Style.space(10)
                  onTextEdited: {
                    root.recipientQuery = text
                    root.recipientNumber = ""
                  }
                }

                ListView {
                  visible: root.filteredContacts.length > 0 && root.recipientNumber === ""
                  Layout.fillWidth: true
                  Layout.preferredHeight: Math.min(contentHeight, Style.space(root.compactHeight ? 52 : 180))
                  clip: true
                  spacing: Style.space(3)
                  model: root.filteredContacts

                  Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

                  delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: contactRow.implicitHeight + Style.space(14)
                    color: contactMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : "transparent"
                    radius: Style.cornerRadius

                    RowLayout {
                      id: contactRow
                      anchors.fill: parent
                      anchors.margins: Style.space(7)
                      spacing: Style.space(8)

                      Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.readingFontFamily
                        font.pixelSize: root.bodySize
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        text: modelData.number
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.readingFontFamily
                        font.pixelSize: root.labelSize
                      }
                    }

                    MouseArea {
                      id: contactMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.chooseContact(modelData)
                    }
                  }
                }

                Text {
                  visible: !root.compactHeight
                  text: "MESSAGE"
                  color: root.dim
                  font.family: root.readingFontFamily
                  font.pixelSize: root.labelSize
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                Controls.TextArea {
                  id: composeMessage
                  focusPolicy: Qt.StrongFocus
                  Layout.minimumHeight: Style.space(60)
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  enabled: !root.sending
                  textFormat: TextEdit.PlainText
                  placeholderText: root.sending ? "Sending…" : "Write a message"
                  color: root.foreground
                  placeholderTextColor: root.dim
                  selectionColor: Color.menu.selectedBackground
                  selectedTextColor: Color.menu.selectedText
                  font.family: root.readingFontFamily
                  font.pixelSize: root.bodySize
                  wrapMode: TextEdit.Wrap
                  padding: Style.space(10)
                  background: Rectangle {
                    color: root.sidebarBackground
                    border.width: 1
                    border.color: composeMessage.activeFocus ? Color.accent : root.separator
                    radius: Style.space(14)
                  }
                }

                RowLayout {
                  Layout.alignment: Qt.AlignRight
                  spacing: Style.space(8)

                  Button {
                    fontSize: root.bodySize - 1
                    text: "Cancel"
                    enabled: !root.sending
                    foreground: root.foreground
                    fontFamily: root.readingFontFamily
                    onClicked: root.showConversations()
                  }

                  Button {
                    fontSize: root.bodySize - 1
                    text: root.sending ? "Sending…" : "Send"
                    enabled: !root.sending
                    && (root.recipientNumber !== "" || recipientField.text.trim() !== "")
                    && composeMessage.text.trim() !== ""
                    foreground: root.foreground
                    fontFamily: root.readingFontFamily
                    bordered: true
                    onClicked: root.sendNewMessage()
                  }
                }
              }

              Rectangle {
                visible: root.selectedConversation !== null && !root.readOnlyProvider
                Layout.fillWidth: true
                implicitHeight: replyRow.implicitHeight + Style.space(20)
                color: root.sidebarBackground
                radius: Style.space(16)
                border.width: 1
                border.color: replyField.activeFocus ? root.blend(Color.accent, root.windowBackground, 0.55) : root.separator
                RowLayout {
                  id: replyRow
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(12)

                  Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Style.space(130), Math.max(Style.space(48), replyField.implicitHeight))
                    contentWidth: availableWidth
                    Controls.TextArea {
                      id: replyField
                      objectName: "replyComposer"
                      activeFocusOnPress: true
                      focusPolicy: Qt.StrongFocus
                      enabled: !root.sending
                      placeholderText: qsTr("Write a message…")
                      textFormat: TextEdit.PlainText
                      color: root.foreground
                      placeholderTextColor: root.dim
                      selectionColor: Color.menu.selectedBackground
                      selectedTextColor: Color.menu.selectedText
                      wrapMode: TextEdit.Wrap
                      font.family: root.readingFontFamily
                      font.pixelSize: root.bodySize
                      padding: Style.space(12)
                      background: Item {}
                      Keys.onReturnPressed: function(event) {
                        if (!(event.modifiers & Qt.ShiftModifier)) { root.sendReply(); event.accepted = true }
                        else event.accepted = false
                      }
                      Keys.onEnterPressed: function(event) {
                        if (!(event.modifiers & Qt.ShiftModifier)) { root.sendReply(); event.accepted = true }
                        else event.accepted = false
                      }
                    }
                  }

                  Button {
                    text: qsTr("Send")
                    iconText: "󰒊"
                    fontSize: root.bodySize - 1
                    horizontalPadding: Style.space(14)
                    verticalPadding: Style.space(12)
                    background: root.outgoingBackground
                    opacity: enabled ? 1 : 0.45
                    focusable: true
                    enabled: !root.sending && replyField.text.trim() !== ""
                    && root.selectedConversation !== null && root.selectedConversation.threadId !== null
                    foreground: root.foreground
                    fontFamily: root.readingFontFamily
                    bordered: true
                    onClicked: root.sendReply()
                  }
                }

              }
              Text {
                Layout.fillWidth: true
                visible: root.selectedConversation !== null || root.composing || root.browsingContacts
                text: root.readOnlyProvider
                ? (root.browsingContacts ? qsTr("Showing up to 200 cached contact addresses. Filtering searches this loaded subset.") : qsTr("Bounded local history · R to refresh · Esc to go back"))
                : root.selectedConversation
                ? "Enter to send · Shift+Enter for a new line"
                : root.composing
                ? "Choose a synced contact or enter a phone number · Esc to cancel"
                : root.filteredConversations.length + " of " + root.conversations.length
                + " conversations · / search · PgUp/PgDn · Home/End"
                color: root.dim
                font.family: root.readingFontFamily
                font.pixelSize: Math.max(11, root.labelSize - 1)
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }
        }
      }
      Rectangle {
        visible: root.viewerOpen
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.88)

        MouseArea { anchors.fill: parent; onClicked: root.closeViewer() }

        Image {
          id: viewerImage
          anchors.centerIn: parent
          // The path comes from the phone's attachment, so the helper has
          // already checked it; the decode size stays bounded here.
          source: Model.localImageSource(root.viewerPath)
          asynchronous: true
          sourceSize.width: 3840
          sourceSize.height: 2160
          autoTransform: true
          fillMode: Image.PreserveAspectFit
          width: Math.min(implicitWidth, parent.width - Style.space(64))
          height: Math.min(implicitHeight, parent.height - Style.space(150))
        }

        Text {
          anchors.centerIn: parent
          visible: root.viewerPath === ""
            || viewerImage.status === Image.Loading
            || viewerImage.status === Image.Error
          text: viewerImage.status === Image.Error
            ? "Could not display this image"
            : "Fetching full image from the phone…"
          color: "white"
          font.family: root.readingFontFamily
          font.pixelSize: root.bodySize
        }

        ColumnLayout {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(24)
          spacing: Style.space(8)

          Text {
            visible: root.viewerStatus !== ""
            Layout.alignment: Qt.AlignHCenter
            // The save confirmation carries the phone's file name.
            text: root.viewerStatus
            textFormat: Text.PlainText
            color: "white"
            font.family: root.readingFontFamily
            font.pixelSize: root.labelSize
          }

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(8)

            Button {
              fontSize: root.bodySize - 1
              text: "Open"
              enabled: root.viewerPath !== ""
              foreground: "white"
              fontFamily: root.readingFontFamily
              bordered: true
              onClicked: root.openAttachmentExternally(root.viewerPath)
            }

            Button {
              fontSize: root.bodySize - 1
              text: "Save to Downloads"
              enabled: root.viewerPath !== "" && !saveProcess.running
              foreground: "white"
              fontFamily: root.readingFontFamily
              bordered: true
              onClicked: {
                saveProcess.command = [root.helperPath, "attachment-save", root.viewerPath]
                saveProcess.generation = root.generation
                saveProcess.running = true
              }
            }

            Button {
              fontSize: root.bodySize - 1
              text: "Close"
              foreground: "white"
              fontFamily: root.readingFontFamily
              onClicked: root.closeViewer()
            }
          }
        }
      }
    }
  }
}
