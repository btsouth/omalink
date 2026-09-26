// Pure identity and validation shared by QML and Node. This module does not
// activate providers, persist phone data or dispatch operations.
var schemaVersion = 1
var maxSnapshotLength = 65536
var capabilityNames = ["messaging", "contacts", "notifications", "sharing", "clipboard", "ring", "media", "battery", "files", "connectivity"]

function record(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function integer(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= 9007199254740991 && Math.floor(value) === value
}

function opaqueId(value, limit) {
  // Never trim, normalize Unicode, decode escapes or infer a telephone number.
  if (typeof value !== "string" || !value.length || value.length > limit
      || /[\u0000-\u001f\u007f]/.test(value)) return false
  // Reject unpaired UTF-16 surrogates so transport encoders cannot change IDs.
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff) {
      var next = value.charCodeAt(++i)
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false
    } else if (code >= 0xdc00 && code <= 0xdfff) return false
  }
  return true
}

function normalizeEndpoint(value) {
  if (!record(value) || ["kdeconnect", "blueferry", "blip"].indexOf(value.provider) === -1
      || !opaqueId(value.instanceId, 256) || !opaqueId(value.deviceId, 1024)
      || !(value.accountId === null || opaqueId(value.accountId, 1024))) return null
  if (value.provider === "kdeconnect" && !/^[A-Za-z0-9]{1,128}$/.test(value.deviceId)) return null
  return {provider: value.provider, instanceId: value.instanceId,
    deviceId: value.deviceId, accountId: value.accountId}
}

function kdeEndpoint(deviceId) {
  return normalizeEndpoint({provider: "kdeconnect", instanceId: "local", deviceId: deviceId, accountId: null})
}

// Compatibility boundary for the only currently implemented transport. An
// explicit future route must never fall back to a raw KDE device ID.
function kdeEndpointFromPayload(payload) {
  if (!record(payload)) return null
  var explicit = Object.prototype.hasOwnProperty.call(payload, "endpoint")
  var endpoint = explicit ? normalizeEndpoint(payload.endpoint) : kdeEndpoint(payload.deviceId)
  if (!endpoint || endpoint.provider !== "kdeconnect"
      || endpoint.instanceId !== "local" || endpoint.accountId !== null) return null
  if (Object.prototype.hasOwnProperty.call(payload, "deviceId")
      && payload.deviceId !== endpoint.deviceId) return null
  return endpoint
}

function endpointParts(endpoint) {
  var value = normalizeEndpoint(endpoint)
  return value ? [value.provider, value.instanceId, value.deviceId, value.accountId] : null
}

function endpointKey(endpoint) {
  var parts = endpointParts(endpoint)
  return parts ? JSON.stringify(["endpoint", schemaVersion].concat(parts)) : ""
}

function threadKey(endpoint, threadId) {
  var parts = endpointParts(endpoint)
  return parts && opaqueId(threadId, 2048)
    ? JSON.stringify(["thread", schemaVersion].concat(parts, [threadId])) : ""
}

function validOwner(value) {
  // D-Bus unique owner, never the reusable well-known service name.
  return typeof value === "string" && value.length <= 255
    && /^:[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+$/.test(value)
}

function requestContext(endpoint, generation, backendOwner) {
  var normalized = normalizeEndpoint(endpoint)
  if (!normalized || !integer(generation) || !validOwner(backendOwner)) return null
  return {endpoint: normalized, generation: generation, backendOwner: backendOwner}
}

function replyIsCurrent(reply, current) {
  if (!record(reply) || !record(current)) return false
  var a = requestContext(reply.endpoint, reply.generation, reply.backendOwner)
  var b = requestContext(current.endpoint, current.generation, current.backendOwner)
  return !!a && !!b && a.generation === b.generation && a.backendOwner === b.backendOwner
    && endpointKey(a.endpoint) === endpointKey(b.endpoint)
}

function normalizeConnection(value) {
  var states = ["unpaired", "offline", "connecting", "ready", "backend-unavailable", "authorization-required", "unknown"]
  if (!record(value) || states.indexOf(value.state) === -1 || !integer(value.observedAt)
      || !(value.lastSuccessAt === null || integer(value.lastSuccessAt))
      || (value.lastSuccessAt !== null && value.lastSuccessAt > value.observedAt)
      || typeof value.stale !== "boolean") return null
  return {state: value.state, observedAt: value.observedAt,
    lastSuccessAt: value.lastSuccessAt, stale: value.stale}
}

function normalizeCapabilities(value) {
  if (!record(value)) return null
  var keys = Object.keys(value)
  if (keys.length > capabilityNames.length) return null
  var result = {}
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i], item = value[key]
    if (capabilityNames.indexOf(key) === -1 || !record(item)
        || ["available", "unsupported", "disabled", "unknown"].indexOf(item.state) === -1
        || !(item.reason === null || (typeof item.reason === "string" && /^[a-z0-9][a-z0-9-]{0,63}$/.test(item.reason)))
        || !(item.evidence === null || opaqueId(item.evidence, 256))) return null
    result[key] = {state: item.state, reason: item.reason, evidence: item.evidence}
  }
  // An omitted capability is unknown, never implicitly supported.
  for (var n = 0; n < capabilityNames.length; n++) {
    if (!Object.prototype.hasOwnProperty.call(result, capabilityNames[n]))
      result[capabilityNames[n]] = {state: "unknown", reason: null, evidence: null}
  }
  return result
}

function normalizeHistory(value) {
  if (!record(value) || ["backend-available", "observed-only", "unknown"].indexOf(value.coverage) === -1
      || typeof value.truncated !== "boolean") return null
  return {coverage: value.coverage, truncated: value.truncated}
}

function normalizeSnapshot(value) {
  if (!record(value) || value.schemaVersion !== schemaVersion) return null
  var endpoint = normalizeEndpoint(value.endpoint)
  var connection = normalizeConnection(value.connection)
  var capabilities = normalizeCapabilities(value.capabilities)
  var history = normalizeHistory(value.history)
  if (!endpoint || !connection || !capabilities || !history
      || !(value.backendOwner === null || validOwner(value.backendOwner))) return null
  // Ownerless data can explain backend absence but cannot authorize a task.
  if (value.backendOwner === null && connection.state !== "backend-unavailable") return null
  return {schemaVersion: schemaVersion, endpoint: endpoint, backendOwner: value.backendOwner,
    connection: connection, capabilities: capabilities, history: history}
}

function parseSnapshot(raw) {
  if (typeof raw !== "string" || raw.length > maxSnapshotLength) return null
  try { return normalizeSnapshot(JSON.parse(raw)) } catch (error) { return null }
}

function capabilityAvailable(snapshot, key) {
  var value = normalizeSnapshot(snapshot)
  return !!value && value.backendOwner !== null && value.connection.state === "ready"
    && !value.connection.stale && Object.prototype.hasOwnProperty.call(value.capabilities, key)
    && value.capabilities[key].state === "available"
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {schemaVersion: schemaVersion, maxSnapshotLength: maxSnapshotLength,
    normalizeEndpoint: normalizeEndpoint, kdeEndpoint: kdeEndpoint, kdeEndpointFromPayload: kdeEndpointFromPayload, endpointKey: endpointKey,
    threadKey: threadKey, requestContext: requestContext, replyIsCurrent: replyIsCurrent,
    normalizeConnection: normalizeConnection, normalizeCapabilities: normalizeCapabilities,
    normalizeHistory: normalizeHistory, normalizeSnapshot: normalizeSnapshot,
    parseSnapshot: parseSnapshot, capabilityAvailable: capabilityAvailable}
}
