#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir"/BlueFerry*.qml "$project_dir"/BlueFerryModel.js "$project_dir"/ProviderRequest.qml "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
cat >"$work/bin/omalink-blueferry" <<'PY'
#!/usr/bin/env python3
import json,pathlib,sys,time
root=pathlib.Path(__file__).resolve().parent
request=json.load(sys.stdin)
assert request=={"version":1,"operation":"status"}
count=root/"calls"
n=int(count.read_text())+1 if count.exists() else 1
count.write_text(str(n))
if n==4:time.sleep(0.8)
print(json.dumps({"version":1,"ok":True,"operation":"status","endpoint":{"provider":"blueferry","instanceId":"local","deviceId":"local-history","accountId":None},"backendOwner":":1.10" if n==1 else ":1.11","apiVersion":2,"connection":"ready" if n==1 else "offline","storage":"locked" if n==2 else "ready","storagePolicy":"encrypted","backendRelease":"1.2.3","map":n==1,"pbap":n==1,"ancs":False,"canReadHistory":n!=2,"history":{"coverage":"observed-only","truncated":True},"items":[]}))
PY
chmod +x "$work/bin/omalink-blueferry"
cp "$project_dir/tests/blueferry-service-runtime.qml" "$work/shell.qml"
if [[ ${OMALINK_PREVIEW:-} == card ]]; then qs -p "$work"; exit; fi
timeout --kill-after=2s 20s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log";exit 1; }
cat "$work/log"
grep -q 'BlueFerry service runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:' "$work/log";then exit 1;fi
[[ $(cat "$work/bin/calls") == 4 ]]
