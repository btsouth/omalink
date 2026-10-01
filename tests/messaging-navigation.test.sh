#!/usr/bin/env bash
# Actual inbox delegate and Messages, synthetic phone only. Run in omabox.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$HOME/.local/state/omalink-preview"
mkdir -p "$work/bin"
rm -f "$work/bin/actions" "$work/bin/fail-history" "$work/bin/sent.json"
bash "$project_dir/tests/messaging-preview.sh" >"$work/navigation.log" 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
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
for ((attempt=0; attempt<100; attempt++)); do
  [[ -s "$work/bin/actions" ]] && break
  sleep 0.05
done
jq -se 'length == 1 and .[0] == ["mark-seen", "fixture", "7", .[0][3]]' "$work/bin/actions" >/dev/null

# A notification arriving before the unread history must also route by sender.
ipc inbox
await_state '.panelOpen and .entries == 1'
ipc fallback
await_state '.panelOpen and .notificationOnly'
[[ $(ipc activateRow) == true ]]
await_state '(.panelOpen | not) and .messagesOpen and .threadId == 7 and .rows == 3'
! rg -q '"dismiss"' "$work/bin/actions"

ipc inbox
await_state '.panelOpen and .entries == 1'
ipc clear
for ((attempt=0; attempt<100; attempt++)); do
  if rg -q '"dismiss"' "$work/bin/actions"; then break; fi
  sleep 0.05
done
jq -se 'map(select(.[0] == "dismiss")) == [["dismiss", "fixture", "notif.1"]]' "$work/bin/actions" >/dev/null
if rg -q 'ReferenceError|TypeError|SyntaxError|FAIL:' "$work/navigation.log"; then
  cat "$work/navigation.log"
  exit 1
fi
echo 'omalink messaging navigation tests passed'
