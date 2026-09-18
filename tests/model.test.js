const assert = require("node:assert/strict")
const model = require("../Model.js")

assert.deepEqual(model.parseStatus(""), model.defaultStatus())
assert.equal(model.parseStatus("not json").ok, false)
assert.equal(model.deviceSummary([]), "No phone connected")
assert.equal(model.deviceSummary([{ name: "Pixel" }]), "Pixel")
assert.equal(model.deviceSummary([{ name: "Pixel" }, { name: "Tablet" }]), "2 phones connected")
assert.equal(model.batteryText({ battery: { charge: 71, charging: false } }), "71%")
assert.equal(model.batteryText({ battery: { charge: 42, charging: true } }), "42% · Charging")
assert.equal(model.connectivityText({ connectivity: { strength: 3, type: "5G" } }), "5G")
assert.equal(model.signalStrength({ connectivity: { strength: 3, type: "5G" } }), 3)
assert.equal(model.signalStrength({ connectivity: { strength: 4, type: "5G" } }), 4)
assert.equal(model.signalStrength({}), -1)
assert.equal(model.hasMedia({}), false)
assert.equal(model.hasMedia({ media: null }), false)
assert.equal(model.hasMedia({ media: {} }), false)
assert.equal(model.hasMedia({ media: { player: "Apple Music" } }), true)
assert.equal(model.hasMedia({ media: { title: "Overthinking" } }), true)
assert.equal(model.mediaTitle({ title: "Overthinking", player: "Apple Music" }), "Overthinking")
assert.equal(model.mediaTitle({ title: "", player: "Apple Music" }), "Apple Music")
assert.equal(model.mediaTitle(null), "")
assert.equal(model.mediaSubtitle({ artist: "usedcvnt", album: "Ultraviolet" }), "usedcvnt · Ultraviolet")
assert.equal(model.mediaSubtitle({ artist: "usedcvnt" }), "usedcvnt")
assert.equal(model.mediaSubtitle({}), "")
assert.equal(model.mediaTime(144023), "2:24")
assert.equal(model.mediaTime(65000), "1:05")
assert.equal(model.mediaTime(0), "0:00")
assert.equal(model.mediaTime(-500), "0:00")
assert.equal(model.mediaTime(null), "0:00")
assert.equal(model.visibleNotifications([
  { appName: "Spotify", isConversation: false },
  { appName: "Messages", isConversation: true }
]).length, 1)
const filterSamples = [
  { appName: "Signal" },
  { appName: "Messages" },
  { appName: "Microsoft Authenticator" }
]
assert.equal(model.visibleNotifications(filterSamples, "signal").length, 1)
assert.equal(model.visibleNotifications(filterSamples, "signal, authenticator").length, 2)
assert.equal(model.visibleNotifications(filterSamples, "").length, 3)
assert.equal(model.visibleNotifications(filterSamples, "  ").length, 3)
const searchableConversations = [
  { names: ["Alex Rivera"], addresses: ["+15550000001"], preview: "Dinner tonight" },
  { names: ["Sam"], addresses: ["+15550000002"], preview: "Project update" }
]
assert.equal(model.filterConversations(searchableConversations, "rivera").length, 1)
assert.equal(model.filterConversations(searchableConversations, "0002")[0].names[0], "Sam")
assert.equal(model.filterConversations(searchableConversations, "project").length, 1)
assert.equal(model.filterConversations(searchableConversations, "missing").length, 0)
const contacts = [{ name: "Alex Rivera", number: "+15550000001" }, { name: "Sam", number: "+15550000002" }]
assert.equal(model.parseContacts(JSON.stringify(contacts)).length, 2)
assert.equal(model.filterContacts(contacts, "rivera")[0].number, "+15550000001")
assert.equal(model.filterContacts(contacts, "0002")[0].name, "Sam")
assert.equal(model.filterContacts(contacts, "").length, 0)
assert.deepEqual(model.parseConversations("not json"), [])
assert.equal(model.parseConversations('[{"threadId":1}]').length, 1)
assert.equal(model.parseMessages('[{"body":"Hello"}]')[0].body, "Hello")
const updatedConversations = model.updateConversationAfterSend([
  { threadId: 1, preview: "Old", timestamp: 1000, incoming: true, unread: true },
  { threadId: 2, preview: "Other", timestamp: 1500 }
], 1, "Sent", 2000)
assert.equal(updatedConversations[0].threadId, 1)
assert.equal(updatedConversations[0].preview, "Sent")
assert.equal(updatedConversations[0].incoming, false)
assert.equal(updatedConversations[0].unread, false)
const smsUpdated = model.upsertConversationAfterSms([
  { threadId: 9, addresses: ["(555) 000-0001"], names: ["Becca"], preview: "Old", timestamp: 1000 }
], "+1 555 000 0001", "Becca", "New", 2000)
assert.equal(smsUpdated[0].threadId, 9)
assert.equal(smsUpdated[0].preview, "New")
assert.equal(smsUpdated[0].pendingSync, true)
const newSms = model.upsertConversationAfterSms([], "+15550000002", "New person", "Hello", 2000)[0]
assert.equal(newSms.pending, true)
assert.equal(newSms.threadId, null)
const staleMerge = model.mergePendingConversation([
  { threadId: 9, addresses: ["+15550000001"], preview: "Old", timestamp: 1000 }
], smsUpdated[0])
assert.equal(staleMerge.resolved, false)
assert.equal(staleMerge.conversations[0].preview, "New")
const freshMerge = model.mergePendingConversation([
  { threadId: 9, addresses: ["+15550000001"], preview: "New", timestamp: 2000 }
], smsUpdated[0])
assert.equal(freshMerge.resolved, true)
const pendingOutgoing = { body: "On my way", timestamp: 2000 }
const pendingMessageMerge = model.mergePendingOutgoing([
  { body: "Earlier", timestamp: 1000, incoming: true }
], pendingOutgoing)
assert.equal(pendingMessageMerge.resolved, false)
assert.equal(pendingMessageMerge.messages.length, 2)
assert.equal(pendingMessageMerge.messages[1].body, "On my way")
assert.equal(pendingMessageMerge.messages[1].pending, true)
const confirmedMessageMerge = model.mergePendingOutgoing([
  { body: "On my way", timestamp: 2500, incoming: false }
], pendingOutgoing)
assert.equal(confirmedMessageMerge.resolved, true)
assert.equal(confirmedMessageMerge.messages.length, 1)
const oldDuplicateMerge = model.mergePendingOutgoing([
  { body: "On my way", timestamp: 200000, incoming: false }
], pendingOutgoing)
assert.equal(oldDuplicateMerge.resolved, false)
assert.equal(oldDuplicateMerge.messages.length, 2)
assert.equal(model.attachmentKind("image/jpeg"), "image")
assert.equal(model.attachmentKind("video/mp4"), "video")
assert.equal(model.attachmentKind("audio/ogg"), "audio")
assert.equal(model.attachmentKind(""), "file")
assert.equal(model.attachmentLabel("image/png"), "Photo")
assert.equal(model.attachmentLabel("application/pdf"), "Attachment")
assert.equal(model.thumbnailUri({ thumbnail: "abc123" }), "data:image/png;base64,abc123")
assert.equal(model.thumbnailUri({ thumbnail: "A".repeat(1048577) }), "")
assert.equal(model.thumbnailUri({ thumbnail: "not base64!" }), "")
assert.equal(model.thumbnailUri({ thumbnail: "AAAA\nAAAA" }), "")
assert.equal(
  model.localImageSource("file:///home/bts/.cache/kdeconnect.daemon/kdeconnect/albumart/1.jpg"),
  "file:///home/bts/.cache/kdeconnect.daemon/kdeconnect/albumart/1.jpg")
