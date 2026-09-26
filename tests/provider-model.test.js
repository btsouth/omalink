const assert = require("node:assert/strict")
const provider = require("../ProviderModel.js")

const kde = provider.kdeEndpoint("abc123")
const ferry = {...kde, provider: "blueferry"}
assert.deepEqual(provider.kdeEndpointFromPayload({deviceId:"abc123"}),kde)
assert.deepEqual(provider.kdeEndpointFromPayload({endpoint:kde}),kde)
assert.deepEqual(provider.kdeEndpointFromPayload({endpoint:kde,deviceId:"abc123"}),kde)
for (const payload of [null, [], {}, {deviceId:123}, {deviceId:"../abc"},
  {endpoint:null,deviceId:"abc123"}, {endpoint:{},deviceId:"abc123"},
  {endpoint:ferry,deviceId:"abc123"}, {endpoint:{...kde,provider:"blip"},deviceId:"abc123"},
  {endpoint:{...kde,instanceId:"remote"},deviceId:"abc123"},
  {endpoint:{...kde,accountId:"account"},deviceId:"abc123"},
  {endpoint:{...kde,accountId:""},deviceId:"abc123"},
  {deviceId:"abc123",deviceName:{toString:0}}, {deviceId:"abc123",conversationHint:[]},
  {deviceId:"abc123",threadId:{toString:0}}, {deviceId:"abc123",threadId:Infinity},
  {endpoint:kde,deviceId:"other"}, {endpoint:kde,deviceId:null}])
  assert.equal(provider.kdeEndpointFromPayload(payload),null,"invalid explicit route never falls back")

assert.deepEqual(kde, {provider:"kdeconnect", instanceId:"local", deviceId:"abc123", accountId:null})
assert.notEqual(provider.endpointKey(kde), provider.endpointKey(ferry))
assert.notEqual(provider.threadKey(kde, "7"), provider.threadKey(ferry, "7"))
for (const field of ["instanceId", "deviceId", "accountId"])
  assert.notEqual(provider.endpointKey(ferry), provider.endpointKey({...ferry, [field]:"another"}), field)
assert.equal(provider.endpointKey({...kde, arbitrary:"ignored"}), provider.endpointKey(kde))
assert.equal(provider.endpointKey({accountId:null,deviceId:"abc123",instanceId:"local",provider:"kdeconnect"}), provider.endpointKey(kde))
const opaque = {...ferry, deviceId:'phone:/雪/📱["x"]', accountId:"account:alice@example.test"}
assert.deepEqual(provider.normalizeEndpoint(opaque), opaque)
assert.notEqual(provider.threadKey(opaque,"a:b"), provider.threadKey({...opaque,deviceId:opaque.deviceId+":a"},"b"))
assert.notEqual(provider.threadKey(opaque,"é"), provider.threadKey(opaque,"e\u0301"), "opaque Unicode is not normalized")
assert.notEqual(provider.threadKey(opaque,"thread"), provider.threadKey(opaque," thread "), "opaque whitespace is preserved")
assert.notEqual(provider.endpointKey({...ferry,accountId:null}), provider.endpointKey({...ferry,accountId:"null"}))
for (const bad of [null, [], {}, {...ferry,provider:"future"}, {...ferry,accountId:undefined},
  {...ferry,deviceId:""}, {...ferry,deviceId:"a".repeat(1025)}, {...ferry,instanceId:"a".repeat(257)},
  {...ferry,deviceId:"x\u0000"}, {...ferry,deviceId:"x\n"}, {...ferry,deviceId:"\ud800"},
  {...ferry,deviceId:"\udc00"}, {...kde,deviceId:"AA:BB"}]) {
  assert.equal(provider.normalizeEndpoint(bad), null)
  assert.equal(provider.endpointKey(bad), "")
  assert.equal(provider.threadKey(bad,"thread"), "")
}
assert.equal(provider.kdeEndpoint("abc/123"),null)
for (const id of ["", 7, null, "\ud800", "x".repeat(2049)]) assert.equal(provider.threadKey(opaque,id),"")
assert.ok(provider.threadKey(opaque,"x".repeat(2048)))

