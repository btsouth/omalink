# Changelog

## Unreleased

- Polish the phone dropdown with larger text, avatar rows and grouped settings.
- Keep new-message drafts and recipients while navigating, and protect unsent
  drafts when closing the Messages window.
- Clear a clicked message from the dropdown after its thread loads, and open
  the requested thread when Messages is already open.

## 0.5.0 - 2026-10-01

- Follow Omarchy's clock setting for 12- or 24-hour message timestamps.
- Redesign Messages with a responsive conversation sidebar, readable type,
  grouped message cards, clearer contrast and a separate reply composer.
- Keep separate drafts while switching threads, and keep the
  latest message visible as cards wrap or the window resizes.
- Open Messages as a normal desktop window that can tile, float, resize and stay
  open alongside other apps. Bring an existing window forward without losing
  its current conversation or draft, and clear local state on explicit close.

## 0.4.0 - 2026-10-01

- Combine SMS notification and unread history rows in one Messages inbox.
- Open a message row before marking it seen; reserve notification dismissal for Clear.
- Update conversations on phone events; coalesce bursts and retain scroll position.
- Simplify send labels, show details beside each message, and reconcile whole-second SMS timestamps.
- Add a multiline reply composer, date separators and a larger conversation view.
- Show only a confidently detected authentication code in a short-lived popup
  with a Copy code button. Ordinary notification text stays out of popups, and
  copied codes carry a sensitive clipboard hint so Omarchy history skips them.

## 0.3.0 - 2026-09-26

- Stop the notification monitor when the shell kills its watcher, instead of
  leaving it running for up to an hour, and remove work directories left by
  killed watchers. The watcher now needs `setpriv` from util-linux.
- Name the sender in text and chat popups ("New message from Rebecca") without
  showing the message. Hidden panel content keeps popups to the app name.
- Refresh phone status in about a quarter second instead of over two: device
  discovery now asks KDE Connect directly rather than through
  `kdeconnect-cli --list-devices`, which always sleeps two seconds.
- Run a refresh requested during another one as soon as it finishes, so a new
  notification reaches the panel right away instead of at the next timer tick.
- Show KDE Connect's cached thread list at once in the panel and the Messages
  window, then update it from the phone. The panel keeps unread messages
  current while closed whenever a notification arrives.
- Match national and international contact-number formats without collapsing
  distinct numbers onto the same short suffix. Senders without digits and
  blank contact numbers no longer match, and CRLF card names lose trailing
  whitespace.

- Add per-app notification rules for the selected phone. Allow, Mute or Default
  apps seen in the phone's current notifications, matched by validated Android
  package or clearly labeled name-only fallback. Status, popups and Clear all
  share one policy, and the source filter setting is never rewritten.
- Explain filtered-empty notification lists and scan limits, stop reporting
  malformed notification IDs as package names, and discard status reads started
  under an older notification policy.

- Add a panel content setting that hides message previews and notification rows,
  clears pending notification replies, and preserves counts and source filters.

- Add opt-in experimental BlueFerry local history and cached contact viewing.
  Require API 2, an existing backend owner and readable storage. Keep this route
  separate from KDE Connect, with no sending, read acknowledgements or setup
  changes. Cancel reads and clear content when disabled or invalidated.
- Send message and shared text through private stdin and direct D-Bus calls.
  Require python-dbus; remove legacy text-bearing command arguments and preserve
  exact Unicode/whitespace with explicit accepted, not-submitted and unknown states.
- Isolate message routes and caches by provider identity and reject malformed
  window requests before changing drafts. Add GitHub model and static validation.

- Add explicit multi-file selection and destination preview, with one bounded
  request per submission and no automatic retries. Report accepted or unknown
  outcomes without claiming delivery.

- Show known paired, offline and unpaired devices with capability-aware setup.
  Disable unavailable tasks, keep null status values unknown, and show freshness.
- Add bounded, redacted connection diagnostics without collecting phone content.

- Show submitting, accepted, matching-history, unconfirmed and not-submitted
  message states. Bound reconciliation, retain uncertain text for editing, and
  never retry a send automatically or label command acceptance as delivery.
- Keep pending message state scoped to its original phone and conversation.
  Distinguish provisional conversations and ignore failed or stale history reads.
- Remember the selected phone for messages and notifications. Discovery order
  and disconnects no longer switch those workflows to another phone.
- Keep the selected phone's name visible while unavailable, pause actions after
  failed status reads, and distinguish failed discovery from an empty list.
- Clear phone-specific panel drafts on selection changes and reject late unread
  results, including switching away and back to the same phone.
- Add the phased implementation plan and isolated multi-phone regression tests.

## 0.2.3 - Unreleased

- Enforce a hard 16 MiB capture limit while requests are pending. Kill and reap
  both producers on overflow or cancellation, and filter signals by device.
- Bound popup workers, contact reads, device metadata, notification clearing,
  attachment image sizes, and the Messages window's thread cache.
- Stop changing KDE Connect notification settings. Popups now hide all titles
  and bodies, including authenticator codes. Document removal and old overrides.
- Fix blank media controls and the doubled D-Bus path used by seek.
- Preserve package-name notification filters and literal option-like message text.
- Prevent late results and old phone data from repopulating closed or reopened
  windows. Store unread timestamps separately for each phone.
