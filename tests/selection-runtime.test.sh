#!/usr/bin/env bash
# Actual Panel/Service components, private omabox session, synthetic phones only.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir"/*.qml "$project_dir/Model.js" "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
export OMALINK_SELECTION_LOG="$work/actions"
cat >"$work/bin/omalink" <<'EOF'
#!/bin/bash
while [[ $1 == --* ]]; do shift 2; done
case $1 in
  status) printf '{"ok":true,"installed":true,"devices":[{"id":"abc123","name":"Pixel"},{"id":"def456","name":"Galaxy"}]}\n' ;;
  watch) sleep 30 ;;
  conversations) sleep 0.3; printf '[{"threadId":7,"names":["%s"],"addresses":["+15550000001"],"preview":"fixture","timestamp":1000,"unread":true}]\n' "$2" ;;
  seen) sleep 0.3; printf '{}\n' ;;
  ring) printf '%s\n' "$2" >>"$OMALINK_SELECTION_LOG"; sleep 0.3 ;;
  *) : ;;
esac
EOF
chmod +x "$work/bin/omalink"
cp "$project_dir/tests/selection-runtime.qml" "$work/shell.qml"
timeout --kill-after=2s 20s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink selection runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|FAIL:' "$work/log"; then exit 1; fi
[[ $(cat "$work/actions") == def456 ]]
