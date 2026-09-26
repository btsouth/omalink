// Notification source policy shared by QML and the pure Node tests. Per-app
// rules only change what OmaLink lists, pops up and clears. They never edit the
// phone or KDE Connect's own notification settings.
//
// Precedence, identical to bin/omalink: an exact mute, then an exact allow, then
// the legacy Notification sources string. Rules are stored per endpoint key and
// passed to the helper per KDE device. An identity is "pkg:<package>" for a
// validated Android package, otherwise "app:<name>". The phone chooses both,
// and a name may be shared by several apps.
var ruleLimit = 100
var phoneLimit = 16
var nameLimit = 256
var scanLimit = 100

function record(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function has(value, key) {
  return record(value) && Object.prototype.hasOwnProperty.call(value, key)
}

function count(value, min) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= min && value <= scanLimit
}

// Control characters and unpaired UTF-16 surrogates cannot round-trip through
// settings, argv and jq unchanged, so such a name is never offered a rule.
function exactText(value) {
  if (typeof value !== "string" || /[\u0000-\u001f\u007f]/.test(value)) return false
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff) {
      var next = value.charCodeAt(++i)
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false
    } else if (code >= 0xdc00 && code <= 0xdfff) return false
  }
  return true
}

function validPackageName(value) {
  return typeof value === "string" && value.length <= nameLimit
    && /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*$/.test(value)
}

function validAppName(value) {
  return typeof value === "string" && value !== "" && value.length <= nameLimit && exactText(value)
}

function validIdentity(value) {
  if (typeof value !== "string") return false
  if (value.indexOf("pkg:") === 0) return validPackageName(value.slice(4))
  if (value.indexOf("app:") === 0) return validAppName(value.slice(4))
  return false
}

// The helper only reports validated packages. Anything else present in the
// package field makes the record unidentifiable rather than name-only.
function identity(notification) {
  if (!record(notification)) return ""
  var packageName = notification.packageName
  if (packageName !== undefined && packageName !== null && packageName !== "")
    return validPackageName(packageName) ? "pkg:" + packageName : ""
  return validAppName(notification.appName) ? "app:" + notification.appName : ""
}

// Canonical KDE endpoint keys from ProviderModel.endpointKey only.
function kdeDeviceId(endpointKey) {
  if (typeof endpointKey !== "string" || endpointKey.length > 512) return ""
  try {
    var parts = JSON.parse(endpointKey)
    if (Array.isArray(parts) && parts.length === 6 && parts[0] === "endpoint" && parts[1] === 1
        && parts[2] === "kdeconnect" && parts[3] === "local" && typeof parts[4] === "string"
        && /^[A-Za-z0-9]{1,128}$/.test(parts[4]) && parts[5] === null
        && JSON.stringify(parts) === endpointKey) return parts[4]
  } catch (error) {}
  return ""
}

function ruleLabel(value, key) {
  return validAppName(value) ? value : key.slice(4)
}

// Settings are user-editable. Invalid entries are ignored, and entries beyond
// the limits are not applied, so the helper argument stays well under the
// kernel's per-argument limit.
function normalizeRules(value) {
  var result = {}
  if (!record(value)) return result
  var phones = 0
  var total = 0
  Object.keys(value).forEach(function(endpointKey) {
    var rules = value[endpointKey]
    if (phones >= phoneLimit || !kdeDeviceId(endpointKey) || !record(rules)) return
    var clean = {}
    var kept = 0
    Object.keys(rules).forEach(function(key) {
      var rule = rules[key]
      if (total >= ruleLimit || !validIdentity(key) || !record(rule)
          || (rule.state !== "allow" && rule.state !== "mute")) return
      clean[key] = {state: rule.state, label: ruleLabel(rule.label, key)}
      kept++
      total++
    })
    if (kept > 0) {
      result[endpointKey] = clean
      phones++
    }
  })
  return result
}

function ruleTotal(rules) {
  return Object.keys(rules).reduce(function(sum, key) { return sum + Object.keys(rules[key]).length }, 0)
}

function phoneRules(rules, endpointKey) {
  return has(rules, endpointKey) && record(rules[endpointKey]) ? rules[endpointKey] : {}
}

function ruleState(rules, key) {
  return key !== "" && has(rules, key) && record(rules[key])
    && (rules[key].state === "allow" || rules[key].state === "mute") ? rules[key].state : ""
}

