function defaultStatus() {
  return {
    schemaVersion: 0,
    observedAt: 0,
    discoveryTruncated: false,
    backend: {name: "kdeconnect", available: false, version: null, versionSource: "kdeconnect-cli"},
    ok: true,
    installed: false,
    devices: [],
    statusText: "KDE Connect is not installed"
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()

  try {
    var parsed = JSON.parse(text)
    if (!parsed || Array.isArray(parsed) || typeof parsed !== "object"
        || typeof parsed.ok !== "boolean" || typeof parsed.installed !== "boolean"
        || !Array.isArray(parsed.devices) || parsed.schemaVersion !== 1
        || !validBackend(parsed.backend) || !validObservation(parsed.observedAt)
        || typeof parsed.discoveryTruncated !== "boolean") throw new Error("Invalid status")
    if (parsed.backend.available && (!parsed.ok || !parsed.installed || parsed.observedAt === 0))
      throw new Error("Contradictory backend status")
    var ids = []
    parsed.devices = parsed.devices.filter(function(device) {
      if (!device || !validDeviceId(device.id) || typeof device.name !== "string"
          || ids.indexOf(device.id) !== -1 || ids.length >= 8) return false
      ids.push(device.id)
      device.name = device.name.slice(0, 256)
      device.backendAvailable = parsed.backend.available === true
      device.paired = nullableBoolean(device.paired)
      device.reachable = nullableBoolean(device.reachable)
      device.type = deviceType(device.type)
      device.connectionState = connectionState(device)
      device.capabilities = normalizedCapabilities(device)
      return true
    })
    return parsed
  } catch (error) {
    var failed = defaultStatus()
    failed.ok = false
    failed.statusText = "Could not read phone status"
    return failed
  }
}

function validDeviceId(id) {
  return typeof id === "string" && /^[A-Za-z0-9]{1,128}$/.test(id)
}

function deviceById(devices, id) {
  if (!validDeviceId(id) || !Array.isArray(devices)) return null
  for (var i = 0; i < devices.length; i++)
    if (devices[i] && devices[i].id === id) return devices[i]
  return null
}

function selectedDeviceId(devices, preferredId) {
  // A missing selected phone remains selected. Never choose another phone just
  // because it became the only reachable one or discovery reordered the list.
  if (validDeviceId(preferredId)) return preferredId
  var paired = Array.isArray(devices) ? devices.filter(function(device) { return device && device.paired === true }) : []
  return paired.length === 1 && validDeviceId(paired[0].id) ? paired[0].id : ""
}

var capabilityPlugins = {
  messaging: "kdeconnect_sms", contacts: "kdeconnect_contacts", notifications: "kdeconnect_notifications",
  sharing: "kdeconnect_share", clipboard: "kdeconnect_clipboard", ring: "kdeconnect_findmyphone",
  media: "kdeconnect_mprisremote", battery: "kdeconnect_battery", files: "kdeconnect_sftp",
  connectivity: "kdeconnect_connectivity_report"
}

function nullableBoolean(value) { return typeof value === "boolean" ? value : null }
function deviceType(value) {
  return ["phone", "tablet", "desktop", "laptop", "tv"].indexOf(value) !== -1 ? value : "unknown"
}
function validObservation(value) {
  return typeof value === "number" && isFinite(value) && value >= 0 && value <= 9007199254740991
    && Math.floor(value) === value
}
function validBackend(value) {
  return !!value && value.name === "kdeconnect" && typeof value.available === "boolean"
    && value.versionSource === "kdeconnect-cli" && (value.version === null
      || (typeof value.version === "string" && /^[0-9]{1,4}\.[0-9]{1,4}(\.[0-9]{1,6})?([-+][A-Za-z0-9][A-Za-z0-9._+-]{0,31})?$/.test(value.version)))
}
function connectionState(device) {
  if (device.paired === false) return "unpaired"
  if (device.reachable === false) return "offline"
  return device.paired === true && device.reachable === true ? "ready" : "unknown"
}
function deviceReady(device) {
  return !!device && device.backendAvailable === true && device.paired === true && device.reachable === true
}
function capabilityReason(device, key) {
  if (!device || device.backendAvailable !== true) return "backend-unavailable"
  if (device.paired === false) return "unpaired"
  if (device.reachable === false) return "offline"
  if (device.paired !== true || device.reachable !== true) return "connection-unknown"
  var capability = device.capabilities && Object.prototype.hasOwnProperty.call(capabilityPlugins, key)
    ? device.capabilities[key] : null
  if (!capability || capability.plugin !== capabilityPlugins[key]) return "capability-unknown"
  if (capability.supported === false) return "not-supported"
  if (capability.enabled === false) return "plugin-disabled"
  if (capability.supported === true && capability.enabled === true && capability.loaded === true) return "plugin-ready"
  if (capability.loaded === false) return "plugin-not-loaded"
  return "capability-unknown"
}
function capabilityState(device, key) {
  var reason = capabilityReason(device, key)
  return reason === "plugin-ready" ? "available" : reason === "not-supported" ? "unsupported"
    : reason === "plugin-disabled" ? "disabled" : "unknown"
}
function capabilityAvailable(device, key) { return capabilityState(device, key) === "available" }
function normalizedCapabilities(device) {
  var result = {}
  Object.keys(capabilityPlugins).forEach(function(key) {
    var raw = device.capabilities && device.capabilities[key]
    var valid = raw && raw.plugin === capabilityPlugins[key]
    result[key] = {plugin:capabilityPlugins[key], permission:"unknown",
      supported:nullableBoolean(valid ? raw.supported : null),
      loaded:nullableBoolean(valid ? raw.loaded : null), enabled:nullableBoolean(valid ? raw.enabled : null)}
  })
  var normalized = {paired:device.paired, reachable:device.reachable,
    backendAvailable:device.backendAvailable, capabilities:result}
  Object.keys(result).forEach(function(key) {
    result[key].state = capabilityState(normalized, key)
    result[key].reason = capabilityReason(normalized, key)
  })
  return result
}

function parseDiagnostics(raw) {
  if (typeof raw !== "string" || raw.length > 65536) return null
  try {
    var parsed = JSON.parse(raw)
    if (!parsed || parsed.schemaVersion !== 1 || typeof parsed.ok !== "boolean"
        || typeof parsed.installed !== "boolean" || !validBackend(parsed.backend)
        || !validObservation(parsed.observedAt) || typeof parsed.discoveryTruncated !== "boolean"
        || !Array.isArray(parsed.devices) || parsed.devices.length > 8) return null
    if (parsed.backend.available && (!parsed.ok || !parsed.installed || parsed.observedAt === 0)) return null
    var failureReason = null
    if (!parsed.ok) {
      if (parsed.backend.available || ["backend-unavailable", "discovery-failed", "backend-restarted"].indexOf(parsed.failureReason) === -1) return null
      failureReason = parsed.failureReason
    }
    var devices = []
    for (var i = 0; i < parsed.devices.length; i++) {
      var device = parsed.devices[i]
      if (!device || device.label !== "device-" + (i + 1)
          || (device.paired !== null && typeof device.paired !== "boolean")
          || (device.reachable !== null && typeof device.reachable !== "boolean")) return null
      var safe = {label:device.label, type:deviceType(device.type), paired:device.paired,
        reachable:device.reachable, backendAvailable:parsed.backend.available,
        capabilities:device.capabilities}
      safe.connectionState = connectionState(safe)
      safe.capabilities = normalizedCapabilities(safe)
      delete safe.backendAvailable
      devices.push(safe)
    }
    return {schemaVersion:1, ok:parsed.ok, failureReason:failureReason, installed:parsed.installed, observedAt:parsed.observedAt,
      discoveryTruncated:parsed.discoveryTruncated,
      backend:{name:"kdeconnect",available:parsed.backend.available,
        version:parsed.backend.version,versionSource:"kdeconnect-cli"}, devices:devices}
  } catch (error) { return null }
}

function deviceSummary(devices) {
  if (!devices || devices.length === 0) return "No phone connected"
  if (devices.length === 1) return devices[0].name
  return devices.length + " phones connected"
}

function batteryText(device) {
  if (!device || !device.battery || device.battery.charge === null || device.battery.charge === undefined)
    return "Battery unavailable"
  return device.battery.charge + "%" + (device.battery.charging ? " · Charging" : "")
}

function connectivityText(device) {
  if (!device || !device.connectivity) return ""
  var type = String(device.connectivity.type || "")
  return type !== "Unknown" ? type : ""
}

function signalStrength(device) {
  if (!device || !device.connectivity) return -1
  if (device.connectivity.strength === null || device.connectivity.strength === undefined) return -1
  var strength = Number(device.connectivity.strength)
  return isFinite(strength) && strength >= 0 ? Math.floor(strength) : -1
}

function hasMedia(device) {
  if (!device || !device.media || typeof device.media !== "object") return false
  return String(device.media.title || "") !== "" || String(device.media.player || "") !== ""
}

function mediaTitle(media) {
  if (!media) return ""
  return String(media.title || media.player || "")
}

function mediaSubtitle(media) {
  if (!media) return ""
  var parts = []
  if (media.artist) parts.push(String(media.artist))
  if (media.album) parts.push(String(media.album))
  return parts.join(" · ")
}

function mediaTime(milliseconds) {
  var totalSeconds = Math.max(0, Math.round((Number(milliseconds) || 0) / 1000))
  var minutes = Math.floor(totalSeconds / 60)
  var seconds = totalSeconds % 60
  return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
}

function filterConversations(conversations, query) {
  if (!Array.isArray(conversations)) return []
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return conversations
  return conversations.filter(function(conversation) {
    var values = []
    if (conversation && conversation.names) values = values.concat(conversation.names)
    if (conversation && conversation.addresses) values = values.concat(conversation.addresses)
    values.push(conversation ? conversation.preview : "")
    return values.join("\n").toLowerCase().indexOf(needle) !== -1
  })
}

function parseContacts(raw) {
  return parseConversations(raw)
}

function filterContacts(contacts, query) {
  if (!Array.isArray(contacts)) return []
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return []
  return contacts.filter(function(contact) {
    return (String(contact.name || "") + "\n" + String(contact.number || ""))
      .toLowerCase().indexOf(needle) !== -1
  })
}

function parseConversations(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    return Array.isArray(parsed) ? parsed : []
  } catch (error) {
    return []
  }
}