- Pass large contact and notification data through streams instead of argv.
- Refuse executable attachments and unknown MIME classification; claim save
  destinations without overwriting an existing file or symlink.
- Add adversarial process tests and real Quickshell lifecycle tests with fake
  phone data.

## 0.2.2 - 2026-09-19

Security, from the follow-up review in omarchy-plugin-marketplace#7127:

- A watchdog now terminates the message and attachment D-Bus captures as soon
  as either exceeds 16 MiB, including while a request is still pending. A
  malicious phone can no longer hold a request open and keep growing the capture.
- The attachment request has a 30-second timeout in addition to the existing
  polling window.
- Direct D-Bus property and list responses are bounded by size and time before
  their contents are truncated, so they no longer have a separate unbounded
  read path.

## 0.2.1 - 2026-09-17

Security, from the report in omarchy-plugin-marketplace#7127 and the review rounds
that followed:

- Album art, notification icons and attachment paths are untrusted input: a path
  is used only when it resolves to a regular file inside KDE Connect's own cache
  or icon directory, with a single link, under a size cap (album art 8 MiB, icons
  1 MiB, attachments 2 GB), and only when its content is a raster image (PNG,
  JPEG, GIF, BMP, WebP). Remote URLs, other URI schemes, symlinks and hard links
  pointing elsewhere, directories, FIFOs, empty and oversized files, and SVG or
  other markup are dropped, and the panel falls back to its placeholder.
- The image URI is built in one place and percent-encoded per segment in UTF-8,
  so a name containing `%2F`, `#`, `?`, a space or a character outside Latin-1
  resolves to the file that was checked.
- Attachment thumbnails must start with a raster image in base64, and the viewer
  asks for image mode, so an attachment reaches Qt's image loader only when its
  contents really are an image.
- Opening an attachment is classified the way the desktop classifies it, by mime
  type and then by a content scan that skips a byte order mark and leading
  whitespace and ignores case. Programs, scripts, desktop entries, pages and
  shortcuts are refused, as are files that cannot be read, and saving refuses
  anything runnable.
- Phone text is plain text in the panel and in both windows, and escaped in
  notification popups. That escaping had broken on bash 5.2 and newer, where `&`
  in a `${value//pattern/replacement}` replacement means the matched text, so `<`
  and `>` came out as `<lt;` and `>gt;`.
- Every busctl call passes `--` before its arguments, and attachment names,
  notification ids and reply ids may not start with a dash. Without that, a phone
  could name an attachment `--address=tcp:host=...` and make the helper open a
  connection to a host it chose, and with enough arguments left busctl runs its
  own ssh bridge.
- Everything a phone can inflate is bounded: 100 notifications read and 25 shown
  per refresh, the newest 200 conversations and 200 messages, titles and previews
  at 1 KiB, text at 8 KiB, names at 256 characters, ids at 128, media metadata at
  256, contacts at 2000, and the watcher's capture at 16 MiB.
- `ring` and `clipboard` validate the device id like every other subcommand, and
  a D-Bus value that is not a number or a boolean falls back to a missing reading
  instead of emptying the panel.

Fixes:

- Attachment thumbnails are base64 wrapped across lines, so the first size and
  shape check rejected every real thumbnail.
- The panel's media section read the phone's player even when nothing was
  playing, filling the journal with "Cannot read property of null".
- The compose field in the Messages window had gained `textFormat`, a property
  Qt Quick Controls' TextField does not have, which stopped that window loading.
- The "Saved to" line rendered the phone's file name as rich text, so a name like
  `<img src="http://...">x.png` made the shell fetch that URL.
- A contact list longer than the cap aborted the helper through a broken pipe.
- Oversized app names, ids or media metadata no longer make jq fail on argument
  size and leave the panel claiming KDE Connect is not installed.
- The messages capture is bounded by size as well as by time, and a failed parse
  no longer leaves it behind.
- An unset `HOME` no longer aborts the helper, `--popups` or `--notify-apps` with
  no value is a usage error, and saving an attachment no longer writes through a
  dangling symlink in the Downloads folder.

Tests: `tests/qml.test.sh` walks QML element blocks, so a `Text` showing phone
data without `Text.PlainText`, an `Image` without the shared gate or a
`sourceSize` bound, an imperative `Image.source`, or `textFormat` on an element
that does not have it all fail the suite. The CLI suite pins each cap and guard,
after checking that the mutation it guards against fails it.

## 0.2.0 - 2026-09-15

- Notification sources setting: comma-separated app names or Android packages, defaulting to messaging and authenticator apps, matched anywhere in either; clear it to allow everything.
- Notification popups setting: keep matching notifications listed in the panel without desktop popups.
- Media controls setting: hide the phone's now-playing section entirely.
- Skip notifications the phone re-sends flagged silent after a reconnect, so old messages do not pop up again.
- Ask the phone for its thread list on every listing so messages sent on the phone appear without waiting for a push.
- Reap orphaned dbus-monitor watchers left behind by a killed watcher.
- Now-playing media controls in the panel: track, artist, album art, play/pause, previous/next, seek, and volume.

## 0.1.0 - 2026-08-23

- Initial release: pairing, device status, SMS/MMS conversations, notification popups with quick reply, clipboard and text sharing, ring, and MMS viewer.
