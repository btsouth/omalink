# OmaLink product review and proposed roadmap

Reviewed September 25, 2026 against the local marketplace-audit candidate.
This is a product proposal, not an implementation or a claim of phone-tested
compatibility. The marketplace fixes remain a separate local candidate.

## Direction

Make OmaLink the place an Omarchy user goes to message, share, and manage their
phone connection. Keep Android first in implementation order, while treating
iPhone setup, failure handling, and useful supported workflows as first-class.
Use existing phone transports behind one consistent interface.

The highest return comes from completing daily tasks and making failures
understandable. More buttons alone will not make users replace their other apps.
The ranking below is engineering judgment from source review, not measured
market demand. Effort is relative, not a calendar estimate.

## Highest-return work

| Priority | Work | Value / effort | What must be true before shipping |
| --- | --- | --- | --- |
| 1 | Guided setup, device selection, connection diagnostics | Very high / medium | Distinguish unpaired, offline, backend unavailable, disabled capability, unknown permission state, and empty data. Retain the chosen device by stable ID. Never send to a different phone after reconnect or reordered discovery. |
| 2 | Complete file/photo sharing and quick-send actions | Very high / medium | Multiple files, explicit destination, incoming-files view, useful errors, filename conflict handling, and file-manager/keyboard entry points. Show only transfer progress, cancellation and completion the backend can actually confirm. |
| 3 | Reliable messaging state | High / medium | Separate submitting, backend acceptance, confirmation in phone history, failure, and unconfirmed outcome. Keep failed text available. No automatic retries that can duplicate a message. Paginate history within bounded memory. |
| 4 | iPhone messaging through an optional BlueFerry adapter | High reach / medium-high | Same OmaLink conversation UI, honest recent-only history, safe group routing, backend-version checks, and tested Bluetooth reconnect. Label experimental support until a meaningful phone/controller matrix passes. |
| 5 | Better clipboard and link handoff | High / small-medium | One keyboard action, clear source/destination, explicit send/receive affordances, useful phone-side instructions. Sensitive clipboard history must be opt-in; no silent archive of passwords or OTPs. |
| 6 | Notification controls users can understand | High / small-medium | Select observed apps instead of typing substring filters. Show when filtering explains an empty list. Add per-app mute, presentation mode and optional hidden panel contents, preserving private popups. |
| 7 | Photos and phone files | High / medium | Browse granted Android folders, import selected originals, handle duplicates and interruption. Add one-way photo import before promising continuous synchronization or backup. |
| 8 | Optional Android screen/control through scrcpy | High for some users / medium-high | Explicit device authorization, clear USB/wireless setup, reconnect handling, and a visible end-session action. No required debugging setup for ordinary messaging or sharing. |

Keyboard navigation, accessible names, visible focus, scaling, long text,
international phone numbers and translation readiness belong in every phase.
They should not be deferred until after adding features.

## What current source shows

- `Panel.qml` renders several device cards but messages, unread state and
  notifications repeatedly use `devices[0]`. Device selection is a correctness
  prerequisite for any additional transport.
- `Service.qml` opens `kdeconnect-app` for setup. The empty states do not guide
  users through individual capabilities or distinguish permission uncertainty.
- `bin/omalink` shares text and URLs, but has no outgoing file workflow.
- `Messages.qml` creates optimistic messages and stops reconciliation after a
  bounded number of attempts without a clear terminal unconfirmed state.
- Refreshes use repeated status/message polling. Existing custom rows and media
  controls need explicit keyboard and accessibility acceptance coverage.
- Current memory-only messaging is a useful privacy default. Adding backend
  history must not silently change that promise.

The independent product review reached the same priorities: setup, complete
sharing, explicit device identity, and understandable messaging outcomes.

## iPhone: incorporate existing work

Two existing Omarchy projects make iPhone integration more feasible than a
KDE-Connect-only plan suggests.

