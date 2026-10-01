const assert = require("node:assert/strict")
const state = require("../SendState.js")

const thread = {threadId: 7, addresses: ["+15550000001"], names: ["Test"]}
const old = {body: "repeat", incoming: false, timestamp: 900}
const incoming = {body: "repeat", incoming: true, timestamp: 1100}
const submitted = state.create("one", "phone", thread, "", "repeat", 1000, [old])
assert.equal(submitted.state, "submitting")
const accepted = state.finish(submitted, 0, 1001, 30000)
assert.equal(accepted.state, "accepted", "helper success is acceptance, not delivery")
assert.equal(state.finish(submitted, 124, 1001, 30000).state, "unconfirmed")
assert.equal(state.finish(submitted, 1, 1001, 30000).state, "unconfirmed")
assert.equal(state.reconcile([accepted], "phone", 7, [old, incoming])[0].state, "accepted")
assert.equal(state.reconcile([accepted], "other", 7, [{...old, timestamp: 1100}])[0].state, "accepted")
assert.equal(state.reconcile([accepted], "phone", 8, [{...old, timestamp: 1100}])[0].state, "accepted")
assert.equal(state.reconcile([submitted], "phone", 7, [{...old, timestamp: 1100}])[0].state, "submitting")

// Even a phone clock ahead of this machine cannot make a pre-send record new.
const futureOld = {...old, timestamp: 1200}
const withFutureBaseline = state.finish(state.create("future", "phone", thread, "", "repeat", 1000,
  [futureOld]), 0, 1001, 30000)
assert.equal(state.reconcile([withFutureBaseline], "phone", 7, [futureOld])[0].state, "accepted")
const fresh = {...old, timestamp: 1300}
const noBaseline = state.finish(state.create("unviewed", "phone", thread, "", "repeat", 1000), 0, 1001, 30000)
assert.equal(state.reconcile([noBaseline], "phone", 7, [fresh], 1400)[0].state, "accepted",
  "an unseen thread with a fast phone clock is not confirmation evidence")
assert.equal(state.reconcile([accepted], "phone", 7, [fresh], 1200)[0].state, "accepted",
  "a future-dated record cannot prove a new send")
const confirmed = state.reconcile([accepted], "phone", 7, [old, fresh])[0]
assert.equal(confirmed.state, "confirmed-in-history")
assert.equal(state.messages([old, fresh], thread, [confirmed]).length, 2)
assert.match(state.detail(confirmed.state), /delivery not verified/)

// One record cannot confirm two identical sends, including subsequent refreshes.
const second = state.finish(state.create("two", "phone", thread, "", "repeat", 1000, [old]), 0, 1001, 30000)
let observed = state.reconcile([accepted, second], "phone", 7, [fresh])
assert.deepEqual(observed.map(x => x.state), ["confirmed-in-history", "accepted"])
observed = state.reconcile(observed, "phone", 7, [fresh])
assert.deepEqual(observed.map(x => x.state), ["confirmed-in-history", "accepted"])
assert.equal(state.pruneConfirmed(observed).length, 2, "confirmation claims survive while another send could reuse them")
observed = state.reconcile(observed, "phone", 7, [fresh, {...fresh, timestamp: 1400}])
assert.deepEqual(observed.map(x => x.state), ["confirmed-in-history", "confirmed-in-history"])
assert.equal(state.pruneConfirmed(observed).length, 0)
assert.equal(state.pruneConfirmed(observed, 1200).length, 2,
  "future-dated confirmation claims cannot be reused by the next send")

assert.equal(state.expire([accepted], 31000)[0].state, "accepted")
const unconfirmed = state.expire([accepted], 31001)[0]
assert.equal(unconfirmed.state, "unconfirmed")
assert.equal(state.reconcile([unconfirmed], "phone", 7, [fresh])[0].state, "confirmed-in-history")
assert.equal(state.expire([confirmed], 100000)[0].state, "confirmed-in-history")
const failed = {...submitted, state: "failed"}
assert.equal(state.reconcile([failed], "phone", 7, [fresh])[0].state, "failed")

// No last-ten-digit or group membership guess when locating a new SMS thread.
assert.equal(state.exactConversation([thread], "+1 (555) 000-0001"), thread)
assert.equal(state.exactConversation([thread], "+445550000001"), null)
assert.equal(state.exactConversation([thread, {...thread, threadId: 8}], "+15550000001"), null)
assert.equal(state.exactConversation([{...thread, addresses: ["+15550000001", "+15550000002"]}], "+15550000001"), null)
const freshSend = state.create("new", "phone", null, "+15550000001", "  exact\ntext 😀  ", 1500, [])
const bound = state.bindThreads([freshSend], [thread])[0]
assert.equal(bound.threadId, "7")
assert.equal(bound.body, "  exact\ntext 😀  ")
assert.equal(state.bindThreads([freshSend], [{...thread, addresses: ["+445550000001"]}])[0].threadId, "")
const localConversations = state.conversations([], [freshSend])
assert.equal(localConversations[0].localOperationId, "new")
const localMessages = state.messages([], localConversations[0], [freshSend])
assert.equal(localMessages[0].body, freshSend.body)
assert.equal(state.historyOnly(localMessages).length, 0, "local placeholders are not phone evidence")
assert.equal(state.messages(localMessages, localConversations[0], [freshSend]).length, 1)
assert.equal(state.conversations(localConversations, [freshSend]).length, 1)
assert.equal(state.messages([], thread, [unconfirmed])[0].sendState, "unconfirmed")
assert.equal(state.messages([], {...thread, threadId: 8}, [unconfirmed]).length, 0)
assert.equal(state.updateThreadPreview([{...thread, preview: "old", timestamp: 900}], 7, [fresh])[0].preview, "repeat")
assert.equal(state.updateThreadPreview([{...thread, preview: "newer", timestamp: 5000}], 7, [fresh])[0].preview, "newer")
assert.equal(submitted.state, "submitting", "transitions leave prior snapshots unchanged")
console.log("send state tests passed")

// SMS timestamps can be truncated to seconds while the desktop uses milliseconds.
const roundedSend = state.finish(state.create("rounded", "phone", thread, "", "repeat", 1899, [old]), 0, 1900, 30000)
const roundedRow = {...old, timestamp: 1000}
assert.equal(state.reconcile([roundedSend], "phone", 7, [old, roundedRow], 2000)[0].state, "confirmed-in-history")
assert.equal(state.reconcile([roundedSend], "phone", 7, [{...old, timestamp: 999}], 2000)[0].state, "accepted")
const roundedBaseline = state.finish(state.create("known", "phone", thread, "", "repeat", 1899, [roundedRow]), 0, 1900, 30000)
assert.equal(state.reconcile([roundedBaseline], "phone", 7, [roundedRow], 2000)[0].state, "accepted")
assert.equal(state.label("accepted"), "Waiting for phone…")

const roundedSecond = state.finish(state.create("rounded-two", "phone", thread, "", "repeat", 1950, [old]), 0, 1951, 30000)
const roundedPair = state.reconcile([roundedSend, roundedSecond], "phone", 7, [roundedRow], 2000)
assert.deepEqual(roundedPair.map(row => row.state), ["confirmed-in-history", "accepted"])
assert.equal(state.pruneConfirmed(roundedPair, 2100).length, 2, "rounded row remains claimed by the first send")
