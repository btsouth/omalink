# OmaLink

Your Android phone, native to Omarchy.

OmaLink is a themed Omarchy Shell plugin powered by KDE Connect. It puts the
phone controls and information that matter directly in the bar, without a web
account or cloud relay.

## Features

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
- Ring a misplaced phone
- Now-playing media controls for the phone: track, artist, and album art with
  play/pause, previous/next, seek, and volume
- Native colors and typography across Omarchy themes
- Memory-only message cache that is cleared when the message window closes

## Requirements

- Omarchy 4.0 or newer
- An Android phone with [KDE Connect](https://kdeconnect.kde.org/) installed
- `kdeconnect` and `jq` on the Omarchy computer

## Install

Install and enable OmaLink:

```sh
omarchy plugin add https://github.com/btsouth/omalink.git --enable
```

If KDE Connect is not installed yet:

```sh
omarchy pkg add kdeconnect
```

Open OmaLink from the bar, choose **Open pairing**, and approve the computer in
KDE Connect on your phone. Grant the Android permissions needed for messaging,
contacts, notifications, clipboard access, and device status.

Both devices must be able to reach one another, normally on the same local
network.

## Messaging notes

OmaLink uses KDE Connect's Android messaging interface. It can read SMS/MMS
conversation history, send SMS messages, and show that a message contains an
attachment. Sending attachments and RCS are not currently exposed by KDE
Connect.

Message history is requested from the phone when needed. OmaLink does not add
its own cloud service or persistent message database.

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

KDE Connect's own desktop popups for phone notifications cannot open anything
when clicked, so OmaLink silences that single popup event (by writing an
`[Event/notification]` override to `~/.config/kdeconnect.notifyrc`) and shows
its own popups instead. Clicking an OmaLink popup opens the OmaLink panel.
Popups for messages never include the message contents; the panel and the
Messages window show them.

By default OmaLink only reads notifications from Android messaging apps,
WhatsApp, Microsoft Authenticator, and Google Authenticator. Change
**Notification sources** in the widget settings to add or remove apps
(comma-separated names or Android packages matched anywhere in the app name or
package), or clear the field to allow every notification. **Notification
popups** can be set to Off to keep matching notifications listed in the panel
without desktop popups.

## Security

Everything OmaLink reads comes from the paired phone and is treated as
untrusted: any app on the phone can choose a notification title, an album art
URL, or an attachment.

- Images from the phone (album art, notification icons, attachment previews)
  are loaded only when they are local files under KDE Connect's own cache and
  icon directories, stay under a size limit, and are raster images (PNG, JPEG,
  GIF, BMP, WebP). Remote URLs and other URI schemes, paths outside those
  directories, symlinks that point elsewhere, oversized files, and SVG or other
  markup are all dropped, and the shell decodes them at a bounded size so a
  malicious image cannot exhaust memory.
- Text from the phone is rendered as plain text in the panel and escaped in
  desktop popups, so notification contents cannot inject markup or make the
  popup daemon fetch something remote.
- Attachments can be opened or saved only from KDE Connect's download
  directory. Opening one goes through OmaLink's own helper, which refuses files
  the phone sent that would run (programs, scripts, and desktop entries, judged
  by content as well as name) and hands everything else to your default
  application.
- OmaLink never builds a shell command out of phone data. Values passed to
  `kdeconnect-cli`, `busctl`, and the plugin's own helper are passed as single
  arguments and validated first.

OmaLink writes three things: one `[Event/notification]` line in
`~/.config/kdeconnect.notifyrc` (so its own popups replace KDE Connect's),
thread ids and timestamps in `~/.local/state/omalink/seen.json` for the unread
badge (never message contents), and the files you explicitly save to your
Downloads folder.

## Settings

Widget settings live in the bar widget configuration: **Refresh interval**,
**Notification sources**, **Notification popups**, and **Media controls**.
OmaLink stores no message data: the conversation cache lives in memory and is
dropped when the Messages window closes.

## Development

Run the checks:

```sh
omarchy plugin validate .
node tests/model.test.js
bash tests/cli.test.sh
```

The test suite uses mock phone data and does not send messages.

## Roadmap

- Guided setup and permission diagnostics
- File sending
- Event-driven message and media updates

## License

[MIT](LICENSE)
