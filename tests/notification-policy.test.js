const assert = require("node:assert/strict")
const policy = require("../NotificationPolicy.js")
const providers = require("../ProviderModel.js")

const pixel = providers.endpointKey(providers.kdeEndpoint("abc123"))
const galaxy = providers.endpointKey(providers.kdeEndpoint("def456"))

// Legacy Notification sources behavior is unchanged without rules.
assert.equal(policy.visibleNotifications([
  { appName: "Spotify", isConversation: false },
  { appName: "Messages", isConversation: true }
]).length, 1)
const filterSamples = [
  { appName: "Signal" },
  { appName: "Messages" },
  { appName: "Microsoft Authenticator" }
]
assert.equal(policy.visibleNotifications(filterSamples, "signal").length, 1)
assert.equal(policy.visibleNotifications(filterSamples, "signal, authenticator").length, 2)
assert.equal(policy.visibleNotifications(filterSamples, "").length, 3)
assert.equal(policy.visibleNotifications(filterSamples, "  ").length, 3)
assert.equal(policy.visibleNotifications(filterSamples, " , ,").length, 3)
assert.deepEqual(policy.visibleNotifications("nope", "signal"), [])
// Package-only filters must survive the helper-to-panel boundary.
assert.deepStrictEqual(policy.visibleNotifications([
  { appName: "Localized name", packageName: "com.example.messaging" }, null, ["array"]
], "com.example.messaging"), [{ appName: "Localized name", packageName: "com.example.messaging" }])

// Identities: a validated package, otherwise the phone-chosen name.
assert.equal(policy.identity({ appName: "WhatsApp", packageName: "com.whatsapp" }), "pkg:com.whatsapp")
assert.equal(policy.identity({ appName: "Signal", packageName: "" }), "app:Signal")
assert.equal(policy.identity({ appName: "Signal" }), "app:Signal")
assert.equal(policy.identity({ appName: "Signal", packageName: "12345" }), "", "invalid package fell back to a name")
assert.equal(policy.identity({ appName: "Signal", packageName: "com..x" }), "")
assert.equal(policy.identity({ appName: "Signal", packageName: "cöm.x" }), "")
assert.equal(policy.identity({ appName: "" }), "")
assert.equal(policy.identity({ appName: "Line\nbreak" }), "")
assert.equal(policy.identity({ appName: "bad \ud800 surrogate" }), "")
assert.equal(policy.identity({ appName: "😀 Chat" }), "app:😀 Chat")
assert.equal(policy.identity({ appName: "N".repeat(257) }), "")
assert.equal(policy.identity(null), "")
for (const valid of ["android", "com.x_y.Z9", "a.b"]) assert.equal(policy.validPackageName(valid), true, valid)
for (const invalid of ["", "1com.x", "com.", ".com", "com.x-y", "com x", "p".repeat(257)])
  assert.equal(policy.validPackageName(invalid), false, invalid)

// Only canonical KDE endpoint keys carry rules.
assert.equal(policy.kdeDeviceId(pixel), "abc123")
assert.equal(policy.kdeDeviceId(JSON.stringify(["endpoint", 1, "blueferry", "local", "local-history", null])), "")
assert.equal(policy.kdeDeviceId('["endpoint", 1, "kdeconnect", "local", "abc123", null]'), "", "non-canonical key accepted")
assert.equal(policy.kdeDeviceId(JSON.stringify(["endpoint", 1, "kdeconnect", "local", "../x", null])), "")
assert.equal(policy.kdeDeviceId("{"), "")

// Precedence: exact mute, then exact allow, then the legacy source filter.
const samples = [
  { id: "1", appName: "Messages", packageName: "com.google.android.apps.messaging" },
  { id: "2", appName: "WhatsApp", packageName: "com.whatsapp" },
  { id: "3", appName: "Spotify", packageName: "com.spotify.music", isConversation: false },
  { id: "4", appName: "Signal", packageName: "" },
  { id: "5", appName: "Messages", packageName: "com.samsung.android.messaging" }
]
let rules = policy.withRule({}, pixel, "pkg:com.google.android.apps.messaging", "mute", "Messages")
rules = policy.withRule(rules, pixel, "pkg:com.spotify.music", "allow", "Spotify")
rules = policy.withRule(rules, pixel, "app:Signal", "mute", "Signal")
const pixelRules = policy.phoneRules(rules, pixel)
const ids = (list) => list.map((item) => item.id)
for (const [sources, expected] of [
  [undefined, ["2", "3", "5"]],
  ["", ["2", "3", "5"]],
  ["   ", ["2", "3", "5"]],
  ["messages, signal", ["3", "5"]],
  ["messages, spotify", ["3", "5"]],
  ["nomatch", ["3"]]
]) assert.deepEqual(ids(policy.visibleNotifications(samples, sources, pixelRules)), expected, String(sources))
// Another phone keeps the legacy behavior; a name rule never matches a package.
assert.deepEqual(ids(policy.visibleNotifications(samples, "messages", policy.phoneRules(rules, galaxy))), ["1", "5"])
assert.deepEqual(ids(policy.visibleNotifications(samples, undefined, policy.phoneRules(rules, galaxy))), ["1", "2", "4", "5"])
const nameRules = policy.phoneRules(policy.withRule({}, pixel, "app:Messages", "mute", "Messages"), pixel)
assert.deepEqual(ids(policy.visibleNotifications(samples, "", nameRules)), ["1", "2", "3", "4", "5"])
assert.deepEqual(ids(policy.visibleNotifications([{ id: "6", appName: "Messages" }], "", nameRules)), [])