assert.equal(model.localImageSource("/home/bts/.cache/art.jpg"), "file:///home/bts/.cache/art.jpg")
assert.equal(model.localImageSource("file:///home/bts/a b.jpg"), "file:///home/bts/a%20b.jpg")
assert.equal(model.localImageSource("http://192.168.1.1/art.jpg"), "")
assert.equal(model.localImageSource("https://example.com/art.jpg"), "")
assert.equal(model.localImageSource("data:image/png;base64,AAAA"), "")
assert.equal(model.localImageSource("qrc:/art.jpg"), "")
assert.equal(model.localImageSource("image://icon/art"), "")
assert.equal(model.localImageSource("file://"), "")
assert.equal(model.localImageSource(""), "")
assert.equal(model.localImageSource(null), "")
assert.equal(model.localImageSource(undefined), "")
assert.equal(model.thumbnailUri({}), "")
assert.equal(model.messageAttachments({ attachments: [{ partId: 1 }] }).length, 1)
assert.equal(model.messageAttachments({}).length, 0)
assert.equal(model.previewText({ preview: "Hi" }), "Hi")
assert.equal(model.previewText({ preview: "", attachments: [{ mimeType: "image/jpeg" }] }), "Photo")
assert.equal(model.previewText({ preview: "", attachments: [], attachmentCount: 2 }), "Attachment")
assert.equal(model.previewText({ preview: "" }), "")
const redacted = { title: "", text: "Sensitive notification content hidden", isConversation: true, appName: "Messages" }
assert.equal(model.redactedNotification(redacted), true)
assert.equal(model.redactedNotification({ text: "Hello there" }), false)
assert.equal(model.notificationDisplayTitle(redacted), "New message")
assert.equal(model.notificationDisplayTitle({ title: "Alex" }), "Alex")
assert.equal(model.notificationDisplayTitle({ title: "", appName: "Gmail" }), "Gmail")
assert.equal(model.notificationDisplayText(redacted), "")
assert.equal(model.notificationDisplayText({ text: "Sensitive notification content hidden", appName: "Gmail" }), "Content hidden by the phone")
assert.equal(model.notificationDisplayText({ text: "Hi" }), "Hi")
assert.equal(model.unreadConversations([{ unread: true }, { unread: false }, {}]).length, 1)
assert.deepEqual(model.parseSeen("not json"), {})
assert.deepEqual(model.parseSeen("[1,2]"), {})
assert.equal(model.parseSeen('{"7":2000}')["7"], 2000)
const unseen = model.filterUnseenUnread([
  { threadId: 7, unread: true, timestamp: 3000 },
  { threadId: 8, unread: true, timestamp: 1000 },
  { threadId: 9, unread: false, timestamp: 5000 }
], { "8": 2000 })
assert.equal(unseen.length, 1)
assert.equal(unseen[0].threadId, 7)
assert.equal(model.filterUnseenUnread([
  { threadId: 7, unread: true, timestamp: 3000 }
], { "7": 2500 }).length, 1)
assert.equal(model.filterUnseenUnread([
  { threadId: 7, unread: true, timestamp: 3000 }
], { "7": 3000 }).length, 0)
assert.equal(model.findConversationByThreadId([{ threadId: 7 }, { threadId: 9 }], "9").threadId, 9)
assert.equal(model.findConversationByThreadId([{ threadId: 7 }], 8), null)
assert.equal(model.findConversationByTitle(searchableConversations, "alex rivera").addresses[0], "+15550000001")
assert.equal(model.findConversationByTitle(searchableConversations, "+15550000002").names[0], "Sam")
assert.equal(model.findConversationByTitle(searchableConversations, "Nobody"), null)
assert.equal(model.findConversationByTitle(searchableConversations, ""), null)
assert.equal(model.conversationTitle({ addresses: ["+15551234567"] }), "+15551234567")
assert.equal(model.conversationTitle({ addresses: ["+15551234567"], names: ["Alex"] }), "Alex")
assert.equal(model.conversationTitle({ addresses: ["Alex", "Sam"] }), "Alex +1")
assert.equal(model.relativeTime(1000, 61000), "1m")

console.log("model tests passed")
