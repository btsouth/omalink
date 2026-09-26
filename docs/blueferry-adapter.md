# Experimental BlueFerry read adapter

`bin/omalink-blueferry` reads an already running local BlueFerry backend. It does
not install or start BlueFerry, configure Bluetooth, unlock storage, send messages,
change read/starred state, delete history, or sync contacts. It uses the system
`/usr/bin/python3` and Arch's `python-dbus` package. There is no subprocess or
command-argument fallback.

The implementation was checked against upstream HEAD
[`71749673b862c8f103d2353aeddd1fb54d185cff`](https://github.com/erikwb/blueferry/tree/71749673b862c8f103d2353aeddd1fb54d185cff),
verified September 26, 2026 UTC. The interface is `Messages1`, but the required
`GetStatus.api_version` is integer **2**. Missing, string, boolean, earlier or later
API versions fail closed. Automated fixtures are not real iPhone validation.

## Identity and history limits

Current BlueFerry status does not expose a stable phone or account identity.
OmaLink therefore represents its local backend history with this exact endpoint:

```json
{"provider":"blueferry","instanceId":"local","deviceId":"local-history","accountId":null}
```

Display this as **BlueFerry local history**, separately from a selected KDE
Connect phone. It is not proof of a particular phone's ownership or identity.
No phone name, MAC address, contact address, service owner, or inferred telephone
number is substituted for a phone identity. This slice permits no sending.

`ListEvents(kinds, limit)` returns a global event tail filtered by event kinds.
It has no thread or phone filter. The adapter never reconstructs conversations
by filtering this tail. Instead, `ListThreads(200)` returns canonical opaque
thread keys with embedded message tails; the `messages` operation repeats that
read and matches the requested key exactly. A missing key returns
`thread_unavailable`, not an empty conversation or a fallback to another thread.

Upstream projects at most 2,000 events into conversations and retains at most
500 messages per thread in a response. It also bounds JSON to 8 MiB and can omit
whole threads or message tails to meet that budget. There is no aggregate
completeness indicator or pagination cursor. Fewer than 200 returned threads
therefore does not prove complete history. Every adapter success carries
`history: {coverage: "observed-only", truncated: true}`. This is local history
observed by BlueFerry, not an imported iPhone message archive.

## Request protocol

Write one UTF-8 JSON object to stdin and close the pipe. Do not put queries or
thread identifiers into shell command arguments or temporary files.

```json
{"version":1,"operation":"status"}
```

A successful status response supplies `backendOwner`, a unique session D-Bus
owner. Subsequent reads must carry that exact owner and the endpoint above:

```json
{"version":1,"operation":"threads","endpoint":{"provider":"blueferry","instanceId":"local","deviceId":"local-history","accountId":null},"expectedOwner":":1.123"}
```

Operations and additional fields:

| Operation | Additional request fields | Backend method |
| --- | --- | --- |
| `status` | None | `GetStatus()` |
| `threads` | `endpoint`, `expectedOwner` | `ListThreads(200)` |
| `messages` | `endpoint`, `expectedOwner`, `threadId` | `ListThreads(200)`, exact key match |
| `contacts` | `endpoint`, `expectedOwner`, optional `query` | Empty query: `ListContacts(0, 100)`; otherwise `FindContacts(query)` |

Unknown and duplicate request fields are rejected. Thread IDs preserve exact
Unicode and punctuation, reject controls and unpaired surrogates, and have a
1,024 UTF-16-code-unit limit. Contact queries are limited to 256 Unicode
characters. There is no automatic pagination, retry, phone association or send.

## Success response

Exit 0 returns one object:

```javascript
{
  version: 1,
  ok: true,
  operation: "threads", // status, threads, messages, contacts
  endpoint: {provider: "blueferry", instanceId: "local", deviceId: "local-history", accountId: null},
  backendOwner: ":1.123",
  apiVersion: 2,
  connection: "ready", // offline, connecting, authorization-required, unknown
  storage: "ready", // locked, disabled, error, unknown
  storagePolicy: "encrypted", // plaintext, none, unknown
  backendRelease: "0.6.2", // bounded version text, or unknown
  map: true, // boolean or null when unknown
  pbap: true,
  ancs: false,
  canReadHistory: true,
  history: {coverage: "observed-only", truncated: true},
  items: []
}
```

`status` always has empty `items`. `canReadHistory` requires storage state `ready`
and policy `encrypted` or `plaintext`. Cached history can be read while the phone
is offline. Locked, disabled, error or unknown storage rejects history/contact
reads with `storage_unavailable`; it never masquerades as an empty archive.

Item shapes are deliberately restricted to plain content and display metadata:

- Threads, at most 200: `threadId`, `names: [name]`, `addresses`, `preview`,
  `timestamp`, `unread`, `incoming`, `isGroup`, `messagesTruncated`,
  `attachmentCount: 0`, `attachments: []`.
- Messages, at most 200: `body`, `timestamp`, `incoming`, `sender`,
  `bodyTruncated`, `attachmentCount: 0`, `attachments: []`.
- Contacts, at most 200 flattened addresses from up to 100 backend contact
  records: `name`, `number`. `number` can be a phone number or email address;
  it is display data, not permission to send.

Thread names/contact names/senders are bounded to 256 UTF-8 bytes, previews and
message bodies to 8 KiB. UTF-8 truncation never splits a character. Thread address
lists contain at most 64 entries of at most 320 UTF-16 code units. Contact records
accept at most 64 phone and 64 email addresses each before flattening. Extra
backend fields, HTML markup variants, raw errors, storage detail and device
addresses are not forwarded. Views must render supplied text as plain text.

Timestamps are nonnegative safe-integer Unix milliseconds decoded from ISO
strings with an explicit timezone. Invalid or timezone-free timestamps cause
that record to be omitted, never replaced with the current time. Incoming state
comes from the backend's explicit outgoing boolean. Unread comes from embedded
incoming messages whose local `read` flag is false; reading here does not mark
anything read. Body and message truncation flags remain explicit.

## Ownership, limits and errors

Each request resolves an existing `io.weirdware.BlueFerry` owner through the bus
and calls only its unique name, with D-Bus auto-start disabled. Non-status reads
reject an owner that differs from `expectedOwner`. API/storage status is checked
before content reads and checked again afterward. The owner is rechecked before
publishing content. Replacement or loss discards the result; no request rebinds
or automatically retries. Callers must invalidate view generations and caches
on owner changes and obtain fresh status before another read.

Limits are 64 KiB of input, 8 MiB of raw backend JSON before JSON decoding, 2 MiB
of serialized output including its newline, and an 18-second deadline including
stdin. Direct D-Bus calls use at most four seconds each within that deadline.
The helper also disables core dumps and caps virtual address space at 256 MiB.
The raw JSON limit applies after D-Bus reception; libdbus must still receive the
wire message. The process memory limit bounds this additional allocation.

Exit 1 returns only `version: 1`, `ok: false`, `operation` (or null for invalid
input), and a fixed `code`. No exception text or backend detail is returned.
Codes are `invalid_request`, `dependency`, `backend_unavailable`,
`backend_changed`, `api_incompatible`, `storage_unavailable`,
`authorization_required`, `rate_limited`, `response_too_large`, `invalid_response`,
`thread_unavailable`, and `read_failed`.

The adapter makes only read-method calls and writes no local content files.
BlueFerry retains its own history according to its configured policy. Its status
method can internally persist setup-verification flags, and its thread reader
builds a local projection. A read-only client does not imply that the running
backend performs no internal local writes. The adapter never invokes upstream
lifecycle helpers, which can activate or restart BlueFerry.

## Validation

```sh
omabox run --net isolated -- /usr/bin/python3 tests/blueferry.test.py
```

The fixture also requires development-only `python-gobject`. It registers a fake
service on omabox's private session bus and tests real D-Bus signatures, backend
absence without activation, owner replacement, storage locks before/after reads,
API mismatch, bounded content, opaque keys, offline history, fixed errors,
contacts, query privacy and the stdin deadline. It never accesses the system bus,
Bluetooth hardware, a real phone, a real keyring or existing BlueFerry storage.