function parseMessages(raw) {
  return parseConversations(raw)
}

function updateConversationAfterSend(conversations, threadId, body, timestamp) {
  if (!Array.isArray(conversations)) return []
  var updated = null
  var remaining = []
  for (var i = 0; i < conversations.length; i++) {
    var conversation = conversations[i]
    if (!updated && Number(conversation.threadId) === Number(threadId)) {
      updated = {}
      for (var key in conversation) updated[key] = conversation[key]
      updated.preview = String(body || "")
      updated.timestamp = Number(timestamp)
      updated.incoming = false
      updated.unread = false
    } else {
      remaining.push(conversation)
    }
  }
  return updated ? [updated].concat(remaining) : conversations.slice()
}

function phoneKey(value) {
  return String(value || "").replace(/[^0-9]/g, "").replace(/^0+/, "")
}

// Country codes and domestic trunk prefixes vary, so compare the shorter
// significant number with the longer number's suffix. Seven digits is the
// shortest match Android itself treats as meaningful; shorter codes are left
// untouched rather than being attributed to an arbitrary contact.
function phoneNumbersMatch(left, right) {
  var leftKey = phoneKey(left)
  var rightKey = phoneKey(right)
  if (leftKey === "" || rightKey === "") return false
  if (leftKey === rightKey) return true
  var shorter = leftKey.length <= rightKey.length ? leftKey : rightKey
  var longer = leftKey.length <= rightKey.length ? rightKey : leftKey
  return shorter.length >= 7 && longer.slice(-shorter.length) === shorter
}

