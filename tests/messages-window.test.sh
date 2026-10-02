#!/usr/bin/env bash
# Run in omabox. Real window lifecycle and compositor, synthetic phone only.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
fixture_pid=""
companion_pid=""
cleanup() {
  [[ -z $fixture_pid ]] || kill "$fixture_pid" 2>/dev/null || true
  [[ -z $companion_pid ]] || kill "$companion_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
OMALINK_PREVIEW_DIR="$work" bash "$project_dir/tests/messaging-preview.sh" >"$work/log" 2>&1 &
fixture_pid=$!
ipc() { qs -p "$work" ipc call omalink-review "$@"; }
await_state() {
  local condition="$1" state=""
  for ((attempt=0; attempt<150; attempt++)); do
    state="$(ipc session 2>/dev/null || true)"
    if jq -e "$condition" <<<"$state" >/dev/null 2>&1; then return; fi
    sleep 0.05
  done
  printf 'Window session did not reach %s: %s\n' "$condition" "$state" >&2
  cat "$work/log"
  return 1
}
await_client() {
  local condition="$1" clients=""
  for ((attempt=0; attempt<150; attempt++)); do
    clients="$(hyprctl -j clients)"
    if jq -e "$condition" <<<"$clients" >/dev/null; then return; fi
    sleep 0.05
  done
  printf 'Compositor did not reach %s: %s\n' "$condition" "$clients" >&2
  return 1
}
dispatch() { hyprctl dispatch "$1" >/dev/null; }
select_thread() {
  for ((attempt=0; attempt<150; attempt++)); do
    [[ $(ipc choose "$1") == true ]] && return
    sleep 0.05
  done
  echo "Could not select thread $1" >&2
  return 1
}
await_state '(.opened | not)'
# Let the preview's initial panel load before explicitly opening Messages.
for ((attempt=0; attempt<150; attempt++)); do
  if ipc navigation 2>/dev/null | jq -e '.panelOpen and .entries == 1' >/dev/null; then break; fi
  sleep 0.05
done
ipc thread
await_state '.opened and .visible and .threadId == 7 and .rows == 3'
await_client '[.[] | select(.title == "OmaLink Messages")] | length == 1'
# The same visible timestamp follows live clock changes without reopening.
[[ $(ipc timestamp) =~ ^[0-9]{2}:[0-9]{2}$ ]]
ipc clockFormat 'ddd d MMM h:mm AP'
[[ $(ipc timestamp) =~ ^[0-9]{1,2}:[0-9]{2}\ (AM|PM)$ ]]
ipc clockFormat 'h:mm ap'
[[ $(ipc timestamp) =~ ^[0-9]{1,2}:[0-9]{2}\ (am|pm)$ ]]
ipc clockFormat 'dddd HH:mm'
[[ $(ipc timestamp) =~ ^[0-9]{2}:[0-9]{2}$ ]]
address="$(hyprctl -j clients | jq -r '.[] | select(.title == "OmaLink Messages") | .address')"
[[ $address =~ ^0x[0-9a-fA-F]+$ ]]
selector="address:$address"
dispatch "hl.dsp.window.float({ action = 'off', window = '$selector' })"
await_client '[.[] | select(.title == "OmaLink Messages" and (.floating | not))] | length == 1'
! hyprctl -j layers | jq -e '.. | objects | select(.namespace? == "omalink-messages")' >/dev/null

ipc draft $'Keep this draft\nwhile using another app'
ipc pending
generation="$(ipc session | jq -r .generation)"
foot --app-id=omalink-window-test --title='OmaLink window test companion' bash --noprofile --norc >"$work/foot.log" 2>&1 &
companion_pid=$!
await_client '[.[] | select(.title == "OmaLink window test companion")] | length == 1'
dispatch "hl.dsp.focus({ window = 'title:^(OmaLink window test companion)$' })"
[[ $(hyprctl -j activewindow | jq -r .title) == 'OmaLink window test companion' ]]
await_state '.opened and .draft == "Keep this draft\nwhile using another app" and .operations == 1'
# Both tiled clients occupy distinct space; Messages is not a fullscreen layer.
hyprctl -j clients | jq -e '
  [.[] | select(.title == "OmaLink Messages" or .title == "OmaLink window test companion")] as $windows
  | ($windows | length) == 2 and all($windows[]; (.floating | not) and .fullscreen == 0)
  and $windows[0].at != $windows[1].at' >/dev/null

[[ $(ipc summon) == true ]]
await_state ".opened and .generation == $generation and .operations == 1 and .draft == \"Keep this draft\\nwhile using another app\""
for ((attempt=0; attempt<150; attempt++)); do
  [[ $(hyprctl -j activewindow | jq -r .title) == 'OmaLink Messages' ]] && break
  sleep 0.05
done
[[ $(hyprctl -j activewindow | jq -r .title) == 'OmaLink Messages' ]]
await_client '[.[] | select(.title == "OmaLink Messages")] | length == 1'

[[ $(ipc summonThread) == true ]]
await_state ".opened and .generation == $generation and .operations == 1 and .draft == \"Keep this draft\\nwhile using another app\""

dispatch "hl.dsp.window.float({ action = 'on', window = '$selector' })"
dispatch "hl.dsp.window.resize({ x = 500, y = 480, relative = false, window = '$selector' })"
await_client '[.[] | select(.title == "OmaLink Messages" and .floating and .size == [500,480])] | length == 1'
dispatch "hl.dsp.window.pin({ action = 'on', window = '$selector' })"
await_client '[.[] | select(.title == "OmaLink Messages" and .pinned)] | length == 1'
dispatch "hl.dsp.window.pin({ action = 'off', window = '$selector' })"
await_client '[.[] | select(.title == "OmaLink Messages" and (.pinned | not))] | length == 1'
# Hyprland may ignore minimize requests. Either way they must not clear state.
ipc minimize true
await_state '.opened and .draft == "Keep this draft\nwhile using another app"'
[[ $(ipc summon) == true ]]
await_state '.opened and .visible and (.minimized | not) and .operations == 1'
dispatch "hl.dsp.window.float({ action = 'off', window = '$selector' })"
# Keep the session through two actual 15-second fallback history refreshes.
for ((attempt=0; attempt<450; attempt++)); do
  [[ $(wc -l < "$work/bin/history-reads") -ge 3 ]] && break
  sleep 0.1
done
[[ $(wc -l < "$work/bin/history-reads") -ge 3 ]]
await_state ".opened and .generation == $generation and .operations == 1 and .caches == 1 and .draft == \"Keep this draft\\nwhile using another app\""

select_thread 8
await_state '.threadId == 8 and .draft == "" and .drafts == 1'
ipc draft 'Draft for Maya'
select_thread 7
await_state '.threadId == 7 and .draft == "Keep this draft\nwhile using another app" and .drafts == 2'
select_thread 8
await_state '.threadId == 8 and .draft == "Draft for Maya"'
for thread in 9 10 11 12 13 14; do
  select_thread "$thread"
  await_state ".threadId == $thread and .rows == 3"
  ipc draft "Draft $thread"
done
select_thread 15
await_state '.threadId == 15 and .drafts == 5 and .draft == ""'

# New-message recipients and text survive both inbox and thread navigation.
ipc composeDraft '+15550000002' 'Unsent new message'
ipc conversations
await_state '(.composing | not) and .savedCompose.body == "Unsent new message"'
select_thread 7
await_state '.threadId == 7'
ipc compose
await_state '.composing and .composeBody == "Unsent new message" and .recipient == "+15550000002"'
# Native close protects cached reply drafts and the current new-message draft.
dispatch "hl.dsp.window.close({ window = '$selector' })"
await_state '.opened and .visible and .closePrompt and .composeBody == "Unsent new message" and .drafts == 5'
ipc keepEditing
await_state '.opened and (.closePrompt | not) and .composeBody == "Unsent new message"'
ipc requestClose
await_state '.closePrompt'
ipc discardDrafts
await_state '(.opened | not) and (.visible | not) and .draft == "" and .rows == 0 and .operations == 0 and .caches == 0 and .drafts == 0 and .savedCompose == null and (.closePrompt | not)'
await_client '[.[] | select(.title == "OmaLink Messages")] | length == 0'
ipc thread
await_state '.opened and .visible and .threadId == 7 and .rows == 3'
await_client '[.[] | select(.title == "OmaLink Messages")] | length == 1'
# A clean session closes directly, without a draft warning.
dispatch "hl.dsp.window.close({ window = 'title:^(OmaLink Messages)$' })"
await_state '(.opened | not) and (.closePrompt | not) and (.hasDrafts | not)'
if rg -q 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:' "$work/log"; then
  cat "$work/log"
  exit 1
fi
echo 'Messages window tests passed: window controls, refresh, draft retention, native-close guard and cleanup'