| Route | Useful capability | Important boundary | Proposed role |
| --- | --- | --- | --- |
| [BlueFerry](https://github.com/erikwb/blueferry) | Direct Bluetooth messaging and contacts, optional notification mirroring; no Mac or Apple login on Linux | Experimental. Only messages observed while connected, no archive import, attachments, reactions, typing indicators or complete sent history. Ambiguous group membership restricts replies. | First iPhone messaging adapter to prototype |
| [Blip](https://github.com/nixfred/blip) | Mac-backed Messages history, sending and attachments over SSH | Requires an awake, reachable Mac signed into Messages, with required macOS permissions. OS database changes can break compatibility. | Optional richer messaging route after basic iPhone support |
| [KDE Connect for iOS](https://apps.apple.com/us/app/kde-connect/id1580245991) | Files, links, explicit clipboard sharing, remote input and commands | Test each supported workflow with foreground, locked and background phone states. Do not promise Android messaging or continuous background parity. | Sharing and desktop-control companion |

BlueFerry already separates its backend from its clients. Its versioned
[D-Bus contract](https://github.com/erikwb/blueferry/blob/71749673b862c8f103d2353aeddd1fb54d185cff/data/io.weirdware.BlueFerry.xml)
and [architecture](https://github.com/erikwb/blueferry/blob/71749673b862c8f103d2353aeddd1fb54d185cff/ARCHITECTURE.md)
make an OmaLink client plausible without rebuilding Bluetooth support. Preserve
its opaque thread IDs, checked group-recipient approval and API-generation
checks. Content-free invalidations should trigger bounded private reads.

Before packaging that adapter, audit its setup effects and storage policy.
Upstream pairing and runtime behavior can affect Bluetooth and WirePlumber;
history may be retained by the backend even when OmaLink itself keeps only
memory state. Explain these effects and require intentional setup. Avoid
duplicate popups without silently rewriting another application's preferences.
Its [protocol notes](https://github.com/erikwb/blueferry/blob/71749673b862c8f103d2353aeddd1fb54d185cff/PROTOCOL.md)
describe empirical phone/controller behavior, not an Apple compatibility
guarantee. Source inspection is not physical validation.

Blip is a candidate backend integration, not merely a launcher shortcut. Its
[Linux shim](https://github.com/nixfred/blip/blob/c3b2e7c953dd0d2045f8999ad49f1a08e679b3c7/bridge/linux/blip-shim)
exposes JSON queries and stdin-based sends. Pin its bridge version because it
does not provide an independently versioned public API. Prefer a dedicated,
restricted SSH key, pinned host identity and explicit server setup; do not fall
back silently to general SSH credentials. Surface an asleep Mac separately
from an offline iPhone. Its current Mac setup requires macOS 13+, a logged-in
desktop session, Full Disk Access for the SSH wrapper and Automation permission.
The [security documentation](https://github.com/nixfred/blip/blob/c3b2e7c953dd0d2045f8999ad49f1a08e679b3c7/docs/SECURITY.md)
explains that this Full Disk Access grant also affects other SSH sessions.
Preserve exact message text using the sender's `--keep-dashes` option and keep
external link previews off by default. Current bridge code does not send
tapbacks, edits or threaded replies. Importing its code requires retaining MIT attribution.
BlueFerry backend and its Omarchy plugin have GPL licenses; review the exact
reuse/distribution plan and notices before copying or bundling code. A separate
backend interface keeps upstream maintenance manageable but is not itself a
license determination.

[BlueBubbles](https://github.com/BlueBubblesApp/bluebubbles-app) is another
possible adapter for users who already run its Mac server. Its optional
[Private API setup](https://docs.bluebubbles.app/private-api/installation)
requires disabling SIP; ordinary operation and that enhanced mode must not be
conflated. Do not require weakened Mac security for OmaLink's baseline support.
Choose one Mac route after a small end-to-end comparison rather than maintaining
two from the first release.

An iPhone may eventually have both Bluetooth and Mac messaging connections.
Keep provider and account identity visible, select a send route explicitly,
and never merge conversations solely because their contact names match.
Deduplicate only with reliable identifiers. Never fail over a send with an
unknown outcome to another transport automatically.

## Other major opportunities and limits

**Richer Android messaging.** KDE Connect 26.08.1 already exposes outgoing
attachment URLs and a SIM subscription argument in
[`SmsPlugin::sendSms`](https://github.com/KDE/kdeconnect-kde/blob/v26.08.1/plugins/sms/smsplugin.cpp).
The previous README's blanket statement that KDE Connect did not expose
attachment sends was too broad and has been corrected. Prototype outgoing MMS
and dual-SIM selection with Android/carrier tests before advertising support.
An API argument alone does not establish successful end-to-end delivery.
Notification replies are not full WhatsApp, Signal or RCS conversation sync.

**Use existing KDE capabilities.** Its
[device interface](https://github.com/KDE/kdeconnect-kde/blob/v26.08.1/core/device.h)
offers pairing, reachability, plugin capability information and change signals.
Its [share interface](https://github.com/KDE/kdeconnect-kde/blob/v26.08.1/plugins/share/shareplugin.h)
supports files, and its [SFTP interface](https://github.com/KDE/kdeconnect-kde/blob/v26.08.1/plugins/sftp/sftpplugin.h)
offers browsing. These lower implementation risk, but transfer progress,
permission diagnostics and phone storage access still need verification.

**Calls and cameras.** Incoming-call alerts and mute are smaller extensions than
desktop call audio. Treat dialing, answering and hands-free audio as a separate
feasibility project. [scrcpy](https://github.com/Genymobile/scrcpy) provides an
Android screen/control foundation and optional camera output; neither makes
iPhone mirroring or cellular call audio automatic. Keep it an optional adapter.

**Guest sharing and continuous sync.** [LocalSend](https://localsend.org/) is a
useful benchmark for easy cross-platform file exchange. Supporting unpaired
guests can follow a good paired-device transfer experience. Folder sync is a
larger product involving conflicts, deletions, battery use and retention.
Do not call it backup without recovery/versioning guarantees. If evaluated,
verify the maintained phone client: the original official
[Syncthing Android app was discontinued](https://forum.syncthing.net/t/discontinuing-syncthing-android/23002).

## Implementation sequence

1. Finish the current marketplace candidate's real-phone acceptance and review
   process independently of feature expansion. It remains local pending the
   owner's next instruction.
2. Add stable selected devices, capability-aware setup, honest send outcomes and
   accessible controls. Define a small provider contract around these actual
   needs: identity, capabilities, connection state, threads and send results.
3. Deliver complete file transfer and quick share. In parallel development,
   prototype BlueFerry reads, direct sends and reconnect with synthetic backend
   tests followed by an iPhone. Do not announce compatibility from mocks alone.
4. Ship iPhone messaging after its acceptance gate, then clipboard/notification
   improvements and tested MMS. Move suitable refreshes to backend events with
   coalescing and offline backoff; measure idle work and latency.
5. Add photo access/import, then optional scrcpy and one Mac messaging adapter.
   Keep calls, webcam, guest transfer and continuous sync as separately scoped
   expansions with evidence of demand.

Avoid a transport framework rewrite before the second backend proves what the
shared interface actually needs. Android-only users should not need Bluetooth
messaging or Mac bridge dependencies installed.

## Release acceptance

- Fresh setup to first useful share/message, including denied permissions and
  missing dependencies. Record completion time and where users need help.
- Two Android devices, overlapping thread IDs, disconnect during send, delayed
  confirmation, restart and reconnect. A send must retain its original target.
- Representative Android vendors plus an iPhone, with exact OS/backend versions.
  For Bluetooth support, test more than one controller family and observe
  existing headset/keyboard behavior during pairing and recovery.
- Phone locked, app backgrounded, laptop suspended, Wi-Fi changed, Bluetooth
  switched off, and bridge unavailable. Show stale/unknown state truthfully.
- Unicode and international contacts, duplicate names, shared addresses, group
  roster changes, large files, low disk space, and interrupted transfers.
- Keyboard-only and screen-reader workflows, light/dark themes, high scaling
  and long translated labels. Use omabox for desktop automation.
- No message contents or credentials in logs, process arguments or broadcast
  signals. Verify retention, deletion, notification privacy and backend changes
  rather than assuming OmaLink's present memory-only policy covers them.

Research snapshots: KDE desktop release `v26.08.1`; BlueFerry
`71749673b862c8f103d2353aeddd1fb54d185cff`; Blip
`c3b2e7c953dd0d2045f8999ad49f1a08e679b3c7`. No researched project was installed,
started, connected to a phone, or contacted on the user's behalf.
