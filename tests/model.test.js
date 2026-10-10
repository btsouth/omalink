const assert = require("node:assert/strict")
const model = require("../Model.js")

assert.deepEqual(model.parseStatus(""), model.defaultStatus())
assert.equal(model.parseStatus("not json").ok, false)
for (const value of ["null", "[]", "4", "{}", '{"ok":true,"installed":true,"devices":{}}'])
  assert.equal(model.parseStatus(value).ok, false)
const phones = [{id:"abc123",name:"Pixel",paired:true},{id:"def456",name:"Galaxy",paired:true}]
assert.equal(model.selectedDeviceId(phones, ""), "", "several phones need explicit selection")
assert.equal(model.selectedDeviceId([phones[0]], ""), "abc123")
assert.equal(model.selectedDeviceId(phones.slice().reverse(), "abc123"), "abc123")
assert.equal(model.selectedDeviceId([phones[1]], "abc123"), "abc123", "offline selection must not retarget")
assert.equal(model.selectedDeviceId([], "abc123"), "abc123")
assert.equal(model.deviceById([phones[1]], "abc123"), null)
assert.equal(model.deviceById(phones, "def456").name, "Galaxy")
assert.equal(model.validDeviceId("../abc"), false)
assert.equal(model.validDeviceId("a".repeat(129)), false)
const normalized = model.parseStatus(JSON.stringify({...model.defaultStatus(),schemaVersion:1,ok:true,installed:true,devices:[
  ...phones, phones[0], {id:"../../escape",name:"Bad"}, {id:"ghi789",name:"N".repeat(500)}, null
]}))
assert.equal(normalized.devices.length, 3)
assert.equal(normalized.devices[2].name.length, 256)
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
assert.equal(model.phoneNumbersMatch("+61 436 000 001", "0436 000 001"), true)
assert.equal(model.phoneNumbersMatch("+1 555 000 0001", "(555) 000-0001"), true)
assert.equal(model.phoneNumbersMatch("+1 212 555 1234", "+1 312 555 1234"), false)
assert.equal(model.phoneKey("OKTA"), "")
assert.equal(model.phoneNumbersMatch("OKTA", "OKTA"), false)
const intlSms = model.upsertConversationAfterSms([
  { threadId: 12, addresses: ["+61436000001"], names: ["Jordan"], preview: "Old", timestamp: 1000 }
], "0436 000 001", "Jordan", "New", 2000)
assert.equal(intlSms[0].threadId, 12)
const distinctSms = model.upsertConversationAfterSms([
  { threadId: 13, addresses: ["+12125551234"], names: ["First"], preview: "Old", timestamp: 1000 }
], "+1 312 555 1234", "Second", "New", 2000)
assert.equal(distinctSms.length, 2)
assert.equal(distinctSms[0].threadId, null)
assert.equal(distinctSms[1].threadId, 13)
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
assert.equal(model.thumbnailUri({ thumbnail: "iVBORw0KGgoAAAANSUhEUg" }), "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg")
assert.equal(model.thumbnailUri({ thumbnail: "abc123" }), "")
// A valid prefix with an oversized or malformed body, so the length and charset
// checks are the things being tested rather than the prefix allowlist.
assert.equal(model.thumbnailUri({ thumbnail: "iVBORw0KGgo" + "A".repeat(1048577) }), "")
assert.equal(model.thumbnailUri({ thumbnail: "iVBORw0KGgo!!!" }), "")
assert.equal(model.thumbnailUri({ thumbnail: "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmc" }), "")
assert.equal(model.thumbnailUri({ thumbnail: "/9j/4AAQSkZJRgABAQ" }), "data:image/png;base64,/9j/4AAQSkZJRgABAQ")
assert.equal(model.thumbnailUri({ thumbnail: "A".repeat(1048577) }), "")
assert.equal(model.thumbnailUri({ thumbnail: "\n".repeat(5000000) + "iVBORw0KGgo" }), "")
assert.equal(model.thumbnailUri({ thumbnail: "iVBORw0KGgo".padEnd(4294968, "\n") }), "")
assert.equal(model.thumbnailUri({ thumbnail: "not base64!" }), "")
assert.equal(model.thumbnailUri({ thumbnail: "iVBORw0KGgo\nAAAA\r\nBBBB" }), "data:image/png;base64,iVBORw0KGgoAAAABBBB")
assert.equal(model.mediaState({}).volume, 0)
assert.equal(model.mediaState({}).canSeek, false)
assert.equal(model.mediaState({ media: null }).length, 0)
assert.equal(model.mediaState({ media: { volume: 40, length: 144023 } }).volume, 40)
assert.equal(model.mediaState({ media: { volume: 40 } }).albumArt, undefined)
assert.equal(
  model.localImageSource("file:///home/bts/.cache/kdeconnect.daemon/kdeconnect/albumart/1.jpg"),
  "file:///home/bts/.cache/kdeconnect.daemon/kdeconnect/albumart/1.jpg")
