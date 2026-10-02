#!/usr/bin/env bash
# Actual inbox delegate and Messages, synthetic phone only. Run in omabox.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$HOME/.local/state/omalink-preview"
mkdir -p "$work/bin"
rm -f "$work/bin/actions" "$work/bin/fail-history" "$work/bin/sent.json" "$work/bin/seen.json" "$work/bin/dismissed" "$work/bin/stale-history" "$work/bin/ambiguous" "$work/bin/fail-dismiss"
touch "$work/bin/persist-read-state"
date +%s%3N > "$work/bin/epoch"
bash "$project_dir/tests/messaging-preview.sh" >"$work/navigation.log" 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; rm -f "$work/bin/persist-read-state"' EXIT
ipc() { qs -p "$work" ipc call omalink-review "$@"; }
await_state() {
  local condition="$1" state=""
  for ((attempt=0; attempt<100; attempt++)); do
    state="$(ipc navigation 2>/dev/null || true)"
    if jq -e "$condition" <<<"$state" >/dev/null 2>&1; then return; fi
    sleep 0.05
  done
  printf 'Navigation did not reach %s: %s\n' "$condition" "$state" >&2
  cat "$work/navigation.log"
  return 1
}
await_state '.panelOpen and .entries == 1'
ipc reject true
[[ $(ipc activateRow) == true ]]
await_state '.panelOpen and (.messagesOpen | not) and .entries == 1'
[[ ! -s "$work/bin/actions" ]]

ipc reject false
touch "$work/bin/fail-history"
[[ $(ipc activateRow) == true ]]
await_state '.messagesOpen and .threadId == 7 and .error == "Could not load conversation"'
[[ ! -s "$work/bin/actions" ]]

rm "$work/bin/fail-history"
ipc inbox
await_state '.panelOpen and .entries == 1'
[[ $(ipc activateRow) == true ]]
await_state '(.panelOpen | not) and .messagesOpen and .threadId == 7 and .rows == 3'
await_actions() {
  for ((attempt=0; attempt<100; attempt++)); do
    if [[ -f "$work/bin/actions" ]] && jq -se "$1" "$work/bin/actions" >/dev/null 2>&1; then return; fi
    sleep 0.05
  done
  cat "$work/bin/actions" >&2
  return 1
}
await_actions 'length == 2 and .[0][0:3] == ["mark-seen", "fixture", "7"] and .[1] == ["dismiss", "fixture", "notif.1"]'
await_state '(.panelOpen | not) and .entries == 0'
ipc peekInbox
await_state '.panelOpen and .entries == 0 and .messagesOpen'

new_message() {
  python3 - "$work/bin" <<'PYTHON'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
(root/'epoch').write_text(str(int((root/'epoch').read_text())+600000))
(root/'dismissed').unlink(missing_ok=True)
(root/'actions').unlink(missing_ok=True)
PYTHON
}

# A new SMS, even reusing the notification ID, returns to the dropdown.
# Clicking it refreshes the already-open thread and preserves the reply draft.
new_message
ipc draft 'Keep my reply draft'
ipc peekInbox
await_state '.panelOpen and .entries == 1 and .threadId == 7'
[[ $(ipc activateRow) == true ]]
await_state '(.panelOpen | not) and .threadId == 7 and .rows == 3'
await_actions 'length == 2 and .[1] == ["dismiss", "fixture", "notif.1"]'
ipc session | jq -e '.draft == "Keep my reply draft"' >/dev/null
ipc peekInbox
await_state '.entries == 0'

# An older cached history must not acknowledge a newer clicked SMS.
new_message
touch "$work/bin/stale-history"
ipc peekInbox
await_state '.entries == 1'
[[ $(ipc activateRow) == true ]]
await_state '(.panelOpen | not) and .threadId == 7 and .rows == 3 and (.readingHistory | not)'
[[ ! -s "$work/bin/actions" ]]
rm "$work/bin/stale-history"
ipc refresh
await_actions 'length == 2 and .[1][0] == "dismiss"'
ipc peekInbox
await_state '.entries == 0'

# A row must select its thread when a different thread is already open.
new_message
[[ $(ipc choose 8) == true ]]
ipc draft 'Draft in the other thread'
ipc peekInbox
await_state '.entries == 1 and .threadId == 8'
[[ $(ipc activateRow) == true ]]
await_state '.threadId == 7 and (.panelOpen | not)'
await_actions 'any(.[]; . == ["dismiss", "fixture", "notif.1"])'
[[ $(ipc choose 8) == true ]]
ipc session | jq -e '.draft == "Draft in the other thread"' >/dev/null

# A notification arriving before unread history also routes by its sender.
new_message
# Seen history leaves just the phone notification in the dropdown.
python3 - "$work/bin" <<'PYTHON'
import pathlib,json,sys
root=pathlib.Path(sys.argv[1])
(root/'seen.json').write_text(json.dumps({'7':int((root/'epoch').read_text())}))
PYTHON
ipc inbox
await_state '.panelOpen and .entries == 1 and .notificationOnly'
[[ $(ipc activateRow) == true ]]
await_state '(.panelOpen | not) and .threadId == 7 and .rows == 3'
await_actions 'length == 2 and .[1] == ["dismiss", "fixture", "notif.1"]'
ipc peekInbox
await_state '.entries == 0'

# Ambiguous sender names stay available, with no read or dismiss action.
new_message
touch "$work/bin/ambiguous"
ipc inbox
await_state '.entries == 1 and .notificationOnly'
[[ $(ipc activateRow) == true ]]
await_state '.messagesOpen and .threadId == null and (.panelOpen | not) and (.loading | not)'
[[ ! -s "$work/bin/actions" ]]
ipc peekInbox
await_state '.entries == 1'
rm "$work/bin/ambiguous"

# If the phone refuses dismissal, the row remains available for Clear.
touch "$work/bin/fail-dismiss"
ipc inbox
await_state '.entries == 1'
[[ $(ipc activateRow) == true ]]
await_state '.threadId == 7 and .rows == 3'
await_actions 'any(.[]; .[0] == "dismiss")'
ipc peekInbox
await_state '.entries == 1 and .notificationOnly'
rm "$work/bin/fail-dismiss"
ipc clear
await_actions 'map(select(.[0] == "dismiss")) | length == 2'
ipc peekInbox
await_state '.entries == 0'

if rg -q 'ReferenceError|TypeError|SyntaxError|FAIL:' "$work/navigation.log"; then
  cat "$work/navigation.log"
  exit 1
fi
echo 'omalink messaging navigation tests passed'