const current = provider.requestContext(ferry,3,":1.21")
assert.equal(provider.replyIsCurrent({...current},current),true)
assert.equal(provider.replyIsCurrent({...current,generation:2},current),false, "old request cannot update a later request")
assert.equal(provider.replyIsCurrent({...current,backendOwner:":1.20"},current),false, "backend restart invalidates old replies")
assert.equal(provider.replyIsCurrent({...current,endpoint:kde},current),false, "same device ID on another provider cannot reroute")
assert.equal(provider.replyIsCurrent(null,current),false)
for (const owner of [null,"","io.weirdware.BlueFerry",":broken",":1.2\n"])
  assert.equal(provider.requestContext(ferry,3,owner),null)
for (const generation of [-1,NaN,Infinity,3.5,Number.MAX_SAFE_INTEGER+1,"3"])
  assert.equal(provider.requestContext(ferry,generation,":1.21"),null)

const snapshot = {schemaVersion:1,endpoint:opaque,backendOwner:":1.21",
  connection:{state:"ready",observedAt:2000,lastSuccessAt:1900,stale:false},
  capabilities:{messaging:{state:"available",reason:null,evidence:"api-generation-2"},
    files:{state:"unsupported",reason:"not-supported",evidence:null}},
  history:{coverage:"observed-only",truncated:true}}
for (const key of ["__proto__", "constructor", "toString"]) {
  const dictionary = JSON.parse('{"' + key + '":{"state":"available","reason":null,"evidence":null}}')
  assert.equal(provider.normalizeCapabilities(dictionary), null, "reject prototype-shaped capability keys")
}
const normalized = provider.parseSnapshot(JSON.stringify(snapshot))
assert.deepEqual(normalized.history,{coverage:"observed-only",truncated:true}, "limited history and truncated result are independent")
assert.equal(normalized.capabilities.clipboard.state,"unknown")
assert.equal(provider.capabilityAvailable(snapshot,"messaging"),true)
assert.equal(provider.capabilityAvailable(snapshot,"files"),false)
assert.equal(provider.capabilityAvailable(snapshot,"clipboard"),false)
assert.equal(provider.capabilityAvailable(snapshot,"toString"),false)
for (const state of ["offline","unpaired","connecting","authorization-required","backend-unavailable","unknown"])
  assert.equal(provider.capabilityAvailable({...snapshot,connection:{...snapshot.connection,state}},"messaging"),false)
assert.equal(provider.capabilityAvailable({...snapshot,connection:{...snapshot.connection,stale:true}},"messaging"),false)
const unavailable = {...snapshot,backendOwner:null,connection:{...snapshot.connection,state:"backend-unavailable"}}
assert.ok(provider.normalizeSnapshot(unavailable))
assert.equal(provider.capabilityAvailable(unavailable,"messaging"),false)
for (const bad of [null, [], {}, {...snapshot,schemaVersion:2}, {...snapshot,schemaVersion:"1"},
  {...snapshot,backendOwner:null}, {...snapshot,backendOwner:"org.kde.kdeconnect"},
  {...snapshot,history:{coverage:"full",truncated:false}}, {...snapshot,history:{coverage:"unknown"}},
  {...snapshot,connection:{...snapshot.connection,stale:0}},
  {...snapshot,connection:{...snapshot.connection,lastSuccessAt:2001}},
  {...snapshot,connection:{...snapshot.connection,observedAt:-1}},
  {...snapshot,capabilities:{surprise:{state:"available",reason:null,evidence:null}}},
  {...snapshot,capabilities:{messaging:{state:"available",reason:"Free form reason",evidence:null}}},
  {...snapshot,capabilities:{messaging:{state:"available",reason:null,evidence:"x".repeat(257)}}}])
  assert.equal(provider.normalizeSnapshot(bad),null)
for (const raw of ["not json", "null", "[]", " ".repeat(provider.maxSnapshotLength+1), snapshot])
  assert.equal(provider.parseSnapshot(raw),null)
// Normalization drops unknown content and copies nested fields; never retain a
// provider's extra body/contact properties through this metadata boundary.
const extra = {...snapshot,body:"private",capabilities:{...snapshot.capabilities,messaging:{...snapshot.capabilities.messaging,body:"private"}}}
const clean = provider.normalizeSnapshot(extra)
assert.equal(JSON.stringify(clean).includes("private"),false)
clean.endpoint.deviceId = "different"
clean.capabilities.messaging.state = "disabled"
assert.equal(snapshot.endpoint.deviceId,opaque.deviceId)
assert.equal(snapshot.capabilities.messaging.state,"available")
console.log("provider identity and contract tests passed")
