#!/usr/bin/env bash
# Actual Messages component in omabox, synthetic backends only.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir"/*.qml "$project_dir"/*.js "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
cat >"$work/bin/omalink-blueferry" <<'PY'
#!/usr/bin/python3
import json
import pathlib
import sys
import time
root = pathlib.Path(__file__).resolve().parent
assert len(sys.argv) == 1
request = json.load(sys.stdin)
operation, owner = request['operation'], request['expectedOwner']
assert request['endpoint'] == {'provider':'blueferry','instanceId':'local','deviceId':'local-history','accountId':None}
assert operation in ['threads','messages','contacts']
with (root / 'blueferry-calls').open('a') as stream:
    stream.write(operation + '\n')
if owner == ':1.11':
    print(json.dumps({'version':1,'ok':False,'operation':operation,'code':'backend_changed'}))
    sys.exit(1)
row = {'threadId':'group:雪:1','names':['Fixture group'],'addresses':['+15550000001'],
       'preview':'Exact <b>text</b> 😀','timestamp':1800000000000,'unread':True,'incoming':True,
       'isGroup':True,'attachmentCount':0,'attachments':[],'messagesTruncated':True}
items = [row]
if operation == 'messages':
    assert request['threadId'] == 'group:雪:1'
    marker = root / 'read-once'
    if marker.exists():
        time.sleep(0.7)
    marker.touch()
    items = [{'body':'  Exact <b>text</b> 😀  ','timestamp':1800000000000,'incoming':True,
              'sender':'Fixture sender','bodyTruncated':True,'attachmentCount':0,'attachments':[]}]
elif operation == 'contacts':
    items = [{'name':'Fixture contact','number':'+15550000001'}]
print(json.dumps({'version':1,'ok':True,'operation':operation,'endpoint':request['endpoint'],
 'backendOwner':owner,'apiVersion':2,'connection':'offline','storage':'ready','storagePolicy':'encrypted',
 'backendRelease':'0.6.0','map':False,'pbap':False,'ancs':False,'canReadHistory':True,
 'history':{'coverage':'observed-only','truncated':True},'items':items}))
PY
cat >"$work/bin/omalink" <<'PY'
#!/usr/bin/python3
import json
import pathlib
import sys
root = pathlib.Path(__file__).resolve().parent
command, device = sys.argv[1:]
assert device == 'android', 'BlueFerry route reached KDE helper'
assert command in ['contacts','conversations'], 'unexpected KDE mutation'
with (root / 'kde-calls').open('a') as stream:
    stream.write(command + '\n')
if command == 'contacts':
    print(json.dumps([{'name':'Android contact','number':'+15550000002'}]))
else:
    print(json.dumps([{'threadId':7,'names':['Android fixture'],'addresses':['+15550000002'],
                      'preview':'Android history','timestamp':1000,'incoming':True,'unread':False}]))
PY
chmod +x "$work/bin/omalink" "$work/bin/omalink-blueferry"
cp "$project_dir/tests/blueferry-runtime.qml" "$work/shell.qml"
if [[ -n ${OMALINK_PREVIEW:-} ]]; then
  qs -p "$work"
  exit
fi
timeout --kill-after=2s 25s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink BlueFerry runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:' "$work/log"; then exit 1; fi
python3 - "$work/bin" <<'PY'
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
assert sorted((root / 'kde-calls').read_text().splitlines()) == ['contacts','conversations']
reads = (root / 'blueferry-calls').read_text().splitlines()
assert set(reads) == {'threads','messages','contacts'} and len(reads) <= 11, reads
print('BlueFerry/KDE routing and read-only checks passed')
PY
