# Changelog

## 0.2.1 - 2026-09-17

- Security: treat phone-reported album art, notification icons, and attachment paths as untrusted input. They are loaded only when they resolve to a small raster image inside KDE Connect's cache or icon directory; remote URLs and other URI schemes, files outside those directories, symlinks that point elsewhere, oversized files, and SVG or other markup are dropped, and the panel decodes them at a bounded size. (Reported by HANCORE-linux in omarchy-plugin-marketplace#7127.)
- Security: render phone text as plain text in the panel, and escape it in notification popups. The popup escaping had silently stopped working on bash 5.2 and newer, which swallowed the ampersands.
- Security: cap the size of phone-supplied attachment thumbnails before they are decoded.
- Security: opening an attachment now goes through OmaLink's own helper, which refuses files the phone sent that would run (programs, scripts, desktop entries, detected by content as well as name) and detaches the viewer from the panel.
- A device line from kdeconnect-cli that cannot be a real device id is skipped, and a D-Bus value that is not a number or a boolean falls back to a missing reading instead of breaking the whole panel status.
- The notification watcher reaps only the dbus-monitor it orphaned, by pid and command check, instead of pattern-killing every matching process on the session bus.

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
