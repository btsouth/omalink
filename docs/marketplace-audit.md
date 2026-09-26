# Marketplace audit, 2026-09-25

Local candidate: `fix/marketplace-audit`, version 0.2.3, based on
`93a9a6c30756357b04f838a0521117891de46dff`. No commit, push, installation, or
marketplace issue edit was performed for this audit.

## Submission status

[Submission #7127](https://github.com/omacom/omarchy-plugin-marketplace/issues/7127)
still has `needs-fixes` and `security-review-required`. Its validation and
review evidence describe `a47e87ab2457072aca3368dba30bfdf5013ed5cd`, not this
working tree. The existing 0.2.2 commit had not been revalidated there.

The first reviewer finding concerned remote or unbounded album art. Existing
local-file, raster, byte-limit, and decode-size guards were retained and tested.
The latest finding concerned captures growing while D-Bus requests remained
pending. The 0.2.2 polling watchdog still permitted overshoot and did not stop
the request at the capture ceiling. This candidate replaces that mechanism.

## Findings fixed

| Area | Problem and correction |
| --- | --- |
| Capture bounds | A FIFO reader now writes at most 16 MiB. Overflow stops and reaps the monitor and pending request, including their process groups. |
| Cancellation | EXIT and signal cleanup removes temporary captures and stops their producers when the helper is cancelled. Attachment requests retain a 30-second timeout. |
| Device isolation | Message and attachment signals must match the requested device path. Unread timestamps now use separate files per device and cannot move backwards. |
| Popup floods | Notification bursts previously spawned unlimited helpers. At most four now run; their lifetimes are bounded. |
| Watcher state | Removed shared `/tmp` fallback and stale-PID killing. Watchers require private runtime storage and clean up their own children. |
| Configuration consent | Removed automatic writes to `kdeconnect.notifyrc`. Duplicate-popup configuration is now an explicit user choice. |
| Notification privacy | Titles and bodies, including codes from non-conversation authenticator notifications, no longer reach popups. |
| Large inputs | Device names, addresses, identifiers, contact files, and clear-all loops are bounded. Large contacts and notification arrays no longer exceed the OS single-argument limit. Aggregate status/list/clear operations have a 45-second deadline. |
| Attachments | Viewer images now use the 8 MiB image cap. Executable files and unavailable MIME classification are refused. Save names are reserved without clobbering existing files or symlinks. |
| CLI options | Global flags are parsed only before the command, preserving literal message text such as `--popups`. Seek and volume numeric inputs are bounded and parsed as decimal. |
| Media | Fixed the doubled `mprisremote` seek path and unqualified QML media references that left controls blank. |
| Notification filtering | Package-name matches survive the second filtering pass in QML. Settings changes restart the watcher. |
| Message lifetime | Closing or switching devices invalidates pending results, cancels reads, and clears drafts and caches. Streaming parsers avoid retaining completed raw message responses. Immediate reopen retries cancelled reads. |
| Message state | Thread cache is limited to five entries. Direct SMS no longer updates an unrelated group conversation containing that number. Attachment cache keys cannot collide with object prototype names. |
| Documentation | Added removal instructions, complete dependencies, local-write disclosure, legacy notification/state migration notes, and explicit validation limits. |

## Validation

Passed on the local candidate:

- Bash syntax, ShellCheck warnings, Node model tests, static QML checks, and
  `git diff --check`.
- `omarchy plugin validate .` inside omabox.
- Existing CLI suite covering paths, image formats and sizes, argument rejection,
  notification filtering, contacts, message bounds, and attachment actions.
- New adversarial tests: pending request floods stop with exactly 16 MiB written;
  producer PIDs disappear; cancellation removes temporary files; cross-device
  signals are ignored; large contact/notification responses survive; literal
  option-like messages remain unchanged; popup bursts stop at four workers.
- Real Quickshell component tests with a fake helper: close during load, thread
  load, five-thread cache, phone switch, late attachment, and immediate reopen.
- Isolated shell inspection with synthetic phones: dark theme at 1920x1080 and
  light theme at 1366x768, panel/media rendering and Messages layout. Clicking
  play/pause and seek produced the expected mocked D-Bus calls. No Omalink QML
  reference or type errors remained in the shell log.

The current marketplace scanner from
`omacom/omarchy-plugin-marketplace@dbf1e37a19ca0ef08d37bc9ae9d8f8260f41f369`
was run locally over its defined source scope. It returned no findings and one
`package-manager` capability for the README's manual
`omarchy pkg add kdeconnect jq` instruction. This requires maintainer review;
the plugin itself does not install packages. This local scan is not a new
marketplace validation or an approval.

## Remaining acceptance and submission work

Real-phone pairing, SMS delivery, incoming notifications, attachment transfer,
media seeking on Android, and reconnect behavior were not exercised. The user's
installed plugin and real desktop were not changed. These checks need a paired
phone and an explicitly authorized real-session check.

After the local candidate is approved, commit and push it, update the existing
submission with the exact SHA and corrected maintainer notes, and verify the
new marketplace validation. Only marketplace maintainers can approve listing.
No audit can guarantee that a later review will find nothing further.