function conversationMatchesNumber(conversation, number) {
  if (!conversation || !Array.isArray(conversation.addresses)) return false
  if (phoneKey(number) === "") return false
  for (var i = 0; i < conversation.addresses.length; i++) {
    if (phoneNumbersMatch(conversation.addresses[i], number)) return true
  }
  return false
}

function upsertConversationAfterSms(conversations, number, name, body, timestamp) {
  var current = Array.isArray(conversations) ? conversations : []
  var updated = null
  var remaining = []
  for (var i = 0; i < current.length; i++) {
    var conversation = current[i]
    if (!updated && conversation.addresses && conversation.addresses.length === 1
        && conversationMatchesNumber(conversation, number)) {
      updated = {}
      for (var key in conversation) updated[key] = conversation[key]
    } else {
      remaining.push(conversation)
    }
  }
  if (!updated) {
    updated = {
      threadId: null,
      addresses: [String(number || "")],
      names: [String(name || number || "")],
      attachmentCount: 0,
      pending: true
    }
  }
  updated.preview = String(body || "")
  updated.timestamp = Number(timestamp)
  updated.incoming = false
  updated.unread = false
  updated.pendingSync = true
  return [updated].concat(remaining)
}

function mergePendingConversation(conversations, pending) {
  var current = Array.isArray(conversations) ? conversations : []
  if (!pending || !pending.addresses || pending.addresses.length === 0)
    return { conversations: current, resolved: true }

  var matchIndex = -1
  for (var i = 0; i < current.length; i++) {
    if (current[i].addresses && current[i].addresses.length === 1
        && conversationMatchesNumber(current[i], pending.addresses[0])) {
      matchIndex = i
      break
    }
  }
  if (matchIndex >= 0) {
    var match = current[matchIndex]
    if (Number(match.timestamp) >= Number(pending.timestamp) || match.preview === pending.preview)
      return { conversations: current, resolved: true }
    var withoutStale = current.slice()
    withoutStale.splice(matchIndex, 1)
    return { conversations: [pending].concat(withoutStale), resolved: false }
  }
  return { conversations: [pending].concat(current), resolved: false }
}

