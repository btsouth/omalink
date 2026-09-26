function validDeviceId(value) {
  return typeof value === "string" && /^[a-zA-Z0-9]{1,128}$/.test(value)
}

function localPath(value) {
  if (typeof value !== "string" || value.length > 16384 || !/^file:\/\/\/[^?#]*$/i.test(value)) return ""
  try {
    var path = decodeURIComponent(value.slice(7))
    if (path.charAt(0) !== "/" || path.slice(0, 2) === "//" || path.indexOf("\u0000") !== -1) return ""
    // UTF-8 byte count, matching the helper's filesystem bound.
    if (encodeURIComponent(path).replace(/%[0-9A-F]{2}/g, "x").length > 4096) return ""
    return path
  } catch (_) { return "" }
}

function selection(urls) {
  if (!Array.isArray(urls) || urls.length < 1 || urls.length > 32) return {ok:false, paths:[], error:"Choose between 1 and 32 local files"}
  var paths = []
  for (var i = 0; i < urls.length; i++) {
    var path = localPath(String(urls[i]))
    if (!path) return {ok:false, paths:[], error:"Only local file URLs without a host, query or fragment can be shared"}
    if (paths.indexOf(path) !== -1) return {ok:false, paths:[], error:"A file was selected more than once"}
    paths.push(path)
  }
  return {ok:true, paths:paths, error:""}
}

function result(raw, exitCode, count) {
  var unknown = {state:"unconfirmed", text:"File request outcome is unknown; check the phone before sending again"}
  if (typeof raw !== "string" || raw.length > 4096) return unknown
  try {
    var value = JSON.parse(raw)
    if (!value || typeof value !== "object" || value.count !== count || typeof value.code !== "string") return unknown
    if (exitCode === 0 && value.ok === true && value.state === "accepted" && value.code === "accepted")
      return {state:"accepted", text:"File request accepted by KDE Connect; delivery is not verified"}
    // Only helper failures known to occur before dispatch are definite failures.
    var errors = {
      dependency:"A required file sharing tool is missing",
      invalid_device:"Choose a valid phone", file_count:"Choose between 1 and 32 files",
      invalid_path:"Choose local files using valid absolute paths",
      unreadable_file:"Every selected item must be a readable regular file",
      duplicate_file:"A file was selected more than once", invalid_size:"Could not check a selected file's size",
      size_limit:"Choose no more than 8 GiB of files per request",
      backend_unavailable:"KDE Connect is unavailable; open phone setup",
      status_unavailable:"Could not check the phone connection", unpaired:"Pair this phone before sharing files",
      offline:"Connect this phone before sharing files", share_unavailable:"Enable file sharing in KDE Connect on both devices",
      backend_changed:"KDE Connect restarted; refresh before sharing files"
    }
    if ((exitCode === 1 || exitCode === 2) && value.ok === false && value.state === "failed" && Object.prototype.hasOwnProperty.call(errors, value.code))
      return {state:"failed", text:errors[value.code]}
    return unknown
  } catch (_) { return unknown }
}

if (typeof module !== "undefined") module.exports = {validDeviceId:validDeviceId, localPath:localPath, selection:selection, result:result}