// Rule editing and legacy settings. The sources string is never rewritten.
assert.equal(policy.ruleState(pixelRules, "pkg:com.spotify.music"), "allow")
assert.equal(policy.ruleState(pixelRules, "pkg:com.whatsapp"), "")
assert.equal(policy.ruleState(pixelRules, ""), "")
const reset = policy.withRule(rules, pixel, "pkg:com.spotify.music", "default", "Spotify")
assert.equal(policy.ruleState(policy.phoneRules(reset, pixel), "pkg:com.spotify.music"), "")
assert.equal(policy.ruleState(policy.phoneRules(rules, pixel), "pkg:com.spotify.music"), "allow", "input mutated")
const cleared = ["pkg:com.google.android.apps.messaging", "pkg:com.spotify.music", "app:Signal"]
  .reduce((value, key) => policy.withRule(value, pixel, key, "default", ""), rules)
assert.deepEqual(cleared, {}, "empty phone entry kept")
assert.equal(policy.withRule(rules, pixel, "com.whatsapp", "mute", ""), null)
assert.equal(policy.withRule(rules, pixel, "pkg:com.whatsapp", "block", ""), null)
assert.equal(policy.withRule(rules, "abc123", "pkg:com.whatsapp", "mute", ""), null)
assert.deepEqual(policy.withoutPhone(rules, pixel), {})
assert.equal(policy.withRule({}, pixel, "pkg:com.whatsapp", "mute", "Bad\nlabel")[pixel]["pkg:com.whatsapp"].label, "com.whatsapp")
assert.deepEqual(policy.normalizeRules({
  [pixel]: { "pkg:com.whatsapp": { state: "mute", label: "WhatsApp" }, "pkg:bad pkg": { state: "mute" },
    "app:Signal": { state: "block" }, "app:": { state: "mute" }, "__proto__": { state: "mute" }, "app:Chat": "mute" },
  "abc123": { "pkg:com.whatsapp": { state: "mute" } },
  [galaxy]: []
}), { [pixel]: { "pkg:com.whatsapp": { state: "mute", label: "WhatsApp" } } })
for (const legacy of [undefined, null, "", "pkg:com.whatsapp", [], 7]) assert.deepEqual(policy.normalizeRules(legacy), {})

// Limits: 100 rules and 16 phones in total. Existing rules still change.
let many = {}
for (let index = 0; index < policy.ruleLimit; index++)
  many = policy.withRule(many, pixel, "pkg:com.example.app" + index, "mute", "App " + index)
assert.equal(policy.withRule(many, pixel, "pkg:com.example.extra", "mute", ""), null)
assert.equal(policy.withRule(many, galaxy, "pkg:com.example.extra", "mute", ""), null)
assert.equal(policy.withRule(many, pixel, "pkg:com.example.app7", "allow", "")[pixel]["pkg:com.example.app7"].state, "allow")
assert.notEqual(policy.withRule(many, pixel, "pkg:com.example.app7", "default", ""), null)
let phones = {}
for (let index = 0; index < policy.phoneLimit; index++)
  phones = policy.withRule(phones, providers.endpointKey(providers.kdeEndpoint("phone" + index)), "pkg:com.whatsapp", "mute", "")
assert.equal(policy.withRule(phones, pixel, "pkg:com.whatsapp", "mute", ""), null)
const oversized = {}
for (let phone = 0; phone < 20; phone++) {
  const phoneRules = {}
  for (let index = 0; index < 120; index++) phoneRules["pkg:com.example.app" + index] = { state: "mute" }
  oversized[providers.endpointKey(providers.kdeEndpoint("phone" + phone))] = phoneRules
}
const bounded = policy.normalizeRules(oversized)
assert.equal(Object.values(bounded).reduce((sum, value) => sum + Object.keys(value).length, 0), policy.ruleLimit)

// The helper receives only states keyed by KDE device. The worst case at the
// limits stays under bin/omalink's 98304-byte refusal and the kernel's limit.
assert.equal(policy.helperArgument({}), "")
assert.deepEqual(JSON.parse(policy.helperArgument(rules)), { abc123: {
  "pkg:com.google.android.apps.messaging": "mute", "pkg:com.spotify.music": "allow", "app:Signal": "mute" } })
