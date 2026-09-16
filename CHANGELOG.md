# Changelog

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
