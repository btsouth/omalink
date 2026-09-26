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
export OMALINK_RULES_DIR="$work"
cat >"$work/bin/omalink" <<'EOF'
#!/bin/bash
exec python3 "$(dirname "$0")/fake.py" "$@"
EOF
cat >"$work/bin/fake.py" <<'PY_HELPER'
import json
import os
import sys
import time

work = os.environ["OMALINK_RULES_DIR"]
args = sys.argv[1:]
with open(os.path.join(work, "calls"), "a") as stream:
    stream.write(json.dumps(args) + "\n")
rules = {}
while args and args[0].startswith("--"):
    if args[0] == "--notify-rules":
        rules = json.loads(args[1])
    args = args[2:]
command = args[0] if args else ""

# Mirrors the helper's precedence for three fixed apps. Chat is outside the
# built-in source list, so only an exact allow lists it.
APPS = [("Chat", "com.example.chat", False), ("Messages", "com.google.android.apps.messaging", True),
        ("Signal", "", False)]

def device(device_id, name):
    policy = rules.get(device_id, {})
    notifications, apps, hidden = [], [], 0
    for index, (app, package, source) in enumerate(APPS):
        key = "pkg:" + package if package else "app:" + app
        state = policy.get(key, "")
        permitted = state == "allow" or (state != "mute" and source)
        apps.append({"key": key, "appName": app, "packageName": package, "count": 1,
                     "permitted": permitted, "sourceAllowed": source})
        if not permitted:
            hidden += 1
            continue
        notifications.append({"id": "n%d" % index, "appName": app, "packageName": package,
                              "title": name + " " + app, "text": "synthetic", "iconPath": "",
                              "dismissable": True, "replyId": "", "replyable": False, "isConversation": False})
    capabilities = {}
    for key, plugin in [("messaging", "kdeconnect_sms"), ("notifications", "kdeconnect_notifications")]:
        capabilities[key] = {"state": "available", "reason": "loaded", "supported": True, "loaded": True,
                             "enabled": True, "permission": "unknown", "plugin": plugin}
    return {"id": device_id, "name": name, "type": "phone", "paired": True, "reachable": True,
            "connectionState": "ready", "capabilities": capabilities, "notifications": notifications,
            "notificationSources": {"examined": 3, "scanTruncated": False, "permitted": len(notifications),
                                    "hidden": hidden, "listed": len(notifications), "unidentified": 0,
                                    "apps": apps}, "media": None}

if command == "status":
    if os.path.exists(os.path.join(work, "slow")):
        time.sleep(1.5)
    print(json.dumps({"schemaVersion": 1, "ok": True, "installed": True, "observedAt": 1,
                      "discoveryTruncated": False, "statusText": "Device status refreshed",
                      "backend": {"name": "kdeconnect", "version": "26.08.1",
                                  "versionSource": "kdeconnect-cli", "available": True},
                      "devices": [device("abc123", "Pixel"), device("def456", "Galaxy")]}))
elif command == "watch":
    time.sleep(30)
elif command in ("conversations", "conversations-cached", "seen"):
    print("{}" if command == "seen" else "[]")
elif command == "dismiss-all":
    pass
else:
    with open(os.path.join(work, "calls"), "a") as stream:
        stream.write("unexpected\n")
PY_HELPER
chmod +x "$work/bin/omalink"
cp "$project_dir/tests/notification-rules-runtime.qml" "$work/shell.qml"
if [[ -n ${OMALINK_PREVIEW:-} ]]; then qs -p "$work"; exit; fi
timeout --kill-after=2s 40s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink notification rules runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|FAIL:' "$work/log"; then exit 1; fi
if grep -q unexpected "$work/calls"; then exit 1; fi
# Status, the watcher's popup workers and Clear all received the same rules.
python3 - "$work/calls" <<'PY_CHECK'
import json
import sys
calls = [json.loads(line) for line in open(sys.argv[1])]
def rules(call):
    return json.loads(call[call.index("--notify-rules") + 1]) if "--notify-rules" in call else {}
chat = {"abc123": {"pkg:com.example.chat": "allow"}}
assert any(call[-1] == "watch" and rules(call) == chat for call in calls), "watcher never received the rule"
assert any(call[-1] == "status" and rules(call) == chat for call in calls), "status never received the rule"
clear = [call for call in calls if "dismiss-all" in call]
assert len(clear) == 1 and clear[0][-1] == "abc123" and rules(clear[0]) == {"abc123": {
    "pkg:com.google.android.apps.messaging": "mute", "app:Signal": "mute"}}, clear
assert not any("--notify-apps" in call for call in calls), "absent legacy sources were passed"
assert [call for call in calls if call[-1] == "status"][-1].count("--notify-rules") == 0, "reset rules still passed"
PY_CHECK
