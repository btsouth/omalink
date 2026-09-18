# Changelog

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
