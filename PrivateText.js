function byteLength(value) {
  try { return encodeURIComponent(value).replace(/%[0-9A-F]{2}/g, "x").length }
  catch (_) { return Infinity }
}

function serialize(request) {
  if (!request || typeof request.body !== "string" || request.body.indexOf("\u0000") !== -1
      || byteLength(request.body) < 1 || byteLength(request.body) > 8192) return ""
  try {
    var text = JSON.stringify(request)
    return byteLength(text) <= 65536 ? text : ""
  } catch (_) { return "" }
}

function outcome(raw, exitCode) {
  var uncertain = {state:"unconfirmed", code:"dispatch_unconfirmed",
    text:"Request outcome is unknown; check the phone before sending again"}
  if (typeof raw !== "string" || raw.length > 4096) return uncertain
  try {
    var value = JSON.parse(raw)
    if (!value || value.version !== 1) return uncertain
    if (exitCode === 0 && value.ok === true && value.state === "accepted" && value.code === "accepted")
      return {state:"accepted", code:"accepted", text:"Request accepted by KDE Connect; delivery is not verified"}
    var errors = {
      invalid_request:"The request could not be submitted",
      invalid_device:"Choose a valid phone", invalid_body:"Use between 1 and 8192 bytes of text without NUL characters",
      invalid_destination:"Choose a valid recipient", invalid_thread:"Choose a valid conversation",
      invalid_reply:"This notification cannot be replied to", dependency:"Install python-dbus to send text and messages",
      unpaired:"Pair this phone before sending", offline:"Connect this phone before sending",
      capability_unavailable:"Enable this feature in KDE Connect on both devices",
      backend_changed:"KDE Connect restarted; refresh before sending",
      backend_unavailable:"Could not submit the request; check KDE Connect and refresh"
    }
    if (exitCode === 1 && value.ok === false && value.state === "not-submitted"
        && Object.prototype.hasOwnProperty.call(errors, value.code))
      return {state:"not-submitted", code:value.code, text:errors[value.code]}
  } catch (_) {}
  return uncertain
}

if (typeof module !== "undefined") module.exports = {byteLength:byteLength, serialize:serialize, outcome:outcome}