// Returns the complete new rule set, or null when the change is invalid or
// would exceed a limit. "default" removes the rule.
function withRule(rules, endpointKey, key, state, label) {
  if (!kdeDeviceId(endpointKey) || !validIdentity(key)
      || ["default", "allow", "mute"].indexOf(state) === -1) return null
  var next = normalizeRules(rules)
  var current = phoneRules(next, endpointKey)
  var updated = {}
  Object.keys(current).forEach(function(existing) { updated[existing] = current[existing] })
  if (state === "default") {
    delete updated[key]
  } else {
    if (!has(updated, key) && (ruleTotal(next) >= ruleLimit
        || (!has(next, endpointKey) && Object.keys(next).length >= phoneLimit))) return null
    updated[key] = {state: state, label: ruleLabel(label, key)}
  }
  if (Object.keys(updated).length > 0) next[endpointKey] = updated
  else delete next[endpointKey]
  return next
}

function withoutPhone(rules, endpointKey) {
  var next = normalizeRules(rules)
  delete next[endpointKey]
  return next
}

// {"<KDE device ID>": {"<identity>": "allow" | "mute"}}, or "" without rules.
function helperArgument(rules) {
  var value = normalizeRules(rules)
  var policy = {}
  var keys = Object.keys(value)
  keys.forEach(function(endpointKey) {
    var states = {}
    Object.keys(value[endpointKey]).forEach(function(key) { states[key] = value[endpointKey][key].state })
    policy[kdeDeviceId(endpointKey)] = states
  })
  return keys.length > 0 ? JSON.stringify(policy) : ""
}

// The legacy source filter, mirroring notification_allowed in bin/omalink
// under its fixed C.UTF-8 locale. The helper filters first, so any difference
// here would leave a record listed that the helper now hides.
var builtinPackages = ["com.google.android.apps.messaging", "com.samsung.android.messaging", "com.android.messaging",
  "com.android.mms", "com.azure.authenticator", "com.google.android.apps.authenticator2", "com.whatsapp"]
var builtinApps = ["messages", "google messages", "samsung messages", "messaging", "authenticator",
  "microsoft authenticator", "google authenticator", "whatsapp"]
// glibc's [[:space:]] in C.UTF-8. It excludes U+00A0, U+2007 and U+202F.
var blank = /^[\t\n\v\f\r \u1680\u2000-\u2006\u2008-\u200a\u2028\u2029\u205f\u3000]*$/
var edges = /^[\t\n\v\f\r \u1680\u2000-\u2006\u2008-\u200a\u2028\u2029\u205f\u3000]+|[\t\n\v\f\r \u1680\u2000-\u2006\u2008-\u200a\u2028\u2029\u205f\u3000]+$/g

// bash lowercases one character at a time, so a multi-character lowercase
// form (U+0130) keeps its first code point and final sigma is not contextual.
function helperLower(value) {
  var result = ""
  for (var i = 0; i < value.length; i++) {
    var code = value.codePointAt(i)
    if (code > 0xffff) i++
    result += String.fromCodePoint(String.fromCodePoint(code).toLowerCase().codePointAt(0))
  }
  return result
}

// null: no configured list. true: a blank list, which allows everything.
// Otherwise the lowercase terms, possibly none, as with a comma-only list.
// argv ends at NUL and bash's read stops at the first newline.
function sourceTerms(sources) {
  if (typeof sources !== "string") return null
  var value = sources.split("\u0000")[0]
  if (blank.test(value)) return true
  return value.split("\n")[0].split(",").map(function(term) { return helperLower(term).replace(edges, "") })
    .filter(function(term) { return term.length > 0 })
}

function sourceAllowed(notification, terms) {
  var packageName = helperLower(String(notification.packageName || ""))
  var app = helperLower(String(notification.appName || ""))
  if (terms === true) return true
  if (!terms) return builtinPackages.indexOf(packageName) !== -1 || builtinApps.indexOf(app) !== -1
  return terms.some(function(term) { return app.indexOf(term) !== -1 || packageName.indexOf(term) !== -1 })
}

function permitted(notification, terms, rules) {
  var state = ruleState(rules, identity(notification))
  if (state === "mute") return false
  if (state === "allow") return true
  return sourceAllowed(notification, terms)
}

// rules are one phone's rules, from phoneRules().
function visibleNotifications(notifications, sources, rules) {
  if (!Array.isArray(notifications)) return []
  var terms = sourceTerms(sources)
  return notifications.filter(function(notification) {
    return record(notification) && permitted(notification, terms, rules)
  })
}

