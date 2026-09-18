# Changelog

## 0.2.1 - 2026-09-17

- Security: treat phone-reported album art, notification icons, and attachment paths as untrusted input. They are loaded only when they resolve to a small raster image inside KDE Connect's cache or icon directory; remote URLs and other URI schemes, files outside those directories, symlinks that point elsewhere, oversized files, and SVG or other markup are dropped, and the panel decodes them at a bounded size. (Reported by HANCORE-linux in omarchy-plugin-marketplace#7127.)
- Security: render phone text as plain text in the panel, and escape it in notification popups. The popup escaping had silently broken on bash 5.2 and newer, where `&` in a `${value//pattern/replacement}` replacement means the matched text: `<` and `>` came out as `<lt;` and `>gt;` instead of entities. `&` alone happened to still work, so the tests now pin all three.
- Security: cap the size of phone-supplied attachment thumbnails before they are decoded.
- Security: opening an attachment now goes through OmaLink's own helper, which refuses files the phone sent that would run (programs, scripts, desktop entries, detected by content as well as name) and detaches the viewer from the panel.
- A device line from kdeconnect-cli that cannot be a real device id is skipped, and a D-Bus value that is not a number or a boolean falls back to a missing reading instead of breaking the whole panel status.
- The notification watcher reaps only the dbus-monitor it orphaned, by pid and command check, instead of pattern-killing every matching process on the session bus.
- Security: a phone that posts hundreds of notifications can no longer stall the bar. Each refresh reads at most 100 notifications and shows at most 25, since every other field needed costs a D-Bus read.
- Security: the conversation list and each message thread are capped at the newest 200 entries, so the phone cannot decide how much data the shell has to hold and filter.
- Security: files the phone made runnable are refused by Save to Downloads as well as Open, an attachment whose contents cannot be read is refused rather than handed to the desktop, and opening a web page or shortcut the phone sent (HTML, SVG, .url) is refused because the browser would fetch whatever it contains. Saving a page is still allowed.
- Fix: attachment thumbnails are base64 wrapped across lines, so the new size and shape check rejected every real thumbnail. Whitespace is stripped before the checks now.
- Fix: the panel's media section read the phone's player even when nothing was playing, which filled the journal with "Cannot read property of null" errors.
- Security: every busctl call now passes `--` before its arguments, and attachment names, notification ids and reply ids may not start with a dash. Without that, a phone could name an attachment `--address=tcp:host=...` and make the helper open a connection to a host it chose, and with enough remaining arguments busctl runs its own ssh bridge (both proved against the real busctl).
- Security: attachment thumbnails must start with a raster image in base64 (PNG, JPEG, GIF, WebP or BMP). That field was the one image the phone sends that skipped the raster gate, so SVG or other markup could reach the image loader through it.
- Security: the QML layer builds the `file://` URI and percent-encodes `%`, `#`, `?` and whitespace. Album art and notification icons are handed over as plain paths now, so a name containing `%2F` can no longer decode to a path outside the one the helper checked.
- Fix: album art is capped at 5 MiB, which is what KDE Connect itself accepts, instead of 4 MiB.
- Fix: the compose field in the Messages window had gained `textFormat`, a property Qt Quick Controls' TextField does not have, which stopped that window from loading. `tests/qml.test.sh` now checks that property additions sit on elements that have them, and that every `Image.source` fed by phone data goes through the shared gate.

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