function mergePendingOutgoing(messages, pending) {
  var current = Array.isArray(messages) ? messages : []
  if (!pending) return { messages: current, resolved: true }

  for (var i = 0; i < current.length; i++) {
    var message = current[i]
    if (message && message.incoming === false
        && String(message.body || "") === String(pending.body || "")
        && Math.abs(Number(message.timestamp) - Number(pending.timestamp)) <= 120000)
      return { messages: current, resolved: true }
  }

  var optimistic = {
    body: String(pending.body || ""),
    timestamp: Number(pending.timestamp),
    incoming: false,
    attachmentCount: 0,
    pending: true
  }
  var merged = current.concat([optimistic])
  merged.sort(function(left, right) { return Number(left.timestamp) - Number(right.timestamp) })
  return { messages: merged, resolved: false }
}

function messageAttachments(message) {
  return message && Array.isArray(message.attachments) ? message.attachments : []
}

function attachmentKind(mimeType) {
  var mime = String(mimeType || "").toLowerCase()
  if (mime.indexOf("image/") === 0) return "image"
  if (mime.indexOf("video/") === 0) return "video"
  if (mime.indexOf("audio/") === 0) return "audio"
  return "file"
}

function attachmentLabel(mimeType) {
  var kind = attachmentKind(mimeType)
  if (kind === "image") return "Photo"
  if (kind === "video") return "Video"
  if (kind === "audio") return "Audio"
  return "Attachment"
}

function thumbnailUri(attachment) {
  // The phone sends this thumbnail; KDE Connect hands it over as base64 wrapped
  // across lines, so whitespace comes out before the size and shape checks. The
  // input length is checked first, because stripping whitespace from a string
  // the phone chose is itself the expensive part.
  var raw = String((attachment && attachment.thumbnail) || "")
  if (raw.length > 4194304) return ""
  var thumbnail = raw.replace(/\s+/g, "")
  if (thumbnail === "" || thumbnail.length > 1048576) return ""
  if (!/^[A-Za-z0-9+/=]+$/.test(thumbnail)) return ""
  // The decoded bytes decide the decoder, so the base64 prefix has to be a
  // raster image: SVG or other markup would otherwise reach the image loader
  // through this one field, which no path check covers.
  if (!/^(iVBORw0KGgo|\/9j\/|R0lGOD|UklGR|Qk)/.test(thumbnail)) return ""
  return "data:image/png;base64," + thumbnail
}

