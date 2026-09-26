# Optional iPhone history through BlueFerry

OmaLink can display retained BlueFerry history after you explicitly enable the
integration. This experimental view does not send messages, mark them read,
change groups, delete history or synchronize contacts. It uses an already-running
local BlueFerry backend. Android KDE Connect integration remains independent.

Install and configure BlueFerry using its [upstream setup guide](https://github.com/erikwb/blueferry#pair-an-iphone).
Keep the iPhone unlocked during pairing. In its Bluetooth settings, enable
Show Message Notifications and Sync Contacts for the computer, and allow system
notifications if requested. For encrypted history, unlock the desktop wallet in
BlueFerry. Then open OmaLink, enable the BlueFerry option and refresh its status.
The Setup guide button opens documentation; it does not install or launch a
backend or change Bluetooth settings.

Review upstream setup effects before installation. On Arch, BlueFerry's backend
package can change Bluetooth service configuration and restart Bluetooth,
disconnecting other devices. BlueFerry can also manage a WirePlumber phone-audio
policy. Pairing, wallet access, backend startup and these configuration choices
belong to BlueFerry's setup flow. OmaLink does not perform them automatically.

## History and privacy

BlueFerry retains messages it observes while connected. This is not an iCloud
archive import or complete sent-message history. Attachments, reactions, typing
indicators and calls are not included. Threads, messages and text have display
limits; a short list does not prove that all available history was returned.
Group sender labels are display information, not confirmed participant lists.

The backend stores history and contacts according to its own settings. Its
default is encrypted local storage with a key in the desktop wallet. It also
supports unencrypted storage and no local retention. Changing that policy can
clear existing backend data. OmaLink keeps fetched content in memory and does
not change the policy. Locked, disabled or failed storage is shown separately
from a successful empty history result. An offline phone can still have readable
retained history.

BlueFerry does not report stable physical phone identity through this status
API. OmaLink labels the connection as a local backend history route, separately
from the selected KDE phone. It does not combine conversations by contact name
or address. Backend replacement invalidates old request owners and cached data.

The adapter uses read methods, but this is not a promise of zero upstream file
writes. BlueFerry can record verified setup state during status queries and
maintains its own storage and connection behavior while running. OmaLink does
not request sends, read acknowledgements, wallet unlock or setup mutations.

## Compatibility and troubleshooting

The reviewed source is BlueFerry
[`71749673`](https://github.com/erikwb/blueferry/tree/71749673b862c8f103d2353aeddd1fb54d185cff).
The adapter requires `GetStatus.api_version == 2`; the `Messages1` interface name
is not the API generation. Missing or incompatible backends are not activated or
restarted by OmaLink. Open BlueFerry separately to install, start or update it.

If history is locked, unlock the wallet through BlueFerry. If retention is off,
choose whether to retain future data there. If storage reports an error, inspect
BlueFerry's storage settings before changing anything. Do not interpret an empty
view as missing phone permissions or proof that the phone has no messages.

Private-bus fixtures and isolated desktop validation do not establish physical
phone support. Actual iPhone OS/controller versions, pairing, locked phone,
Bluetooth reconnection, incoming direct/group messages and wallet behavior still
require an explicitly authorized hardware test. Keep this experimental view
separate from claims of full iPhone messaging support.

BlueFerry is a separate GPL-2.0-or-later project. OmaLink talks to its documented
D-Bus interface and does not vendor upstream client code or assets.
