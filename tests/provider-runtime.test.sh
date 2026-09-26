#!/usr/bin/env bash
# Run only in omabox. Real Messages.qml, synthetic routes, no real backend.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir"/*.qml "$project_dir"/*.js "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
cat >"$work/bin/omalink" <<'PY'
#!/usr/bin/env python3
import json
import pathlib
import sys
import time

root = pathlib.Path(__file__).resolve().parent
command, device, *args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps([command, device]) + "\n")
if command == "contacts":
    print("[]")
elif command in ("conversations", "conversations-cached"):
    print(json.dumps([{"threadId":7,"names":[device],"addresses":["+15550000001"],
        "preview":device + " history","timestamp":1000,"incoming":True,"unread":False}]))
elif command == "messages":
    if device == "old":
        marker = root / "old-read"
        if marker.exists():
            time.sleep(0.7)
        marker.touch()
    print(json.dumps([{"body":device + " history","timestamp":1000,"incoming":True,"attachments":[]}]))
else:
    raise AssertionError("unexpected command")
PY
chmod +x "$work/bin/omalink"
cp "$project_dir/tests/provider-runtime.qml" "$work/shell.qml"
timeout --kill-after=2s 20s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink provider runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:' "$work/log"; then exit 1; fi
python3 - "$work/bin/calls.jsonl" <<'PY'
import collections
import json
import pathlib
import sys
calls = collections.Counter(tuple(json.loads(line)) for line in pathlib.Path(sys.argv[1]).read_text().splitlines())
assert calls == {("contacts","old"):2,("conversations","old"):2,("conversations-cached","old"):2,("messages","old"):2,
                 ("contacts","new"):1,("conversations","new"):1,("conversations-cached","new"):1,("messages","new"):1}, calls
print("provider routing invocation checks passed")
PY