let worst = {}
for (let index = 0; index < policy.ruleLimit; index++) {
  const endpoint = providers.endpointKey(providers.kdeEndpoint("D".repeat(120) + (index % policy.phoneLimit)))
  worst = policy.withRule(worst, endpoint, "app:" + "€".repeat(253) + String(index).padStart(3, "0"), "mute", "")
}
assert.equal(Object.keys(worst).length, policy.phoneLimit)
assert.ok(Buffer.byteLength(policy.helperArgument(worst)) < 98304)

// Helper scan summaries are validated before display.
const sources = policy.normalizeSources({ examined: 5, permitted: 3, hidden: 2, listed: 3, unidentified: 1, scanTruncated: false,
  apps: [
    { key: "pkg:com.whatsapp", appName: "WhatsApp", packageName: "com.whatsapp", count: 2, permitted: true, sourceAllowed: true },
    { key: "app:Signal", appName: "Signal", packageName: "", count: 1, permitted: true, sourceAllowed: false },
    { key: "app:Ctl\u0001", appName: "Ctl\u0001", packageName: "", count: 1, permitted: false, sourceAllowed: false },
    { key: "pkg:com.forged", appName: "WhatsApp", packageName: "com.whatsapp", count: 1, permitted: false, sourceAllowed: true }
  ] })
assert.deepEqual(sources.apps.map((app) => app.key), ["pkg:com.whatsapp", "app:Signal"])
assert.equal(sources.unidentified, 3)
for (const invalid of [null, {}, { examined: 1, permitted: 1, hidden: 1, listed: 0, unidentified: 0, scanTruncated: false, apps: [] },
  { examined: 101, permitted: 101, hidden: 0, listed: 25, unidentified: 0, scanTruncated: true, apps: [] },
  { examined: 2, permitted: 1, hidden: 1, listed: 2, unidentified: 0, scanTruncated: false, apps: [] },
  { examined: 0, permitted: 0, hidden: 0, listed: 0, unidentified: 0, scanTruncated: "no", apps: [] }])
  assert.equal(policy.normalizeSources(invalid), null)

// Rows: observed apps first, then apps that only have a saved rule.
const rowRules = policy.phoneRules(policy.withRule(policy.withRule({}, pixel, "app:Signal", "mute", "Signal"),
  pixel, "pkg:com.example.gone", "allow", "Gone app"), pixel)
const rows = policy.appRows(sources, rowRules)
assert.deepEqual(rows.map((row) => [row.key, row.state, row.observed, row.nameOnly]), [
  ["pkg:com.whatsapp", "default", true, false], ["app:Signal", "mute", true, true], ["pkg:com.example.gone", "allow", false, false]])
assert.equal(rows[2].label, "Gone app")
assert.equal(policy.appRowDetail(rows[0]), "com.whatsapp · 2 current")
assert.equal(policy.appRowDetail(rows[1]), "Name only; other apps may share it · 1 current")
assert.equal(policy.appRowDetail(rows[2]), "com.example.gone · None current")
assert.deepEqual(rows.map(policy.appRowStatus), ["Listed by Notification sources", "Muted in OmaLink", "Always listed"])
assert.equal(policy.appRowStatus({ state: "default", sourceAllowed: false }), "Hidden by Notification sources")
assert.equal(policy.appRowStatus({ state: "default", sourceAllowed: null }), "Follows Notification sources")
assert.deepEqual(policy.appRows(null, {}), [])

// Filtered-empty is distinguished from an empty phone, and limits are disclosed.
const summary = (value) => ({ examined: 0, permitted: 0, hidden: 0, listed: 0, unidentified: 0, scanTruncated: false, apps: [], ...value })
assert.deepEqual(policy.summaryLines(null, 0), [])
assert.deepEqual(policy.summaryLines(summary({}), 0), ["No notifications on the phone right now."])
assert.deepEqual(policy.summaryLines(summary({ examined: 4, hidden: 4 }), 0), ["4 phone notifications are hidden by your filters."])
assert.deepEqual(policy.summaryLines(summary({ examined: 1, hidden: 1 }), 0), ["1 phone notification is hidden by your filters."])
assert.deepEqual(policy.summaryLines(summary({ examined: 3, permitted: 3, listed: 3 }), 2), ["1 more hidden by your filters."])
assert.deepEqual(policy.summaryLines(summary({ examined: 3, permitted: 3, listed: 3 }), 3), [])
assert.deepEqual(policy.summaryLines(summary({ examined: 100, permitted: 87, hidden: 13, listed: 25, scanTruncated: true }), 25), [
  "13 more hidden by your filters.",
  "Showing 25 of 87 matching. Clear all dismisses all 87 on the phone.",
  "Only the first 100 phone notifications were checked. Clear all stops there too."])

console.log("notification policy tests passed")