assert.equal(model.localImageSource("/home/bts/.cache/art.jpg"), "file:///home/bts/.cache/art.jpg")
assert.equal(model.localImageSource("file:///home/bts/a b.jpg"), "file:///home/bts/a%20b.jpg")
assert.equal(model.localImageSource("/home/bts/a b.jpg"), "file:///home/bts/a%20b.jpg")
assert.equal(model.localImageSource("/home/bts/a%2Fb.jpg"), "file:///home/bts/a%252Fb.jpg")
assert.equal(model.localImageSource("/home/bts/a#b?c.jpg"), "file:///home/bts/a%23b%3Fc.jpg")
// The URI must decode back to the path the helper validated: U+3000 has to be
// encoded in UTF-8, and a trailing space belongs to the file name.
assert.equal(model.localImageSource("/a\u3000b.jpg"), "file:///a%E3%80%80b.jpg")
assert.equal(model.localImageSource("/a /b.jpg"), "file:///a%20/b.jpg")
assert.equal(model.localImageSource("/a/b.jpg\n"), "file:///a/b.jpg")
assert.equal(model.localImageSource("/a/b.jpg\n\n"), "file:///a/b.jpg")
assert.equal(model.localImageSource("file:///home/bts/a%2Fb.jpg"), "file:///home/bts/a%252Fb.jpg")
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
assert.equal(model.notificationDisplayTitle(redacted), "Hidden text")
assert.equal(model.notificationDisplayTitle({ title: "", text: "", isConversation: true }), "New message")
assert.equal(model.notificationDisplayTitle({ title: "Alex" }), "Alex")
assert.equal(model.notificationDisplayTitle({ title: "", appName: "Gmail" }), "Gmail")
assert.equal(model.notificationDisplayText(redacted), "Android hid it, likely a code. Check your phone.")
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


assert.strictEqual(model.signalStrength({ connectivity: { strength: null } }), -1)
const group = { threadId: 99, addresses: ['+15550000001', '+15550000002'], names: ['Group'] }
const directSms = model.upsertConversationAfterSms([group], '+15550000001', 'Alex', 'Hello', 1000)
assert.strictEqual(directSms.length, 2)
assert.strictEqual(directSms[0].threadId, null)
assert.strictEqual(directSms[1].threadId, 99)

console.log("model tests passed")

const sms = {id:"sms1",packageName:"com.google.android.apps.messaging",title:"Becca",text:"new"}
const chat = {...sms,id:"chat1",packageName:"com.whatsapp"}
const becca = {threadId:7,names:["Becca"],addresses:["+15550000001"],preview:"new",unread:true,timestamp:1000}
let inbox = model.messageInbox([becca],[sms,chat])
assert.equal(inbox.messages.length,1)
assert.deepEqual(inbox.messages[0].notificationIds,["sms1"])
assert.deepEqual(inbox.notifications,[chat])
assert.equal(becca.notificationIds,undefined,"inbox must not mutate history")
inbox = model.messageInbox([],[sms])
assert.equal(inbox.messages[0].notificationOnly,true,"notification appears before SMS history")
assert.equal(inbox.messages[0].preview,"new")
assert.equal(model.messageInbox([becca,{...becca,threadId:8}],[sms]).messages.length,3,"ambiguous names stay visible")
assert.equal(model.messageInbox([becca],[{...sms,packageName:""}]).notifications.length,1,"unknown transport stays visible")

assert.equal(model.findConversationByTitle([becca,{...becca,threadId:8}], "Becca"), null,
  "an ambiguous notification must not open the first matching recipient")

const clockBar = (format, section = "center") => ({layout:{[section]:[{id:"omarchy.clock",format}]}})
assert.equal(model.messageTimeFormat(clockBar("ddd d MMM h:mm AP")), "h:mm AP")
assert.equal(model.messageTimeFormat(clockBar("h:mm:ss ap", "right")), "h:mm ap")
assert.equal(model.messageTimeFormat(clockBar("hh:mm A", "left")), "h:mm A")
assert.equal(model.messageTimeFormat(clockBar("dddd HH:mm")), "HH:mm")
assert.equal(model.messageTimeFormat(clockBar("HH:mm AP")), "HH:mm", "capital H stays 24-hour in Qt")
assert.equal(model.messageTimeFormat(clockBar("HH:mm 'AP'")), "HH:mm", "quoted text is not a period token")
assert.equal(model.messageTimeFormat(clockBar("'h:mm AP' yyyy")), "HH:mm")
assert.equal(model.messageTimeFormat(null), "HH:mm")
assert.equal(model.messageTimeFormat({layout:{center:[null,{id:"other.clock",format:"h:mm AP"}]}}), "HH:mm")
assert.equal(model.messageTimeFormat({position:"left",layout:{center:[{id:"omarchy.clock",format:"HH:mm",verticalFormat:"h\nmm AP"}]}}), "h:mm AP")
