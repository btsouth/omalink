# OmaLink implementation plan

Status: implementation started, September 25, 2026. This document describes planned work. No
feature or hardware acceptance item below is complete merely because it appears
in this plan. The marketplace audit candidate is a separate prerequisite.

Scope follows [the product roadmap](product-roadmap.md): one useful Omarchy
phone interface, Android first in implementation order, and first-class iPhone
workflows within verified transport limits. Preserve the existing QML UI and
bounded helper design. Add a provider boundary when BlueFerry needs one rather
than replacing the application with a framework first.

## Delivery rules and dependencies

- Keep the marketplace/security fix in its own reviewable commit and PR. Do not
  mix new phone protocols or configuration changes into that diff.
- Implement and validate each slice before starting its dependent slice. Every
  feature PR states automated evidence, physical evidence, and untested cases.
- Optional providers stay optional. An Android installation must not require a
  Bluetooth messaging backend, Mac bridge, adb, camera module, or sync daemon.
- An unavailable permission or unsupported operation is a product state. It is
  not an invitation to guess, retry indefinitely, or reroute to another phone.
- No automatic retry or provider failover for a send whose outcome is unknown.
- Preserve upstream security limits unless a reviewed requirement and replacement
  bound justify changing them. Never remove bounds to obtain complete history.
- Use small commits for an independently understandable behavior change. Open
  draft PRs while code, automated validation, title, or description is unfinished.
  Unreleased source may merge after review; physical acceptance stays an explicit
  release gate until it has actually been performed.

Dependency order:

```text
marketplace baseline
  -> selected device and offline routing
  -> honest messaging outcomes
  -> capability/setup model
       -> files and quick share -> photos/import -> optional folder sync
       -> provider contract -> BlueFerry -> optional Mac messaging bridge
       -> clipboard and notifications
       -> Android MMS and SIM selection
       -> optional screen/control -> optional webcam
       -> call alerts -> separate call-audio feasibility
  accessibility, localization, retention and measured performance: every phase
```

## Identity and contracts

Begin with stable KDE Connect device IDs. At the second provider, introduce
small JSON contracts, validated at helper boundaries and documented with field
types. Type notation below specifies the contract, not a new runtime dependency.

```typescript
type Provider = "kdeconnect" | "blueferry" | "blip";
type Endpoint = {
  provider: Provider;
  instanceId: string;          // local backend or configured Mac gateway
  deviceId: string;            // opaque ID owned by that provider
  accountId: string | null;    // only when the backend supplies account identity
};
type Capability = {
  state: "available" | "unsupported" | "disabled" | "unknown";
  reason: string | null;       // stable code; UI translates the explanation
  evidence: string | null;     // reported interface/version or checked result
};
type Connection = {
  state: "unpaired" | "offline" | "connecting" | "ready"
       | "backend-unavailable" | "authorization-required";
  observedAt: number;
  lastSuccessAt: number | null;
  stale: boolean;
};
type ThreadRef = { endpoint: Endpoint; threadId: string };
type SendRequest = {
  operationId: string;
  endpoint: Endpoint;
  threadId: string | null;
  recipients: string[];
  body: string;
  attachmentRefs: string[];
  subscriptionId: string | null;
  expectedGroupToken: string | null;
};
type SendResult = {
  operationId: string;
  state: "submitting" | "accepted" | "confirmed-in-history"
       | "failed" | "unconfirmed";
  backendMessageId: string | null;
  reason: string | null;
  retrySafe: boolean;
};
```

Use a canonical serialization or structured key for endpoint identity, not an
unescaped concatenation. Thread keys always include endpoint identity. Contact
names, phone numbers, Bluetooth labels and discovery order are not device IDs.
Do not merge conversations across providers by matching names or previews.

A user may explicitly associate a BlueFerry endpoint and an iOS KDE Connect
endpoint with one physical phone. Store that association as a separate local
record. Capabilities remain route-specific. A Mac gateway is a messaging
account route, not evidence of an iPhone's battery or reachability.