// The media block of the panel reads the phone's player even when there is
// none, which is what produced "Cannot read property of null" in the journal.
function mediaState(device) {
  var media = device && device.media && typeof device.media === "object" ? device.media : null
  if (!media) {
    return {
      player: "", title: "", artist: "", album: "", volume: 0, length: 0,
      position: 0, isPlaying: false, canSeek: false, albumArt: ""
    }
  }
  return media
}

// Every Image.source that comes from the phone goes through here. The helper
// already drops remote URLs and files outside KDE Connect's directories; this
// keeps the panel from loading any other scheme even if that changed, so a
// phone cannot make the shell fetch a URL or decode a file it chose.
//
// This is also the only place that builds the URI, and it encodes the
// characters Qt would decode again. Without that, a file name containing %2F
// would resolve to a different path than the one the helper checked.
function localImageSource(value) {
  // Only trailing newlines come off: trimming would eat a trailing space that is
  // part of the file name and make Qt open a different file than the one the
  // helper validated.
  var text = String(value === undefined || value === null ? "" : value).replace(/[\r\n]+$/, "")
  if (text === "") return ""
  if (text.indexOf("file://") === 0) text = text.slice(7)
  if (text.charAt(0) !== "/" || text.indexOf("\n") !== -1 || text.indexOf("\0") !== -1) return ""
  // Percent-encode per segment, in UTF-8. A hand-rolled "%" + charCode is not
  // UTF-8 for anything outside Latin-1, so U+3000 would encode as %3000 and Qt
  // would decode it as a different path.
  var segments = text.split("/")
  for (var index = 0; index < segments.length; index++) {
    segments[index] = encodeURIComponent(segments[index])
  }
  return "file://" + segments.join("/")
}

function previewText(conversation) {
  if (!conversation) return ""
  var preview = String(conversation.preview || "")
  if (preview !== "") return preview
  var attachments = messageAttachments(conversation)
  if (attachments.length > 0) return attachmentLabel(attachments[0].mimeType)
  if (Number(conversation.attachmentCount) > 0) return "Attachment"
  return ""
}

function redactedNotification(notification) {
  var text = String((notification && notification.text) || "")
  return text.indexOf("Sensitive notification content hidden") === 0
}

function notificationDisplayTitle(notification) {
  if (!notification) return ""
  var title = String(notification.title || "")
  if (title !== "") return title
  if (notification.isConversation) return "New message"
  return String(notification.appName || "")
}

function notificationDisplayText(notification) {
  if (!notification) return ""
  if (redactedNotification(notification))
    return notification.isConversation ? "" : "Content hidden by the phone"
  return String(notification.text || "")
}

// SMS history and Android notifications are two views of the same inbox.
// Keep unknown/ambiguous senders visible; never combine another chat transport.
function smsNotification(notification) {
  return notification && ["com.google.android.apps.messaging", "com.samsung.android.messaging",
    "com.android.messaging", "com.android.mms"].indexOf(notification.packageName) !== -1
}

function messageInbox(unread, notifications) {
  var messages = (unread || []).map(function(row) {
    return Object.assign({}, row, {notificationIds: []})
  })
  var other = []
  ;(notifications || []).forEach(function(notification) {
    if (!smsNotification(notification)) { other.push(notification); return }
    var needle = String(notification.title || "").trim().toLowerCase()
    var matches = messages.filter(function(row) {
      return !row.notificationOnly && needle !== ""
        && (row.names || []).concat(row.addresses || []).some(function(value) {
          return String(value).trim().toLowerCase() === needle
        })
    })
    if (matches.length === 1) {
      matches[0].notificationIds.push(notification.id)
    } else {
      messages.push({threadId: null, names: [notificationDisplayTitle(notification)],
        preview: notificationDisplayText(notification), timestamp: 0,
        notificationOnly: true, notificationIds: [notification.id]})
    }
  })
  return {messages: messages, notifications: other}
}

function unreadConversations(conversations) {
  if (!Array.isArray(conversations)) return []
  return conversations.filter(function(conversation) {
    return conversation && conversation.unread === true
  })
}

