#!/usr/bin/env bash
# Run only in omabox. Real Messages.qml, fake helper, no phone or system bus.
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
if sys.argv[1:] == ["text-stdin"]:
    request = json.load(sys.stdin)
    command, device = request["operation"], request["deviceId"]
    args = [request.get("threadId", request.get("destination")), request["body"]]
    assert request["body"] not in " ".join(sys.argv)
else:
    command, device, *args = sys.argv[1:]
path = root / (device + ".json")
rows = json.loads(path.read_text()) if path.exists() else [
    {"body": "repeat", "timestamp": 1000, "incoming": False, "attachments": []}
]
if command in ("sms", "reply"):
    if device == "dependency":
        print(json.dumps({"version":1,"ok":False,"state":"not-submitted","code":"dependency"}))
        sys.exit(1)
    with (root / "sends.jsonl").open("a") as stream:
        stream.write(json.dumps({"device": device, "command": command, "target": args[0], "body": args[1]}) + "\n")
    if device == "slow":
        time.sleep(0.7)
    else:
        time.sleep(0.15)
    if device == "unknown":
        sys.exit(1)
    if device in ("confirm", "partial"):
        rows.append({"body": args[1], "timestamp": int(time.time() * 1000), "incoming": False, "attachments": []})
        path.write_text(json.dumps(rows))
    print(json.dumps({"version":1,"ok":True,"state":"accepted","code":"accepted"}))
elif command == "contacts":
    print(json.dumps([{"name": "Fixture", "number": "+15550000001"}]))
elif command == "conversations":
    print(json.dumps([{"threadId": 7, "names": ["Fixture"], "addresses": ["+15550000001"],
                       "preview": rows[-1]["body"], "timestamp": rows[-1]["timestamp"], "incoming": False, "unread": False}]))
elif command == "messages":
    print(json.dumps(rows))
    if device == "partial" and len(rows) > 1:
        sys.exit(1)
PY
chmod +x "$work/bin/omalink"
cp "$project_dir/tests/send-runtime.qml" "$work/shell.qml"
timeout --kill-after=2s 30s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink send runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:' "$work/log"; then exit 1; fi
python3 - "$work/bin/sends.jsonl" <<'PY'
import json
import pathlib
import sys
rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert len(rows) == 6, rows
assert [row["device"] for row in rows] == ["old", "confirm", "old", "unknown", "slow", "partial"], rows
assert rows[1]["body"] == "  exact\ntext 😀  ", rows
assert rows[2]["command"] == "sms", rows
assert rows[4]["target"] == "7", rows
print("send invocation and exact-content checks passed")
PY
