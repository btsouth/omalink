#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$project_dir/MfaPopup.qml" "$work/"
cp "$project_dir/tests/mfa-runtime.qml" "$work/shell.qml"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
if [[ ${OMALINK_MFA_PREVIEW:-} == 1 ]]; then
  exec qs -p "$work"
fi
timeout --kill-after=2s 8s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink MFA copy runtime passed' "$work/log"
[[ "$(wl-paste --type text/plain --no-newline)" == 004219 ]]
wl-paste --list-types | grep -qx 'x-kde-passwordManagerHint'
if [[ -f "$HOME/.local/state/omarchy/clipboard-history.json" ]] \
    && grep -q 004219 "$HOME/.local/state/omarchy/clipboard-history.json"; then
  echo 'MFA code reached clipboard history' >&2
  exit 1
fi
if grep -Eq 'ReferenceError|TypeError|SyntaxError|FAIL:' "$work/log"; then exit 1; fi
