#!/usr/bin/env bash
# Run in omabox. This loads the actual Messages component with a fake helper.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir"/*.qml "$project_dir/Model.js" "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
cat >"$work/bin/omalink" <<'EOF'
#!/bin/bash
sleep 0.3
case $1 in
  contacts) printf '[{"name":"%s","number":"+15550000001"}]\n' "$2" ;;
  conversations) printf '[{"threadId":7,"names":["%s"],"addresses":["+15550000001"],"preview":"fixture","timestamp":1000,"unread":false}]\n' "$2" ;;
  messages) printf '[{"body":"fixture message","timestamp":1000,"incoming":true,"attachments":[]}]\n' ;;
  attachment) printf '/tmp/should-not-open.png\n' ;;
  *) : ;;
esac
EOF
chmod +x "$work/bin/omalink"
cp "$project_dir/tests/runtime.qml" "$work/shell.qml"
timeout --kill-after=2s 20s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|FAIL:' "$work/log"; then exit 1; fi
