# OmaLink

Your phone, native to Omarchy.

OmaLink is a themed Omarchy Shell plugin powered by KDE Connect. It puts the
phone controls and information that matter directly in the bar, without a web
account or cloud relay. An optional experimental view reads local iPhone history
from an already-running BlueFerry backend.

## Features

- Paired, offline and unpaired devices with task availability and connection setup
- Connected phone, battery, charging state, network type, and signal strength
- SMS/MMS/RCS and authenticator notifications with dismissal on the phone
- Notification sources you can tune, and popups you can turn off while keeping
  the list in the panel
- Notification popups that open the OmaLink panel on click, with message
  contents always hidden in popups (read them in the panel instead)
- Unread text messages readable directly in the panel, even when the phone
  redacts notification contents; click one to open its conversation
- Clear unread messages from the panel (KDE Connect cannot mark conversations
  read on the phone, so clearing is local: a cleared thread returns only when
  a new message arrives)
- Quick reply to notifications from messaging apps
- Open a text's conversation straight from its notification
- SMS conversation list with contact names, search, and unread state
- Read conversations, copy message text, send replies, and start new messages
- MMS photos inline, with a full-size viewer, save to Downloads, and open
  actions; videos and other attachments open in their default app
- Send the desktop clipboard to the phone
- Send text or links to the phone
- Choose multiple local files, preview the destination and submit one bounded batch
- Ring a misplaced phone
- Now-playing media controls for the phone: track, artist, and album art with
  play/pause, previous/next, seek, and volume
- Native colors and typography across Omarchy themes
- Memory-only message cache that is cleared when the message window closes

## Experimental iPhone history

Enable **Experimental BlueFerry history** in the widget settings after installing,
pairing and starting BlueFerry separately. The panel shows connection and storage
state, then opens bounded conversations and cached contacts in OmaLink. Viewing
history does not send messages or mark them read. Turning the option off closes
the view and clears its cached contents.

This is BlueFerry's local observed history, not a complete iPhone archive or a
connection associated with the selected KDE Connect phone. Sending, attachments,
phone setup and storage changes remain unavailable in this integration. It is
experimental and has not passed physical iPhone acceptance. See the
[setup, retention and compatibility guide](docs/blueferry-setup.md).

## Requirements

