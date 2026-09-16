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
