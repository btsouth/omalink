// Runs one decision table through bin/omalink's policy functions and
// NotificationPolicy.js. The helper filters first; any disagreement would let
// the panel keep a record the helper hides, or hide one it explicitly allowed.
// Needs bash and jq only: no D-Bus, phone or desktop session.
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")
const fs = require("node:fs")
const path = require("node:path")
const policy = require("../NotificationPolicy.js")
const providers = require("../ProviderModel.js")

const helper = fs.readFileSync(path.join(__dirname, "..", "bin", "omalink"), "utf8")
function extract(name) {
  const match = helper.match(new RegExp("^" + name + "\\(\\) \\{\\n[\\s\\S]*?^\\}$", "m"))
  assert.ok(match, "helper function missing: " + name)
  return match[0]
}
const functions = ["notification_package", "load_notify_rules", "notification_permitted", "notification_allowed"]
  .map(extract).join("\n")
const limit = helper.match(/^notify_rules_max_bytes=\d+$/m)[0]

// Arguments: device app package, repeated. Prints one 1/0 per notification.
const script = `set -euo pipefail
export LC_ALL=C.UTF-8
usage() { exit 2; }
${limit}
declare -A notify_rules=()
${functions}
NOTIFY_APPS_SET="\${PARITY_SET:-}"
NOTIFY_APPS="\${PARITY_APPS:-}"
NOTIFY_RULES_SET="\${PARITY_RULES_SET:-}"
NOTIFY_RULES="\${PARITY_RULES:-}"
load_notify_rules
while (( $# >= 3 )); do
  if notification_permitted "$1" "$2" "$3"; then printf 1; else printf 0; fi
  shift 3
done
`

const pixel = providers.endpointKey(providers.kdeEndpoint("abc123"))
const galaxy = providers.endpointKey(providers.kdeEndpoint("def456"))
const notifications = [
  { appName: "Messages", packageName: "com.google.android.apps.messaging" },
  { appName: "WhatsApp", packageName: "com.whatsapp" },
  { appName: "Spotify", packageName: "com.spotify.music" },
  { appName: "Signal", packageName: "" },
  { appName: "Signal", packageName: "org.thoughtcrime.securesms" },
  { appName: "Microsoft Authenticator", packageName: "com.azure.authenticator" },
  { appName: "İnstagram", packageName: "" },
  { appName: "ΣΑΣ Bank", packageName: "" },
  { appName: "Ärzte", packageName: "" },
  { appName: "Chat App", packageName: "" },
  { appName: "", packageName: "com.example.nameless" },
  { appName: "", packageName: "" },
  { appName: "-h", packageName: "" },
  { appName: "Tab\tName", packageName: "" }
]
const sources = [undefined, "", "  \t", "　", " ", ",", " , ,", "messages, signal", "SIGNAL",
  "com.whatsapp", "instagram", "σας", "ärzte", "i̇nstagram", "chat app", "chat app", "nomatch\nsignal",
  "signal\nnomatch", "-h", "tab\tname"]
let rules = policy.withRule({}, pixel, "pkg:com.google.android.apps.messaging", "mute", "Messages")
rules = policy.withRule(rules, pixel, "pkg:com.spotify.music", "allow", "Spotify")
rules = policy.withRule(rules, pixel, "app:Signal", "mute", "Signal")
rules = policy.withRule(rules, pixel, "app:İnstagram", "allow", "İnstagram")
rules = policy.withRule(rules, galaxy, "pkg:com.whatsapp", "mute", "WhatsApp")
rules = policy.withRule(rules, galaxy, "app:-h", "allow", "-h")

let cases = 0
for (const ruleSet of [{}, rules]) {
  const argument = policy.helperArgument(ruleSet)
  for (const value of sources) {
    const args = []
    for (const device of ["abc123", "def456"])
      for (const notification of notifications) args.push(device, notification.appName, notification.packageName)
    const bash = execFileSync("bash", ["-c", script, "parity", ...args], { encoding: "utf8", env: {
      PATH: process.env.PATH, PARITY_SET: value === undefined ? "" : "1", PARITY_APPS: value === undefined ? "" : value,
      PARITY_RULES_SET: argument === "" ? "" : "1", PARITY_RULES: argument } })
    let index = 0
    for (const endpoint of [pixel, galaxy]) {
      const phoneRules = policy.phoneRules(ruleSet, endpoint)
      for (const notification of notifications) {
        const js = policy.visibleNotifications([notification], value, phoneRules).length === 1 ? "1" : "0"
        assert.equal(js, bash[index], "helper and panel disagree: " + JSON.stringify({ sources: value,
          device: endpoint === pixel ? "abc123" : "def456", notification, rules: argument !== "" }))
        index++
        cases++
      }
    }
    assert.equal(index, bash.length)
  }
}
console.log("notification parity tests passed (" + cases + " cases)")
