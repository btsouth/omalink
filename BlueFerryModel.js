// OmaLink's independent validation of the optional read-only helper contract.
function endpoint() {
  return {provider:"blueferry", instanceId:"local", deviceId:"local-history", accountId:null}
}
function record(value) { return value !== null && typeof value === "object" && !Array.isArray(value) }
function integer(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= 9007199254740991 && Math.floor(value) === value
}
function owner(value) {
  return typeof value === "string" && value.length <= 255 && /^:[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+$/.test(value)
}
function validEndpoint(value) {
  return record(value) && value.provider === "blueferry" && value.instanceId === "local"
    && value.deviceId === "local-history" && value.accountId === null
}
function textSize(value) {
  if (typeof value !== "string") return null
  var bytes = 0, points = 0
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code === 0) return null
    if (code >= 0xd800 && code <= 0xdbff) {
      var next = value.charCodeAt(++i)
      if (!(next >= 0xdc00 && next <= 0xdfff)) return null
      bytes += 4
    } else if (code >= 0xdc00 && code <= 0xdfff) return null
    else bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : 3
    points++
  }
  return {bytes:bytes, points:points}
}
function text(value, byteLimit, pointLimit, nonempty) {
  if (typeof value !== "string" || value.length > Math.max(byteLimit || 0, (pointLimit || 0) * 2)) return false
  var size = textSize(value)
  return !!size && (!nonempty || size.points > 0) && (!byteLimit || size.bytes <= byteLimit)
    && (!pointLimit || size.points <= pointLimit)
}
function errorText(code) {
  var errors = {
    invalid_request:"The BlueFerry request was not valid. Refresh and try again.",
    dependency:"Install python-dbus for the system Python to read BlueFerry history.",
    backend_unavailable:"BlueFerry is not running. Start it separately, then refresh.",
    backend_changed:"BlueFerry restarted. Refresh before opening history again.",
    api_incompatible:"This BlueFerry API is not supported. Check the installed backend version.",
    storage_unavailable:"BlueFerry history is unavailable. Check its wallet and retention settings.",
    authorization_required:"BlueFerry did not authorize this read. Check its setup and permissions.",
    rate_limited:"BlueFerry is busy. Wait briefly, then refresh.",
    response_too_large:"BlueFerry returned too much data for this view.",
    invalid_response:"BlueFerry returned an invalid response. Refresh or check its version.",
    thread_unavailable:"This conversation is no longer in BlueFerry's available history.",
    read_failed:"Could not read BlueFerry history. Refresh or check the backend.",
    request_failed:"Could not complete the BlueFerry request. Refresh to try again.",
    request_timeout:"The BlueFerry request timed out. Refresh to try again."
  }
  return Object.prototype.hasOwnProperty.call(errors, code) ? errors[code] : errors.invalid_response
}
function knownCode(code) {
  return ["invalid_request","dependency","backend_unavailable","backend_changed","api_incompatible",
    "storage_unavailable","authorization_required","rate_limited","response_too_large","invalid_response",
    "thread_unavailable","read_failed","request_failed","request_timeout"].indexOf(code) !== -1
}
function failure(code) {
  var selected = knownCode(code) ? code : "invalid_response"
  return {ok:false, code:selected, error:errorText(selected), items:[], backendOwner:"", canReadHistory:false}
}
function noAttachments(item) {
  return item.attachmentCount === 0 && Array.isArray(item.attachments) && item.attachments.length === 0
}
function normalizeItem(item, operation) {
  if (!record(item)) return null
  if (operation === "contacts") {
    return text(item.name,256,0,false) && text(item.number,0,320,true)
      ? {name:item.name, number:item.number} : null
  }
  if (!integer(item.timestamp) || typeof item.incoming !== "boolean" || !noAttachments(item)) return null
  if (operation === "messages") {
    if (!text(item.body,8192,0,false) || !text(item.sender,256,0,false) || typeof item.bodyTruncated !== "boolean") return null
    return {body:item.body, timestamp:item.timestamp, incoming:item.incoming, sender:item.sender,
      bodyTruncated:item.bodyTruncated, attachments:[], attachmentCount:0}
  }
  if (!text(item.threadId,0,1024,true) || /[\u0000-\u001f\u007f]/.test(item.threadId)
      || !Array.isArray(item.names) || item.names.length !== 1 || !text(item.names[0],256,0,false)
      || !Array.isArray(item.addresses) || item.addresses.length > 64 || !text(item.preview,8192,0,false)
      || typeof item.unread !== "boolean" || typeof item.isGroup !== "boolean"
      || typeof item.messagesTruncated !== "boolean") return null
  for (var a = 0; a < item.addresses.length; a++) if (!text(item.addresses[a],0,320,true)) return null
  return {threadId:item.threadId, names:[item.names[0]], addresses:item.addresses.slice(), preview:item.preview,
    timestamp:item.timestamp, unread:item.unread, incoming:item.incoming, isGroup:item.isGroup,
    messagesTruncated:item.messagesTruncated, attachments:[], attachmentCount:0}
}
function result(transport, operation, expectedOwner) {
  if (["status","threads","messages","contacts"].indexOf(operation) === -1) return failure("invalid_request")
  if (operation !== "status" && !owner(expectedOwner)) return failure("invalid_request")
  if (!record(transport) || transport.ok !== true) return failure(record(transport) ? transport.code : "invalid_response")
  var value = transport.data
  if (!record(value) || value.version !== 1 || typeof value.ok !== "boolean"
      || (value.operation !== operation && !(value.operation === null && value.code === "invalid_request" && !value.ok)))
    return failure("invalid_response")
  if (!value.ok) return transport.exitCode === 1 && knownCode(value.code) ? failure(value.code) : failure("invalid_response")
  if (transport.exitCode !== 0 || value.apiVersion !== 2 || !validEndpoint(value.endpoint) || !owner(value.backendOwner))
    return failure("invalid_response")
  if (expectedOwner && value.backendOwner !== expectedOwner) return failure("backend_changed")
  if (["ready","offline","connecting","authorization-required","unknown"].indexOf(value.connection) === -1
      || ["ready","locked","disabled","error","unknown"].indexOf(value.storage) === -1
      || ["encrypted","plaintext","none","unknown"].indexOf(value.storagePolicy) === -1
      || !text(value.backendRelease,128,0,true) || !/^[A-Za-z0-9._+~:-]+$/.test(value.backendRelease)
      || [value.map,value.pbap,value.ancs].some(function(flag) { return flag !== null && typeof flag !== "boolean" })
      || typeof value.canReadHistory !== "boolean" || !record(value.history)
      || value.history.coverage !== "observed-only" || value.history.truncated !== true
      || !Array.isArray(value.items) || value.items.length > 200 || (operation === "status" && value.items.length !== 0))
    return failure("invalid_response")
  if (value.canReadHistory && (value.storage !== "ready" || ["encrypted","plaintext"].indexOf(value.storagePolicy) === -1))
    return failure("invalid_response")
  if (operation !== "status" && !value.canReadHistory) return failure("storage_unavailable")
  var items = [], ids = []
  for (var i = 0; i < value.items.length; i++) {
    var item = normalizeItem(value.items[i],operation)
    if (!item || (operation === "threads" && ids.indexOf(item.threadId) !== -1)) return failure("invalid_response")
    if (operation === "threads") ids.push(item.threadId)
    items.push(item)
  }
  return {ok:true, code:"", error:"", operation:operation, endpoint:endpoint(), backendOwner:value.backendOwner,
    apiVersion:2, connection:value.connection, storage:value.storage, storagePolicy:value.storagePolicy,
    backendRelease:value.backendRelease, map:value.map, pbap:value.pbap, ancs:value.ancs,
    canReadHistory:value.canReadHistory, history:{coverage:"observed-only",truncated:true}, items:items}
}
if (typeof module !== "undefined" && module.exports)
  module.exports = {endpoint:endpoint, validEndpoint:validEndpoint, errorText:errorText, result:result}
