#!/usr/bin/env bash
# Actual Messages component and event watcher, synthetic phone only. Run in omabox.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir"/*.qml "$project_dir"/*.js "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
cat > "$work/bin/omalink" <<'PY'
#!/usr/bin/env python3
import json,pathlib,sys,time
root=pathlib.Path(__file__).parent
args=sys.argv[1:]
while args and args[0].startswith('--'): args=args[2:]
command=args[0]
rows=[{'body':'Earlier message '+str(i),'timestamp':1000*(i+1),'incoming':True,'attachments':[]} for i in range(80)]
old=rows[-1]
new={'body':'New incoming message','timestamp':81000,'incoming':True,'attachments':[]}
if command=='watch-messages':
    # An unrelated phone must not refresh this conversation.
    print('changed other',flush=True)
    time.sleep(1)
    (root/'new').touch()
    for _ in range(20): print('changed fixture',flush=True)
    time.sleep(10)
elif command in ('conversations','conversations-cached'):
    row=new if (root/'new').exists() else old
    print(json.dumps([{'threadId':7,'names':['Alex'],'addresses':['+15550000001'],
      'preview':row['body'],'timestamp':row['timestamp'],'incoming':True,'unread':True}]))
elif command=='messages':
    with (root/'reads').open('a') as f: f.write('read\n')
    print(json.dumps(rows+[new] if (root/'new').exists() else rows))
elif command=='contacts': print('[]')
PY
chmod +x "$work/bin/omalink"
cp "$project_dir/tests/message-events-runtime.qml" "$work/shell.qml"
timeout --kill-after=2s 8s qs -p "$work" > "$work/log" 2>&1 || { cat "$work/log"; exit 1; }
grep -q 'omalink message event runtime tests passed' "$work/log" || { cat "$work/log"; exit 1; }
if grep -Eq 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:' "$work/log"; then cat "$work/log"; exit 1; fi
[[ $(wc -l < "$work/bin/reads") == 2 ]] || { echo 'Event burst caused redundant history reads'; exit 1; }
echo 'message event runtime passed: new SMS before 4s, 20 events coalesced into one read'