Represent history coverage separately: full available backend history,
recent/observed-only, truncated, or unknown. Add bounded page/cursor fields only
where the backend implements them; otherwise display the limit. An event means
"invalidate and fetch privately," not permission to broadcast message content.

Version the OmaLink helper envelope from the first provider extraction. Reject
malformed required fields and unsupported contract versions. Bind replies to
request generation, selected endpoint and backend owner. A backend restart must
invalidate old proxies, pending reads and cached capability evidence.

## Phase 0: release the audit baseline independently

- [x] Review the existing dirty changes against `docs/marketplace-audit.md`.
- [x] Run current model, QML, shell, plugin-validator, CLI, audit and runtime
  checks using the documented isolation split. Record exact candidate SHA.
- [ ] Perform or explicitly leave open the real-phone acceptance checklist.
- [x] Commit the audit fixes separately. Verify the exact PR title, description,
  branch, rendered content, diff and checks after publishing a draft.
- [ ] Update marketplace evidence only when the submitted revision actually
  includes the fixes. Marketplace approval and a passing local test are separate.

Audit candidate: `7d2e99a`, merged [PR #4](https://github.com/btsouth/omalink/pull/4).
Local automated checks passed; real-phone acceptance and marketplace re-review
remain open. No installation or real-desktop mutation was performed.

## Phase 1: the first three feature PRs

### PR 1: stable selected device and offline routing

Touch `Service.qml`, `Panel.qml`, `Model.js`, selection settings/state, and
focused tests. Keep the first implementation KDE Connect-specific, with a seam
for endpoint identity later. Full paired-device enumeration belongs to PR 3;
this first slice can retain the selected ID/name while it is unreachable.

- [x] Add a selected-device control and persist `selectedDeviceId` and its last
  known display name through `shell.updateEntryInline`. Choose the only
  discovered device initially; with several, require a visible selection.
  A once-established selection never changes because discovery order changes.
- [x] Replace every action/read using `devices[0]` with a resolved selection.
  Include notifications, unread counts, clear actions and Messages launch.
- [x] Keep the selected offline device visible, disable unavailable actions,
  and show why. A successful empty discovery is not the same as a failed read.
  Disable mutations after failed status reads instead of trusting stale data.
- [x] Clear device-scoped notification reply/share fields on selection change.
  Freeze the destination of in-flight operations and show that destination.
  Switching the view must not redirect or duplicate an operation already sent.
- [x] Reject late unread/thread results for an old selection or generation.
  Status lists all devices and cannot change an established selection.

Automated acceptance: reordered arrays, two devices with overlapping thread
IDs, selected-device disconnect, failed enumeration, restart, removal of a
paired device, pending reply during selection change, and late results. Isolated
UI acceptance: selector, offline state, keyboard path, long names and scaling.
Physical acceptance: two paired phones and disconnect during a prepared reply.

Implemented selection evidence: model/CLI regression checks, actual Panel and
Service tests in omabox (including two panel instances, late reads after an
away-and-back switch, persisted settings, and a fixed in-flight ring target),
plugin validation, and the existing adversarial/lifecycle suite pass. Inspected
dark 1920x1080 and light 1366x768 panels; Tab and Enter selected a synthetic phone.
Real phones, screen-reader acceptance and high scaling remain unverified.

### PR 2: honest messaging send outcomes

Touch `Messages.qml`, pure send-state functions in `Model.js` or a small new
model module, helper error/result output, and tests. Do not add new transports.

- [x] Introduce the explicit send state machine above and operation IDs.
- [x] Treat successful command submission as backend acceptance, not delivery.
  Only backend/history evidence can advance the visible confirmation state.
- [x] Give bounded reconciliation a terminal unconfirmed state. Preserve the
  text for inspection or intentional resend; explain possible duplication.
- [x] Keep definitively failed input editable. Never silently resend after
  reconnect, restart, timeout, selection change or transport change.
- [x] Distinguish cancellation before dispatch from stopping observation after
  dispatch. The latter does not claim to cancel the phone's send.
- [x] Keep pending-send state scoped to its original endpoint/thread. When the
  message window closes, preserve the existing no-persistent-body policy and
  explain that an already submitted send may still finish.
- [ ] Prefer stdin/private bounded pipes for new content-bearing helper calls.
  Migrate existing message-body arguments in a bounded separate commit if needed.

Acceptance: success with delayed history, definite rejection, lost response,
history never arriving, repeated identical messages, window close/reopen,
disconnect mid-send and late completion. Assert no automatic duplicate calls.
Only identify delivery/read receipts if the backend really reports them.

Implemented in a separate messaging slice. Nonzero transport exits are
conservatively unconfirmed because the helper cannot prove non-dispatch; only
local validation establishes not submitted. Reconciliation is bounded to six
extra reads and a 30-second observation window. Exact text/time matching also
requires a previously loaded thread snapshot and rejects prior/future records;
it is correlation, not backend message identity or a delivery receipt. New or
unviewed threads can remain unconfirmed. An identical concurrent send made on
the phone remains ambiguous, so the UI says a matching message was found.

Pure-model and actual-QML regression coverage includes prior identical messages,
missing snapshots, reused history records, two provisional recipients, editing
while another thread loads, partial failed reads, uncertainty, preserved text,
exact Unicode contents and late completion after close/reopen. New observations
remain in memory; content-bearing legacy helper arguments are not migrated yet.
Physical delivery, screen-reader acceptance and complete translation remain open.

### PR 3: capability-aware setup and diagnostics

Implemented and locally validated. PRs #4, #5 and #6 merged into `main` at `523e200`.
The automated and isolated UI evidence above applies to those source changes;
physical acceptance and marketplace re-review remain open.

- [x] Discover KDE backend/version and supported plugin interfaces. Distinguish
  capability support from current readiness and user permission.
- [x] Enumerate paired devices as well as reachable ones, replacing the retained
  selection placeholder with actual pairing/reachability evidence. Preserve null
  battery/network values and distinguish an unpaired device from an offline one.
- [x] Provide setup steps for install, pair, reachability and the desired task.
  Name Android permissions accurately; missing data alone means unknown.
- [x] Use KDE pairing APIs or an explicit native-manager handoff. Never mutate
  packages, firewall, network, Bluetooth or another app's settings during a read.
- [x] Add per-capability unavailable explanations, freshness time and retry.
- [x] Add a redacted diagnostics export containing versions, state and bounded
  error codes, excluding bodies, contact lists, tokens and credentials.

Acceptance: clean install, daemon absent, backend crash, disabled plugin,
permission denied/unknown, paired offline device, usable messaging with absent
media capability, and user completing first share without developer assistance.

Automated evidence: model and metadata contracts, failure/timeout/size boundaries,
owner restart, diagnostics redaction, messaging preflight, CLI and adversarial
checks pass. Actual Panel/Service tests cover capability changes during reads,
unknown pairing/reachability, offline selection, stale status, and blocked actions.
Send/lifecycle regression suites and plugin validation pass in omabox. Dark
1920x1080 and light 1366x768 setup views were inspected. Real-phone permissions,
first-use success and screen-reader acceptance remain open. The legacy SMS CLI
has a narrow backend-restart race after preflight; no failed dispatch is retried
or represented as definitely unsent.

## Phase 2: transfers, handoff and the provider boundary

### PR 4: complete KDE file transfer

- [ ] Probe the supported file/share interface, including `shareUrls`, against
  the tested desktop release. Inventory which states and cancellation callbacks
  it exposes before drawing a progress bar.
- [ ] Add explicit destination plus multi-file picker/drop support. Validate
  local regular-file inputs, ownership expectations, paths, count and size limits.
- [ ] Model submitted, transferring when observable, completed when confirmed,
  failed and unknown separately. Show indeterminate progress when bytes are not
  exposed. "Stop waiting" must not be labeled "Cancel transfer."
- [ ] Add bounded received-transfer activity and Open folder. Determine actual
  backend destination and conflict semantics; do not rescan every Downloads file
  and imply OmaLink received it. Refuse unsolicited auto-open of received files.
- [ ] Handle low disk, same names, Unicode, partial transfer and disconnect.
  Retain no source/recipient history beyond a documented bounded policy.

### PR 5: quick share and clipboard

- [ ] Add one explicit share entry point for clipboard, URL, text and file URIs.
  Let a shortcut/file-manager action invoke it with an unambiguous destination.
- [ ] Receive clipboard content only through a supported backend path. Explain
  Android/iOS foreground restrictions and required phone-side gestures.
- [ ] Do not add automatic clipboard history. Any later history is opt-in,
  bounded, expiring and clearable; OTPs/passwords must not be silently archived.
- [ ] Show source and destination, preserve exact contents, bound content length,
  and avoid logging or passing sensitive text in command arguments.

### PR 6: extract the provider boundary with synthetic fixtures

- [ ] Keep the existing KDE implementation behind the documented contract.
  Implement capability and connection normalization, cancellation and owner
  changes. Do not move working view code merely for architectural symmetry.
- [ ] Add endpoint-aware selection and thread refs without changing KDE IDs.
- [ ] Add synthetic second-provider fixtures covering unsupported operations,
  recent-only history, opaque IDs, stale events and backend loss.
- [ ] Introduce migrations only for selection metadata. Preserve unread state
  and do not import/copy message bodies into persistent storage.

## Phase 3: direct iPhone messaging

### PR 7: BlueFerry read-only adapter and setup

Target the researched BlueFerry generation 2 API at
`71749673b862c8f103d2353aeddd1fb54d185cff`, subject to a fresh check before coding.
The `Messages1` interface suffix does not mean `GetStatus.api_version == 1`.

- [ ] Connect to the same owner-bound proxy used to read `GetStatus`; require a
  supported `api_version` on every new backend owner. Never call a mismatched API.
- [ ] Adapt `GetStatus`, `ListThreads`, bounded contact reads and supported
  history reads. Preserve opaque thread keys, group uncertainty, truncation and
  history coverage. Do not present backend observations as an imported archive.
- [ ] Subscribe to `Events1` invalidations and coalesce bounded private reads.
- [ ] Provide explicit setup/repair handoff using documented upstream operations.
  Audit Bluetooth controller changes, pairing, service activation, WirePlumber
  fragments and their removal before exposing one-click setup.
- [ ] Explain storage policy and wallet-locked states using backend-reported
  values. Retained BlueFerry history is independent of OmaLink's memory cache.
- [ ] Audit the exact GPL reuse/distribution boundary. Prefer consuming the
  separate installed backend without copying frontend implementation. This
  design choice is not a substitute for checking license obligations.

### PR 8: BlueFerry direct and checked-group sending

- [ ] Map `SendOutcomeUnknown` to unconfirmed and preserve recipient route.
- [ ] Use `SendToThreadChecked` for groups with the current displayed roster and
  `expected_group_token`. Invalidate approval after roster change; never derive
  recipients from a display title or send to an ambiguous group automatically.
- [ ] Expose local read/star/delete actions only with accurate backend semantics.
  Label backend-history deletion separately from deletion on the iPhone.
- [ ] Resolve popup ownership through an explicit setting; do not silently edit
  BlueFerry preferences. Deduplicate only on verified identifiers.
- [ ] Keep unsupported attachments/full archive/call controls visibly unavailable.

Physical release gate: current iPhone OS, at least two Bluetooth controller
families, foreground/locked phone, laptop suspend, reconnect, pairing repair,
wallet locked, changed group roster, unknown send result and concurrent headset
or keyboard use. Ship as experimental until this matrix has actual evidence.
Pairing tests may change Bluetooth/audio state and require the owner's explicit
real-desktop/hardware participation. Mocks establish contracts, not compatibility.

## Phase 4: notification/privacy, Android messaging and performance

### PR 9: usable notification policy

- [ ] List observed app identities with per-app enable/mute rather than requiring
  substring editing. Preserve a compatible migration for existing filter strings.
- [ ] Add filtered-empty explanations, temporary presentation mode and optional
  hidden panel contents. Keep notification popups content-free by default.
- [ ] Model per-provider/per-endpoint policy explicitly; prevent duplicate popup
  delivery without rewriting another application's configuration silently.
- [ ] Add safe notification actions only when the originating provider reports
  them; a messaging-app reply is not a full conversation-sync capability.

### PR 10: Android attachments and SIM selection

- [ ] Verify KDE `SmsPlugin::sendSms` attachment URL and subscription parameters
  against installed desktop/Android versions. Add runtime capability checks.
- [ ] Determine the actual SIM-list source; never invent a slot-to-subscription
  mapping or infer one from a phone label. Fall back to the phone default only
  when that behavior is explicit and accepted by the backend.
- [ ] Add outgoing attachment preparation and limits, preview/removal, selected
  SIM indication, carrier-cost wording where it affects the send decision, and
  the existing honest send-state model. Keep ordinary file share separate.
- [ ] Test MMS with actual carrier settings, dual-SIM devices, disabled data,
  oversize media and a default-SIM change. Do not advertise generic RCS send
  support merely because the notification or history names a conversation RCS.

### PR 11: bounded history and measured event updates

- [ ] Add pagination only where real backend cursors/requests support it;
  otherwise show truncation instead of silently implying complete history.
- [ ] Replace suitable repeated full-status polls with supported signals,
  coalesced targeted reads, offline backoff and reconnect invalidation.
- [ ] Keep bounded media polling where the interface has no useful signals.
- [ ] Record idle CPU/process activity, update latency and worst-case burst
  behavior before and after. Set measured budgets before declaring improvement.
- [ ] Keep independent error recovery for status, history, contacts and transfer
  state; one successful status read must not clear an unrelated history error.

## Phase 5: photos, screen/control and optional Mac messaging

### PR 12: phone files and one-way photo import

- [ ] Use verified KDE SFTP/browse capability and user-granted folders. Detect
  unsupported/locked storage rather than requesting unrestricted phone access.
- [ ] Browse lazily with bounded thumbnail decoding and safe paths. Import
  explicit originals with progress supported by the copy operation.
- [ ] Handle duplicates with a documented identity/hash policy, interruption,
  destination permissions and low disk. Do not delete phone originals by default.
- [ ] State that import is a copy, not continuous sync or a recoverable backup.

### PR 13: optional scrcpy screen/control

- [ ] Probe installed scrcpy/adb versions and USB/wireless support. Bind a
  session to an exact adb serial and verify association with the selected phone.
- [ ] Guide explicit debugging authorization; ordinary OmaLink setup does not
  enable adb, install packages or require debugging.
- [ ] Start/stop a visible session with argument arrays and bounded diagnostics.
  Handle disconnect, locked phone and multiple adb devices; never select the
  first connected device implicitly.
- [ ] Test scrcpy launches only inside omabox during automated desktop work.
  Real phone authorization and input need a separate owner-observed gate.

### PR 14: optional Mac messaging provider

First compare a minimal Blip bridge read/send/attachment workflow with an
existing BlueBubbles installation, if one is available. Select one supported
route; do not implement both before validating the user benefit. Blip is the
current source-reviewed candidate at
`c3b2e7c953dd0d2045f8999ad49f1a08e679b3c7`.

- [ ] Pin bridge version/schema and retain Blip and vendored upstream MIT
  notices. Prefer the bridge commands to embedding its complete QML frontend.
- [ ] Require a dedicated restricted SSH key and verified host identity. A
  missing dedicated key is an error, not permission to use general SSH access.
- [ ] Explain the awake/logged-in Mac requirement, Full Disk Access granted to
  the SSH wrapper, and Messages Automation. The disk-access grant also affects
  other SSH sessions. Optional Accessibility/read-receipt behavior is separate.
- [ ] Read history and attachments through bounded private queries. Send exact
  message text on stdin with `--keep-dashes`; respect bridge text/file limits.
- [ ] Surface gateway sleep, revoked grants, schema mismatch and unknown send
  outcomes. No automatic failover to Bluetooth on ambiguous submission.
- [ ] Keep external link-preview fetching off by default and retain the current
  no-persistent-message-body default in OmaLink.
- [ ] Do not promise tapback/edit/threaded-reply sends absent implementation.
  Never require SIP disabling for baseline support. If BlueBubbles is chosen,
  separate its ordinary features from its optional private-API setup.

Physical gate: owned Mac/iPhone test conversation, direct/group sends, selected
attachment transfer, SMS/RCS route where available, Mac sleep, permission loss,
wrong key, unknown response, message identity and deduplication across routes.

## Phase 6: separately scoped expansions

Each item begins with a small feasibility result and a defined supported route.
An inconclusive prototype remains unshipped rather than becoming a misleading
button. These are planned investigations followed by implementation if feasible.

| Work | Concrete first slice | Gate before expansion |
| --- | --- | --- |
| Calls | Capability-reported incoming call alerts and mute where supported | Verify exact alert/mute behavior. Dialing, answering and desktop call audio each need a separate transport/audio-routing test; no inferred iPhone or carrier-call support. |
| Webcam | Optional scrcpy camera output with explicit start/stop and actual target-device support | Verify camera source, resolution, frame rate, virtual-camera/module prerequisites and microphone separately. Show active capture, revoke cleanly, and test meeting-app interoperability. |
| Guest sharing | Evaluate LocalSend interoperability or an explicit installed-app handoff, then a bounded receive/send workflow | Verify discovery/protocol/license, recipient confirmation, cancellation, filename conflicts, network exposure and temporary access. Do not auto-accept anonymous files. |
| Folder sync | Choose a maintained desktop/mobile backend and prototype one user-selected folder | Verify maintained Android/iOS client availability, direction, conflicts, deletions, versioning, battery/background limits and dry-run preview. Recover interrupted runs and restore a deleted/overwritten file before calling it backup. |
| Richer media controls | Select actual remote player and capability-reported controls | Confirm player-switch API, seek/volume support, stale metadata and multiple sessions; keep unsupported controls disabled. |

## Accessibility and internationalization in every PR

- [ ] Every custom row, attachment action and slider has keyboard activation,
  visible focus, useful accessible name/role/value and logical tab order.
- [ ] Complete open/select/read/reply/share/dismiss workflows without a mouse.
  Check Escape behavior and focus return after overlays close.
- [ ] Validate theme contrast, high scaling, narrow screens, large text and
  long translated labels inside omabox. Record a screen-reader acceptance gate.
- [ ] Route new user-facing strings through the host-compatible translation
  mechanism, avoiding concatenations that break pluralization or RTL layout.
- [ ] Preserve exact message text, Unicode, emoji, combining marks and direction.
  Test international addresses and duplicate contacts. Do not resolve contact
  identity through a last-ten-digits match when it is ambiguous.
- [ ] Localize dates and numbers while keeping stable machine IDs untouched.

## Retention, migrations and ownership

Default OmaLink message/contact/thread caches remain memory-only and bounded.
Selection, per-device preferences and unread timestamps may persist privately.
An optional provider can retain its own data; the UI and documentation must say
which component owns it, how long it stays and how the user clears it.

- [ ] Add a versioned state file with atomic writes, private permissions, size
  limits and explicit migrations. Preserve legacy state until a verified new
  record exists; do not destroy it during a failed migration.
- [ ] Keep migrations idempotent and test older-state downgrade behavior. Never
  infer account/device associations from display names during migration.
- [ ] Keep credentials in backend-owned SSH/keyring mechanisms, not widget
  settings or diagnostic exports. Do not duplicate private keys into plugin data.
- [ ] Separate Forget in OmaLink, unpair device, delete backend history and remove
  received files. Explain the exact effect and request destructive confirmation
  only for the action the user selected.
- [ ] Bound and expire transfer metadata/thumbnails if introduced. Saved originals
  remain user files; no expiry task silently deletes them.
- [ ] Test wallet locked, state corruption, full disk, concurrent readers, late
  process results and interrupted atomic writes without leaking content.

## Backend versions, tests and packaging

Maintain a small compatibility table with provider version, interface generation,
minimum tested phone OS, optional capabilities and physical evidence date. Start
from KDE desktop `26.08.1`, the pinned BlueFerry/Blip snapshots above, and record
the Android/iOS app versions actually used. These are research baselines, not
claims that all later versions are compatible. Probe runtime capability before
enabling a button and give useful mismatch instructions.

Validation layers:

1. Pure model/contract tests for identity, routing, serialization, state machines,
   boundaries, migrations and international inputs. Use synthetic fixtures only.
2. Helper tests with controlled fake transports and a private bus: limits,
   disconnects, cancellation, backend-owner changes and malformed responses.
3. Isolated desktop checks through omabox for QML, shell/plugin validation,
   notifications, portals, keyring/session D-Bus and screenshot/keyboard review.
   Do not launch these tests on the user's desktop by accident.
4. Explicit physical acceptance on phones/Mac: pairing, permission prompts,
   actual delivery, transport loss, lock/background behavior and resource use.
   Use owned test recipients. Never send a live message as an implicit smoke test.
5. Packaging checks from a clean install and upgrade: optional dependencies absent,
   provider unavailable, uninstall cleanup, rollback and retained user files.

Run only checks justified by the changed behavior, then required package gates.
Do not repeat whole-suite runs without a change or unresolved concern. New
capabilities require behavioral tests, not snapshots mirroring implementation.

Ship optional integrations in disabled/unconfigured state. Plugin installation
must not silently pair devices, change Bluetooth/WirePlumber, grant permissions,
enable debugging, enroll SSH keys, install system packages or enable sync. Setup
must describe concrete changes and use provider-supported rollback paths.

For each release: reconcile version/changelog, exact SHA, CI, local checks,
hardware matrix, privacy/retention documentation and install/upgrade behavior.
Verify the live PR diff, title, body, source branch and checks after updates.
Register every worked PR with the thread when that tool is available. Feature
documentation must label proposed, experimental and physically verified support
accurately. A passing mock or marketplace check never establishes phone support.

## Completion checklist

- [ ] Phase 0 audit release baseline
- [ ] Phase 1 selected device, messaging outcomes and setup
- [ ] Phase 2 transfers, handoff and provider contract
- [ ] Phase 3 direct iPhone messaging
- [ ] Phase 4 notifications, Android MMS/SIM and event performance
- [ ] Phase 5 photos, screen/control and optional Mac messaging
- [ ] Phase 6 calls, webcam, guest sharing, sync and richer media feasibility
- [ ] Accessibility/internationalization gates for every shipped workflow
- [ ] Retention/migrations and provider license/version checks
- [ ] Packaging, real-device acceptance and release evidence

Checked entries record completed implementation or verification. Unchecked
entries remain planned or await physical acceptance; no phase is complete solely
because a draft PR exists.
