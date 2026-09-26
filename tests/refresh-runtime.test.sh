#!/usr/bin/env bash
# Run in omabox. This loads the actual Service component with a fake helper.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir"/*.qml "$project_dir"/*.js "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
cat >"$work/bin/omalink" <<'SH'
#!/bin/bash
while [[ $1 == --* ]]; do shift 2; done
case $1 in
  status)
    sleep 0.6
    printf '{"schemaVersion":1,"ok":true,"installed":true,"observedAt":1,"discoveryTruncated":false,"statusText":"ok","backend":{"name":"kdeconnect","version":"26.08.1","versionSource":"kdeconnect-cli","available":true},"devices":[]}\n'
    ;;
  watch)
    sleep 0.2
    echo "posted abc123 notif.1"
    sleep 30
    ;;
  *) : ;;
esac
SH
chmod +x "$work/bin/omalink"
cp "$project_dir/tests/refresh-runtime.qml" "$work/shell.qml"
timeout --kill-after=2s 20s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink refresh runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|FAIL:' "$work/log"; then exit 1; fi