function parseSeen(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
  } catch (error) {
    return {}
  }
}

function filterUnseenUnread(conversations, seen) {
  if (!Array.isArray(conversations)) return []
  var map = seen && typeof seen === "object" ? seen : {}
  return conversations.filter(function(conversation) {
    if (!conversation || conversation.unread !== true) return false
    var seenTs = Number(map[String(conversation.threadId)])
    return !isFinite(seenTs) || Number(conversation.timestamp) > seenTs
  })
}

function findConversationByThreadId(conversations, threadId) {
  if (!Array.isArray(conversations)) return null
  var needle = String(threadId)
  if (needle === "") return null
  for (var i = 0; i < conversations.length; i++) {
    if (conversations[i] && String(conversations[i].threadId) === needle) return conversations[i]
  }
  return null
}

function findConversationByTitle(conversations, title) {
  if (!Array.isArray(conversations)) return null
  var needle = String(title || "").trim().toLowerCase()
  if (needle === "") return null
  var matches = conversations.filter(function(conversation) {
    return conversation && (conversation.names || []).concat(conversation.addresses || []).some(function(value) {
      return String(value).trim().toLowerCase() === needle
    })
  })
  return matches.length === 1 ? matches[0] : null
}

function conversationTitle(conversation) {
  if (!conversation) return "Unknown sender"
  var values = conversation.names && conversation.names.length ? conversation.names : conversation.addresses
  if (!values || !values.length)
    return "Unknown sender"
  if (values.length === 1) return String(values[0])
  return String(values[0]) + " +" + (values.length - 1)
}

function relativeTime(timestamp, now) {
  var value = Number(timestamp)
  if (!isFinite(value) || value <= 0) return ""
  var elapsed = Math.max(0, Number(now || Date.now()) - value)
  var minutes = Math.floor(elapsed / 60000)
  if (minutes < 1) return "Now"
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  if (days < 7) return days + "d"
  var date = new Date(value)
  return (date.getMonth() + 1) + "/" + date.getDate()
}

if (typeof module !== "undefined") {
  module.exports = {
    deviceReady: deviceReady,
    capabilityState: capabilityState,
    capabilityReason: capabilityReason,
    capabilityAvailable: capabilityAvailable,
    parseDiagnostics: parseDiagnostics,
    validDeviceId: validDeviceId,
    deviceById: deviceById,
    selectedDeviceId: selectedDeviceId,
    defaultStatus: defaultStatus,
    parseStatus: parseStatus,
    deviceSummary: deviceSummary,
    batteryText: batteryText,
    connectivityText: connectivityText,
    signalStrength: signalStrength,
    hasMedia: hasMedia,
    mediaTitle: mediaTitle,
    mediaSubtitle: mediaSubtitle,
    mediaTime: mediaTime,
    filterConversations: filterConversations,
    parseContacts: parseContacts,
    filterContacts: filterContacts,
    parseConversations: parseConversations,
    parseMessages: parseMessages,
    updateConversationAfterSend: updateConversationAfterSend,
    phoneKey: phoneKey,
    phoneNumbersMatch: phoneNumbersMatch,
    conversationMatchesNumber: conversationMatchesNumber,
    upsertConversationAfterSms: upsertConversationAfterSms,
    mergePendingConversation: mergePendingConversation,
    mergePendingOutgoing: mergePendingOutgoing,
    messageAttachments: messageAttachments,
    attachmentKind: attachmentKind,
    attachmentLabel: attachmentLabel,
    thumbnailUri: thumbnailUri,
    mediaState: mediaState,
    localImageSource: localImageSource,
    previewText: previewText,
    redactedNotification: redactedNotification,
    notificationDisplayTitle: notificationDisplayTitle,
    notificationDisplayText: notificationDisplayText,
    smsNotification: smsNotification,
    messageInbox: messageInbox,
    unreadConversations: unreadConversations,
    parseSeen: parseSeen,
    filterUnseenUnread: filterUnseenUnread,
    findConversationByThreadId: findConversationByThreadId,
    findConversationByTitle: findConversationByTitle,
    conversationTitle: conversationTitle,
    relativeTime: relativeTime
  }
}
