# Provider metadata contract

`ProviderModel.js` is a pure JavaScript boundary for endpoint identity and small
metadata snapshots. QML and Node use the same implementation. It does not
activate a backend, send messages, store history or provide iPhone integration.
BlueFerry and Blip are recognized namespaces for adapter development and tests;
recognizing a namespace does not make that provider available in the UI.

The existing KDE helper still produces its existing status schema. This contract
is a separate boundary to adopt when adding adapters. Do not feed a KDE status
object directly to `parseSnapshot`, or treat its schema version as an adapter API
version. An adapter must separately verify the backend's API generation.

## Identity

An endpoint has four required fields:

```javascript
{
  provider: "kdeconnect", // kdeconnect, blueferry or blip
  instanceId: "local",   // stable backend installation or configured gateway
  deviceId: "abc123",   // provider-owned opaque identity
  accountId: null       // actual backend account identity, when provided
}
```

`kdeEndpoint(deviceId)` preserves the current KDE device ID and adds the local
namespace. `normalizeEndpoint(value)` returns a detached canonical object, or
`null` on invalid input. A missing account field and an empty account string are
invalid; explicit `null` means the backend supplies no account identity. The
string `"null"` is a different account. Changing an instance or account creates a
new endpoint; a name, phone number, backend owner or connection address must not
substitute for a stable ID.

`endpointKey(endpoint)` serializes a versioned JSON tuple, in fixed field order.
`threadKey(endpoint, threadId)` includes that full endpoint and the opaque thread
ID in a separate tuple namespace. Both return `""` on invalid input. Callers
must reject an empty key before caching or routing an operation. Do not use
string concatenation with delimiters or merge threads by contact name.

IDs preserve Unicode, punctuation and whitespace exactly. There is no case
folding, trimming or Unicode normalization. Control characters and unpaired
UTF-16 surrogates are rejected to avoid transport-dependent identity changes.
Bounds are UTF-16 code units: instance 256, device/account 1024, thread 2048.
KDE device IDs retain their existing 1 to 128 ASCII alphanumeric restriction.
Numeric KDE thread IDs must be explicitly converted to strings by the KDE
adapter; generic code must not coerce malformed identity fields.

## Current KDE integration

Service exposes the selected phone as `selectedEndpoint` while preserving the
existing `selectedDeviceId` setting and unread-state files. Panel includes the
endpoint when opening Messages. `kdeEndpointFromPayload(payload)` accepts that
explicit local KDE endpoint, or a legacy valid `deviceId` when the endpoint
field is absent. An explicit endpoint with another provider, instance or account
is rejected. A supplied legacy device ID must match the endpoint exactly.
Malformed or unsupported explicit endpoints never fall back to a raw device ID.

Messages rejects invalid or over-65,536-code-unit open payloads without changing
an already open view or dispatching helper commands. Its raw KDE device ID is
derived from the validated endpoint. Endpoint changes invalidate existing read
generations and clear drafts/history; thread cache keys include the endpoint.
This is a routing boundary for the existing KDE backend, not a generic provider
selector. No selection migration or persistent message storage is introduced.

The existing KDE view still uses its own request generations. Unique backend
owner capture and subscriptions are not wired into that transport yet. The
owner-aware functions below define and test the future adapter contract; they
must not be presented as a live owner-transition guarantee.

## Version 1 snapshot

```javascript
{
  schemaVersion: 1,
  endpoint: {provider: "blueferry", instanceId: "local", deviceId: "opaque:phone", accountId: null},
  backendOwner: ":1.21",
  connection: {
    state: "ready",
    observedAt: 1800000000000,
    lastSuccessAt: 1800000000000,
    stale: false
  },
  capabilities: {
    messaging: {state: "available", reason: null, evidence: "api-generation-2"},
    files: {state: "unsupported", reason: "not-supported", evidence: null}
  },
  history: {coverage: "observed-only", truncated: true}
}
```

This example is synthetic metadata, not a claim of tested BlueFerry support.

`parseSnapshot(raw)` rejects non-string or over-65,536-code-unit input before
JSON parsing. `normalizeSnapshot(value)` validates already-parsed objects. Both
return `null` for unsupported contract versions or invalid required fields.
Normalization retains only documented fields and returns detached objects.
Adapters must bound transport bytes before decoding as well; this JavaScript
limit is not a substitute for a subprocess or D-Bus capture ceiling.

Connection states are `unpaired`, `offline`, `connecting`, `ready`,
`backend-unavailable`, `authorization-required` and `unknown`. Timestamps are
nonnegative safe integer Unix milliseconds. `lastSuccessAt` may be `null` and
must not exceed `observedAt`. Adapters decide freshness using their actual
polling or event policy and set `stale` explicitly. The model does not invent a
last-success time or make old evidence fresh. Callers must reevaluate staleness
as time passes, even if no further backend event arrives.

Capabilities are limited to `messaging`, `contacts`, `notifications`, `sharing`,
`clipboard`, `ring`, `media`, `battery`, `files` and `connectivity`. States are
`available`, `unsupported`, `disabled` and `unknown`. Missing capabilities become
`unknown`; unrecognized capability keys are rejected. A reason is `null` or a
stable lowercase alphanumeric/hyphen code up to 64 characters. Evidence is
`null` or a bounded, single-line string up to 256 code units. Evidence must not
contain message contents or authorization secrets. Reasons are translated by
the UI, not displayed as arbitrary backend instructions.

`capabilityAvailable(snapshot, key)` requires a valid snapshot, a unique backend
owner, `ready`, non-stale connection evidence and an explicitly available
capability. A discovered phone or recognized provider alone never authorizes an
action. Backend absence permits `backendOwner: null` only with connection state
`backend-unavailable`.

History coverage and response truncation are independent. `coverage` is
`backend-available`, `observed-only` or `unknown`; `truncated` is required and
boolean. `backend-available` means the backend's available history, never proof
of the phone's complete archive. An observed-only response can also be
truncated. No pagination cursor is invented where a backend has none.

## Pending requests and backend replacement

`requestContext(endpoint, generation, backendOwner)` captures the exact route,
a nonnegative safe integer request generation and the unique D-Bus owner name.
It returns `null` if any field is invalid. A reusable service name such as
`org.kde.kdeconnect` is not an owner identity.

`replyIsCurrent(replyContext, currentContext)` accepts a result only when all
three match. Increment the generation on selection changes, cancellation,
closing the view and owner transitions, including loss and recovery. Fetch the
new owner's API version and capabilities before authorizing new requests. Clear
old proxies and cached evidence. A session-bus reconnect also invalidates all
contexts; owner names are unique only within that bus lifetime. No helper here
subscribes to owner changes or cancels processes automatically; the adapter and
view must wire those events.

A discarded read can be fetched again. An uncertain send must not be
resubmitted, automatically routed through another provider, or claimed failed
solely because its backend disappeared. Keep the existing bounded send-state
logic and require explicit user action for another send.

Run the pure fixtures with `node tests/provider-model.test.js`. They cover
cross-provider identity collisions, opaque identifiers, unsupported tasks,
observed-only and truncated history, schema rejection, stale reads, owner
replacement and backend loss. They do not replace real backend acceptance.

Run `bash tests/provider-runtime.test.sh` only inside omabox. It exercises the
actual Messages component with synthetic KDE routes, rejected provider summons,
namespaced history and delayed responses. Existing selection and send runtime
tests also cover the integration. No real phone or iPhone backend is contacted.
