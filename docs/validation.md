# Validation

GitHub Actions runs the model and static checks on pull requests, pushes to
`main`, and manual dispatches. The job uses Ubuntu 24.04 and Node.js 24, has a
ten-minute timeout, and cancels superseded runs on the same branch. Its token has
read-only repository access; checkout does not persist credentials. Actions are
pinned to immutable commits.

## Checks run in CI

From the repository root:

```sh
for test in tests/*.test.js; do
  node "$test"
done
bash tests/qml.test.sh
python3 tests/mfa.test.py
shellcheck -S warning bin/omalink bin/omalink-files tests/*.sh
```

These checks need no phone, desktop, session bus, or repository secrets. The
notification parity test runs the helper's policy functions with Bash and jq,
both present on the runner, and compares them with the panel's JavaScript. The
QML check uses Bash and standard GNU text tools available on Ubuntu. It inspects
source for unsafe text/image bindings and known invalid properties; it does not
load QML or replace runtime validation.

## Isolated helper and desktop checks

Run the remaining checks through [omabox](https://github.com/btsouth/omabox) on an
Omarchy development machine. Read its setup instructions first. Run from this
repository so the plugin and test files are mounted in the isolated environment.
Do not run these suites directly against the user's desktop or session bus.

```sh
omabox run -- omarchy plugin validate .
omabox run -- bash tests/cli.test.sh
omabox run -- /usr/bin/python3 tests/audit.test.py
omabox run -- /usr/bin/python3 tests/capabilities.test.py
omabox run -- bash tests/files.test.sh
omabox run -- bash tests/runtime.test.sh
omabox run -- bash tests/selection-runtime.test.sh
omabox run -- bash tests/refresh-runtime.test.sh
omabox run -- bash tests/message-events-runtime.test.sh
omabox run -- bash tests/messaging-navigation.test.sh
omabox run -- bash tests/messages-window.test.sh
omabox run -- bash tests/mfa-runtime.test.sh
omabox run -- bash tests/send-runtime.test.sh
omabox run -- bash tests/provider-runtime.test.sh
omabox run -- bash tests/provider-request-runtime.test.sh
omabox run -- bash tests/blueferry-runtime.test.sh
omabox run -- bash tests/blueferry-service-runtime.test.sh
omabox run -- /usr/bin/python3 tests/blueferry.test.py
omabox run -- bash tests/file-share-runtime.test.sh
omabox run -- bash tests/private-request-runtime.test.sh
omabox run -- /usr/bin/python3 tests/text-transport.test.py
omabox run -- bash tests/notification-rules-runtime.test.sh
```

The direct D-Bus transport fixture needs the development-only `python-gobject`
package in addition to the runtime `python-dbus` dependency.

These suites use fake phone data and controlled transports. They cover helper
boundaries, capabilities, selected-phone routing, stale replies, message
outcomes, rejected provider routes, endpoint-scoped caches, file submission,
notification rule parity and stale-status suppression, QML loading, and
lifecycle behavior. Inspect the
affected UI in omabox as well, including keyboard navigation and both light and
dark themes. A successful CI job does not imply these checks ran.

The inbox navigation fixture covers acknowledgment after a successful thread
load, fresh incoming messages reusing a notification ID, already-open thread
routing and retained drafts. Rejected launches, failed or stale history,
ambiguous senders and notification dismissal failures keep the entry available.

The Messages window test exercises real Hyprland tiling, focus, floating,
resizing, pinning, per-conversation draft retention and close/reopen cleanup.
It keeps a draft and local send record through two scheduled history refreshes
with a synthetic phone. Minimize requests may be ignored by Hyprland; the test checks that requesting one does
not clear the session. Draft checks cover thread switches, the five-draft bound
and cleanup on close. New-message text and recipient survive navigation; native
close offers Keep editing or Discard and close when any unsent draft remains.
The close guard also covers mouse and keyboard controls. It does not establish an hours-long soak or phone delivery.

For a realistic visual fixture:

```sh
omabox run -d -- env OMALINK_PREVIEW_RICH=1 bash tests/messaging-preview.sh
```

This adds synthetic contacts, multi-day messages and longer paragraphs for
checking wide and narrow layouts. Inspect the conversation list, message history
and compose view in both light and dark themes.

## Physical acceptance

Release acceptance also requires an explicitly authorized check with supported
phones and backend versions. Record the OS and backend version, the operation,
and the observed result. Cover pairing/reconnection, selected-phone routing,
permissions, foreground/background behavior, messages with owned test
recipients, and file receipt. Verify accessibility with a screen reader.

Helper acceptance is not proof of message delivery or file receipt. Mocked
tests, a clean CI run, and a merged PR do not establish real-phone acceptance or
marketplace approval. The feature-specific gates are tracked in the
[implementation plan](implementation-plan.md).
