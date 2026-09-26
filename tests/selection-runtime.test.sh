#!/usr/bin/env bash
# Actual Panel/Service components, private omabox session, synthetic phones only.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir"/*.qml "$project_dir"/*.js "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
export OMALINK_SELECTION_LOG="$work/actions"
cat >"$work/bin/omalink" <<'EOF'
#!/bin/bash
while [[ $1 == --* ]]; do shift 2; done
case $1 in
  text-stdin) exec python3 "$(dirname "$0")/private.py" ;;
  status) printf '{"schemaVersion":1,"ok":true,"installed":true,"observedAt":1,"discoveryTruncated":false,"backend":{"name":"kdeconnect","version":"26.08.1","versionSource":"kdeconnect-cli","available":true},"devices":[{"id":"abc123","name":"Pixel","paired":true,"reachable":true},{"id":"def456","name":"Galaxy","paired":true,"reachable":true}]}\n' ;;
  diagnostics) printf '{"schemaVersion":1,"ok":true,"installed":true,"observedAt":1,"discoveryTruncated":false,"backend":{"name":"kdeconnect","version":"26.08.1","versionSource":"kdeconnect-cli","available":true},"devices":[{"label":"device-1","id":"PRIVATE","name":"PRIVATE","paired":true,"reachable":true,"type":"phone","capabilities":{}}]}\n' ;;
  watch) sleep 30 ;;
  conversations|conversations-cached) sleep 0.3; printf '[{"threadId":7,"names":["%s"],"addresses":["+15550000001"],"preview":"fixture","timestamp":1000,"unread":true}]\n' "$2" ;;
  seen) sleep 0.3; printf '{}\n' ;;
  ring) printf '%s\n' "$2" >>"$OMALINK_SELECTION_LOG"; sleep 0.3 ;;
  *) printf "unexpected:%s\n" "$1" >>"$OMALINK_SELECTION_LOG" ;;
esac
EOF
cat >"$work/bin/private.py" <<'PY_HELPER'
import json
import os
import sys
import time
request = json.load(sys.stdin)
assert sys.argv[1:] == []
assert request["deviceId"] == "abc123"
assert request["body"] == "  exact 😀  "
with open(os.environ["OMALINK_SELECTION_LOG"], "a") as stream:
    stream.write(request["operation"] + "\n")
time.sleep(0.15)
print(json.dumps({"version":1,"ok":True,"state":"accepted","code":"accepted"}))
PY_HELPER
chmod +x "$work/bin/omalink"
cp "$project_dir/tests/selection-runtime.qml" "$work/shell.qml"
if [[ -n ${OMALINK_PREVIEW:-} ]]; then qs -p "$work"; exit; fi
timeout --kill-after=2s 20s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink selection runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|FAIL:' "$work/log"; then exit 1; fi
[[ $(cat "$work/actions") == $'def456\nshare\nnotify-reply' ]]