- Omarchy 4.0 or newer
- An Android phone with [KDE Connect](https://kdeconnect.kde.org/) installed
- `kdeconnect`, `jq`, and `python-dbus` on the Omarchy computer
- The standard Omarchy tools from `bash`, `coreutils`, `util-linux`, `systemd`,
  `dbus`, `libnotify`, `xdg-utils`, `findutils`, `gawk`, `grep`, and `sed`

Qt and Quickshell come with Omarchy. Text and messaging use the system Python
interpreter at `/usr/bin/python3` and its `dbus` module, provided by Arch
`python-dbus`. A virtual environment or mise Python does not supply this runtime
dependency. Node.js is only needed for development tests.

## Install

Install and enable OmaLink:

```sh
omarchy plugin add https://github.com/btsouth/omalink.git --enable
```

Install any missing dependencies:

```sh
omarchy pkg add kdeconnect jq python-dbus
```

Open OmaLink from the bar, choose **Open pairing**, and approve the computer in
KDE Connect on your phone. Enable the plugins you want in **Manage devices** and
on the phone. For messaging, follow KDE Connect's SMS and contacts permission
prompts. Notification access is a separate Android setting. Clipboard behavior
can require a phone-side gesture; see the [KDE Connect guide](https://userbase.kde.org/KDEConnect).

Both devices must be able to reach one another, normally on the same local
network. OmaLink never installs packages itself.

## Share files

Select a phone, expand **Share files**, choose one or more files, review the
preview and press **Send files**. Selecting files does not submit them. Switching
phones or losing file-sharing availability clears the selection. A submitted
request keeps its original destination and is never retried automatically.

Each request allows up to 32 readable regular files, totaling at most 8 GiB.
Folders and special files are refused. Unicode and spaces are preserved;
explicit symlinks to readable regular files are allowed. Files can change after
validation because KDE Connect opens them asynchronously.

A successful request means KDE Connect accepted the batch, not that the files
arrived. Its `shareUrls` API does not expose aggregate outgoing progress,
completion or cancellation. Check KDE Connect and the phone for results. If the
outcome is unknown, check before choosing the files again to avoid duplicates.
OmaLink keeps the preview in memory and clears it on submission; it adds no
persistent transfer or path history. KDE Connect and the native picker manage
their own caches and recent-file metadata. Incoming transfer activity is not yet
shown in OmaLink. Drag-and-drop is deferred; use the file picker.

For an explicit device ID and local absolute paths from a checkout:

```sh
bin/omalink-files DEVICE_ID '/absolute/path/first file.pdf' '/absolute/path/photo.jpg'
```

## Connection setup and diagnostics

The panel lists up to eight known KDE Connect devices, including paired offline
phones and discovered devices awaiting pairing. Selecting an offline phone keeps
that destination selected. It does not send actions to another phone. Pair new
devices through **Manage devices**; OmaLink does not change packages, firewalls,
network settings or KDE Connect plugin settings.

The selected phone shows which tasks its KDE Connect plugins support, which are
disabled, and which cannot be confirmed. Available means the backend reports a
loaded, enabled plugin for a paired, reachable device. It does not prove phone
permissions or successful delivery. Failed or outdated status pauses actions.

Android messaging remains the supported messaging path. An iPhone with KDE
Connect can expose a different set of tasks; keep its app open while connecting.
The [upstream iOS limitations](https://github.com/KDE/kdeconnect-ios/blob/master/README.md)
explain its background behavior. BlueFerry and Mac messaging integration remain
planned work.

**Connection diagnostics** shows a selectable report with backend version,
pairing/reachability and plugin state. It excludes phone names and IDs, addresses,
contacts, message bodies, notification text, media titles, file paths and tokens.
To save the same bounded report from a checkout:

```sh
bin/omalink diagnostics > omalink-diagnostics.json
```

Diagnostics inspect metadata only. Missing phone permissions remain unknown;
they are not inferred from absent data. Reports do not contain KDE Connect logs.

## Remove

```sh
omarchy plugin remove omalink.phone
```

This leaves KDE Connect, its pairings, and its cached files untouched. Optional
OmaLink unread state lives under `~/.local/state/omalink`; remove that directory
if you no longer want it.

Versions through 0.2.2 could add `[Event/notification]` with `Action=` to
`~/.config/kdeconnect.notifyrc`. Version 0.2.3 does not change this file. If you
want KDE Connect's popups back after removing OmaLink, review that section and
remove the empty `Action=` override that OmaLink added. Preserve any settings
you configured yourself.

## Messaging notes

The panel remembers your selected phone for messages and notifications. A single
available phone is selected initially; with several phones, choose **Use this
phone**. Disconnecting the selected phone does not switch to another one.
The selected ID and last known name are stored in the widget's `shell.json`
settings. Switching phones clears unsent panel share/notification-reply drafts.
Actions pause when status cannot be refreshed; an unavailable selected phone
remains visible until it reconnects or you select another.

OmaLink uses KDE Connect's Android messaging interface. It can read SMS/MMS
conversation history, send SMS messages, and show that a message contains an
attachment. OmaLink does not yet send attachments or expose full RCS
conversations. KDE Connect's desktop messaging API includes attachment-send
support, but OmaLink has not implemented or validated that workflow.

Message history is requested from the phone when needed. OmaLink does not add
its own cloud service or persistent message database.

Sends distinguish **Submitting**, **Accepted by KDE Connect**, **Unconfirmed**
and **Not submitted**. A successful helper call means acceptance, not delivery.
OmaLink makes at most six additional history reads over a 30-second observation
window. If confirmation remains unavailable, check your phone before using
**Edit copy** to prepare another send. OmaLink never retries automatically.

A matching outgoing history record is labeled separately from delivery. The
match uses exact text, time and a previously loaded conversation snapshot;
KDE Connect does not expose a corresponding send ID here. Simultaneous identical
messages sent on the phone remain ambiguous, and new or unviewed conversations
without a prior snapshot stay unconfirmed. Up to 100 local send records remain
in memory until the window closes; closing clears them and does not cancel a
send already submitted to the phone.

## Media controls

OmaLink shows the phone's active media player in the panel with play/pause,
previous/next, seek, and volume. It reads KDE Connect's mprisremote plugin,
which emits no change signals, so the panel's regular polling (every 3
seconds while open) drives the display. If the section never appears, check
that media control is enabled for this computer in the KDE Connect app on
the phone. **Media controls** can be set to Off in the widget settings to hide
the section entirely.

OmaLink does not send desktop playback to the phone. If a media bar appears on
your phone while something plays on the computer, that is KDE Connect's
Multimedia control plugin. Turn it off in the KDE Connect app on the phone:
tap this computer, open its plugin settings, and disable **Multimedia
control**.

## Notification popups

OmaLink's popups show the app name and an invitation to open the panel. They
never include notification titles or bodies, including authenticator codes.
Clicking a popup opens the OmaLink panel. At most four popup helpers run at
once; notifications skipped during a burst remain available in the panel.

KDE Connect may also show its own popups. To avoid duplicates, turn those off
in KDE Connect's notification settings, or turn OmaLink's **Notification
popups** setting Off. OmaLink does not edit KDE Connect configuration.

By default OmaLink only reads notifications from Android messaging apps,
WhatsApp, Microsoft Authenticator, and Google Authenticator. Change
**Notification sources** in the widget settings to add or remove apps
(comma-separated names or Android packages matched anywhere in the app name or
package), or clear the field to allow every notification. **Notification
popups** can be set to Off to keep matching notifications listed in the panel
without desktop popups.

Select **Notification apps** under the panel's phone notifications to set rules
per app for the selected phone. The list shows apps in the phone's current notifications
(from the first 100 checked) plus any app that already has a rule. It is not a
list of installed apps. **Allow** always lists an app, **Mute** hides it from
the panel, popups and **Clear all**, and **Default** follows **Notification
sources**. A mute wins over any source setting. Rules only change what OmaLink
shows; the phone and KDE Connect are unchanged. Apps are matched by Android
package when the phone reports one. Otherwise they are matched by name only,
which the phone chooses and other apps may share. OmaLink keeps up to 100 rules
on up to 16 phones. **Clear all** dismisses every matching notification OmaLink
checked, up to 100, including ones beyond the 25 listed.

Set **Panel message content** to **Hide** to remove unread message previews and
notification rows from the panel, including app names, icons and reply controls.
Counts remain visible, and the per-app list is hidden too. Changing to Hide
clears an unsent panel notification reply.
This is a display preference: existing bounded reads still run, Messages opened
explicitly can show conversations, and KDE Connect or other apps are unaffected.
Use **Notification popups: Off** separately to suppress OmaLink's app-name popups.

## Security and local data

Phone notifications, media metadata, contact records, and attachments are
untrusted input. OmaLink applies these checks before displaying or opening them:

- Image paths must resolve to readable regular files inside KDE Connect's cache
  or per-user icon directory. Files with multiple hard links, remote URLs,
  control characters, markup, and other URI schemes are refused. Art and the
  image viewer accept at most 8 MiB; notification icons accept at most 1 MiB.
  Raster signatures and bounded QML decode sizes are required.
- Notification and message text is rendered as plain text. Popups contain no
  notification content, and the displayed app name is escaped.
- D-Bus captures have an exact 16 MiB disk ceiling. The monitor and pending
  request are terminated and reaped on overflow, cancellation, or completion.
  Conversation requests time out after 12 seconds; attachment requests after
  30 seconds, followed by at most 30 seconds waiting for arrival. Direct reads
  have byte limits and timeouts too. Status, conversation listing, and clearing
  notifications each have a 45-second overall deadline.
- Each status refresh includes at most eight devices, reads the app name and
  package of at most 100 notifications per device, and reads the contents of at
  most 25 it will display. Content of filtered or muted notifications is never
  read. Conversations and threads
  contain at most 200 entries, with at most ten attachment thumbnails per entry.
  Thumbnails are capped at 256 KiB of encoded data. Titles and previews are
  capped at 1 KiB, message bodies at 8 KiB, and names at 256 characters. Contact
  reads are bounded by file count and bytes and return at most 2000 numbers.
- Commands use argument arrays and validated identifiers. Text, URLs, message
  recipients and reply bodies travel through a private stdin pipe and direct
  D-Bus calls, never command arguments, environment variables or body files.
  Requests are limited to 64 KiB of JSON and 8 KiB of UTF-8 text with a 20-second
  deadline. Exact text is preserved, including leading spaces and line breaks.
  Only a complete whitespace-free HTTP(S) URL uses the URL-sharing method.
  Other text uses text sharing. Non-content D-Bus CLI options end at `--`.
- Opening or saving an attachment requires a validated local cache file no
  larger than 2 GiB. Executable files, scripts, and desktop entries are refused.
  Opening additionally refuses web pages and shortcuts. An unavailable MIME
  classifier fails closed. Save destinations are claimed without overwriting
  existing files or following existing symlinks.

OmaLink writes device-specific thread ids and timestamps, never message bodies,
to `~/.local/state/omalink/seen-DEVICE.json`. It also uses private runtime locks,
bounded temporary D-Bus captures, and files you explicitly save to Downloads.
Legacy `seen.json` state is left untouched; unread badges may reappear once
when upgrading to device-specific state.

The Messages window keeps at most five threads in memory. Closing it clears
conversation data, contacts, attachment paths, drafts, and pending display data,
and cancels outstanding reads. Late results cannot reopen an attachment or
repopulate the closed window. A send already submitted to KDE Connect may
still finish after the window closes.

KDE Connect maintains its own caches independently. OmaLink is an unsandboxed
plugin, and opening a permitted attachment hands untrusted content to your
chosen application. These checks do not establish that file contents are safe,
protect against image-decoder vulnerabilities, or prevent KDE Connect or another
process under your account from changing a cached file after validation.

## Settings

Widget settings live in the bar widget configuration: **Refresh interval**,
**Notification sources**, **Notification popups**, and **Media controls**.
OmaLink stores no message data: the conversation cache lives in memory and is
dropped when the Messages window closes.

## Development

Run the checks in an isolated desktop with [omabox](https://github.com/btsouth/omabox).
The private D-Bus fixture also needs the development-only `python-gobject` package:

```sh
node tests/model.test.js
node tests/provider-model.test.js
node tests/private-text.test.js
node tests/blueferry-model.test.js
node tests/send-state.test.js
node tests/capabilities.test.js
node tests/file-share-model.test.js
node tests/private-text.test.js
node tests/blueferry-model.test.js
bash tests/qml.test.sh
shellcheck -S warning bin/omalink bin/omalink-files tests/*.sh
omabox run -- omarchy plugin validate .
omabox run -- bash tests/cli.test.sh
omabox run -- /usr/bin/python3 tests/audit.test.py
omabox run -- /usr/bin/python3 tests/capabilities.test.py
omabox run --net isolated -- /usr/bin/python3 tests/text-transport.test.py
omabox run -- bash tests/files.test.sh
omabox run -- bash tests/runtime.test.sh
omabox run -- bash tests/selection-runtime.test.sh
omabox run -- bash tests/send-runtime.test.sh
omabox run -- bash tests/provider-runtime.test.sh
omabox run -- bash tests/provider-request-runtime.test.sh
omabox run -- bash tests/blueferry-runtime.test.sh
omabox run -- bash tests/blueferry-service-runtime.test.sh
omabox run -- /usr/bin/python3 tests/blueferry.test.py
omabox run -- bash tests/private-request-runtime.test.sh
omabox run -- bash tests/file-share-runtime.test.sh
```

The test suite uses mock phone data and does not send real messages. The text
transport suite requires omabox and registers a mock KDE Connect service on its
private session bus. It checks actual D-Bus argument types, exact content,
preflight rejection, daemon ownership, uncertain outcomes, dependency absence,
the stdin deadline, and process arguments while dispatch is pending.

### Text helper protocol

Scripts that previously called `bin/omalink share`, `sms`, `reply`, or
`notify-reply` must migrate to `bin/omalink text-stdin`. Those old commands now
reject content arguments instead of forwarding them. Send one JSON object on
standard input and close the pipe:

```json
{"version":1,"operation":"sms","deviceId":"PHONE_ID","destination":"+15550000001","body":"Hello"}
```

The common fields are `version`, `operation`, `deviceId`, and `body`. `share`
needs only those fields; `sms` adds `destination`, `reply` adds a decimal string
`threadId`, and `notify-reply` adds `replyId`. Unknown or duplicate fields are
rejected. Write the object directly from the calling application to the child
process stdin; do not put real content in shell command arguments or temporary
files to construct it.

The helper returns one JSON object with `version: 1`, `ok`, `state`, `code`, and
`statusText`. Exit 0 with `accepted` means KDE Connect accepted the request,
not that the phone delivered it. `not-submitted` means validation or preflight
prevented dispatch. `unconfirmed` means dispatch began but its outcome is unknown.
Failures exit 1. Check the phone before intentionally retrying an uncertain
request; there are no automatic retries. A missing `python-dbus` dependency
returns `not-submitted` with code `dependency` and never falls back to command
arguments.

## Roadmap

- Guided setup and permission diagnostics
- File sending
- Event-driven message and media updates

See the [product review and proposed roadmap](docs/product-roadmap.md) for
priorities, iPhone integration options, and the validation required before
claiming support. These are proposed features, not current capabilities.
The [implementation plan](docs/implementation-plan.md) breaks that work into
reviewable changes and records completed implementation separately from
physical-phone acceptance.

## License

[MIT](LICENSE)