// Validates the helper's per-device scan summary. An app whose identity cannot
// be ruled is counted as unidentified rather than silently dropped.
function normalizeSources(value) {
  if (!record(value) || typeof value.scanTruncated !== "boolean" || !Array.isArray(value.apps)
      || value.apps.length > scanLimit) return null
  var fields = ["examined", "permitted", "hidden", "listed", "unidentified"]
  for (var i = 0; i < fields.length; i++) if (!count(value[fields[i]], 0)) return null
  if (value.permitted + value.hidden !== value.examined || value.listed > value.permitted) return null
  var apps = []
  var seen = {}
  var unidentified = value.unidentified
  value.apps.forEach(function(app) {
    if (!record(app) || !count(app.count, 1) || typeof app.appName !== "string"
        || typeof app.packageName !== "string" || typeof app.permitted !== "boolean"
        || typeof app.sourceAllowed !== "boolean") return
    var key = identity({appName: app.appName, packageName: app.packageName})
    if (key === "" || key !== app.key || has(seen, key)) {
      unidentified = Math.min(value.examined, unidentified + app.count)
      return
    }
    seen[key] = true
    apps.push({key: key, appName: app.appName, packageName: app.packageName, count: app.count,
      permitted: app.permitted, sourceAllowed: app.sourceAllowed})
  })
  return {examined: value.examined, permitted: value.permitted, hidden: value.hidden,
    listed: value.listed, unidentified: unidentified, scanTruncated: value.scanTruncated, apps: apps}
}

// Apps seen in the current scan, then apps that only have a saved rule.
function appRows(sources, rules) {
  var rows = []
  var seen = {}
  var apps = sources && Array.isArray(sources.apps) ? sources.apps : []
  apps.forEach(function(app) {
    seen[app.key] = true
    rows.push({key: app.key, label: app.appName !== "" ? app.appName : app.packageName,
      packageName: app.packageName, nameOnly: app.key.indexOf("app:") === 0, count: app.count,
      observed: true, sourceAllowed: app.sourceAllowed, state: ruleState(rules, app.key) || "default"})
  })
  Object.keys(record(rules) ? rules : {}).forEach(function(key) {
    if (has(seen, key) || !validIdentity(key) || ruleState(rules, key) === "") return
    rows.push({key: key, label: ruleLabel(rules[key].label, key),
      packageName: key.indexOf("pkg:") === 0 ? key.slice(4) : "", nameOnly: key.indexOf("app:") === 0,
      count: 0, observed: false, sourceAllowed: null, state: rules[key].state})
  })
  return rows
}

function appRowDetail(row) {
  var parts = [row.nameOnly ? "Name only; other apps may share it" : row.packageName]
  parts.push(row.observed ? (row.count === 1 ? "1 current" : row.count + " current") : "None current")
  return parts.join(" · ")
}

function appRowStatus(row) {
  if (row.state === "mute") return "Muted in OmaLink"
  if (row.state === "allow") return "Always listed"
  if (row.sourceAllowed === true) return "Listed by Notification sources"
  if (row.sourceAllowed === false) return "Hidden by Notification sources"
  return "Follows Notification sources"
}

// Explains an empty or partial list without implying anything about the
// phone's installed apps or permissions. Clear all is only mentioned while the
// panel offers it.
function summaryLines(sources, visibleCount, clearAvailable) {
  if (!sources) return []
  var lines = []
  var hidden = sources.hidden + Math.max(0, sources.listed - visibleCount)
  if (sources.examined === 0) lines.push("KDE Connect reports no phone notifications right now.")
  else if (visibleCount === 0 && hidden > 0)
    lines.push(hidden === 1 ? "1 phone notification is hidden by your filters." : hidden + " phone notifications are hidden by your filters.")
  else if (hidden > 0) lines.push(hidden + " more hidden by your filters.")
  if (sources.permitted > sources.listed && visibleCount > 0)
    lines.push("Showing " + visibleCount + " of " + sources.permitted + " matching."
      + (clearAvailable ? " Clear all dismisses all " + sources.permitted + " on the phone." : ""))
  if (sources.scanTruncated)
    lines.push("Only the first " + scanLimit + " phone notifications were checked." + (clearAvailable ? " Clear all stops there too." : ""))
  return lines
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {ruleLimit: ruleLimit, phoneLimit: phoneLimit, builtinPackages: builtinPackages,
    builtinApps: builtinApps, validPackageName: validPackageName,
    validIdentity: validIdentity, identity: identity, kdeDeviceId: kdeDeviceId,
    normalizeRules: normalizeRules, phoneRules: phoneRules, ruleState: ruleState, withRule: withRule,
    withoutPhone: withoutPhone, helperArgument: helperArgument, visibleNotifications: visibleNotifications,
    normalizeSources: normalizeSources, appRows: appRows, appRowDetail: appRowDetail,
    appRowStatus: appRowStatus, summaryLines: summaryLines}
}
