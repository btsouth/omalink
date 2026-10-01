#!/usr/bin/env bash
# Run only inside omabox. Leaves the fixture running for screenshots/input.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$HOME/.local/state/omalink-preview"
mkdir -p "$work/bin"
cp "$project_dir"/*.qml "$project_dir"/*.js "$work/"
ln -sfn /usr/share/omarchy/shell/Commons "$work/Commons"
ln -sfn /usr/share/omarchy/shell/Ui "$work/Ui"
cp "$project_dir/tests/messaging-preview.qml" "$work/shell.qml"
cat > "$work/bin/omalink" <<'PY'
#!/usr/bin/env python3
import json,pathlib,sys,time
root=pathlib.Path(__file__).parent
args=sys.argv[1:]
while args and args[0].startswith('--'): args=args[2:]
command=args[0]
if command in ['mark-seen','dismiss']:
 with (root/'actions').open('a') as stream: stream.write(json.dumps(args)+'\n')
now=int(time.time()*1000)
rows=[{'body':'Are we still meeting for lunch?','timestamp':now-300000,'incoming':True,'attachments':[]},
      {'body':'Yes! I can be there at noon.','timestamp':now-240000,'incoming':False,'attachments':[]},
      {'body':'Perfect, see you there.','timestamp':now-60000,'incoming':True,'attachments':[]}]
if (root/'sent.json').exists(): rows+=json.loads((root/'sent.json').read_text())
thread={'threadId':7,'names':['Alex'],'addresses':['+15550000001'],
 'preview':rows[-1]['body'],'timestamp':rows[-1]['timestamp'],'incoming':rows[-1]['incoming'],'unread':True}
notif={'id':'notif.1','appName':'Messages','packageName':'com.google.android.apps.messaging','title':'Alex',
 'text':'Perfect, see you there.','iconPath':'','dismissable':True,'replyId':'','replyable':False,'isConversation':True}
if command=='status':
 capabilities={key:{'state':'available','reason':'loaded','supported':True,'loaded':True,'enabled':True,'permission':'unknown','plugin':{'messaging':'kdeconnect_sms','notifications':'kdeconnect_notifications','sharing':'kdeconnect_share','ring':'kdeconnect_findmyphone'}[key]}
  for key in ['messaging','notifications','sharing','ring']}
 device={'id':'fixture','name':'Test phone','type':'phone','paired':True,'reachable':True,'connectionState':'ready',
  'capabilities':capabilities,'battery':{'charge':72,'charging':False},'notifications':[notif],
  'notificationSources':{'examined':1,'scanTruncated':False,'permitted':1,'hidden':0,'listed':1,'unidentified':0,
    'apps':[{'key':'pkg:com.google.android.apps.messaging','appName':'Messages','packageName':notif['packageName'],
       'count':1,'permitted':True,'sourceAllowed':True}]},'media':None}
 print(json.dumps({'schemaVersion':1,'ok':True,'installed':True,'observedAt':now,'discoveryTruncated':False,
   'backend':{'name':'kdeconnect','available':True,'version':'26.08.1','versionSource':'kdeconnect-cli'},'devices':[device]}))
elif command in ['conversations','conversations-cached']: print(json.dumps([thread]))
elif command=='messages':
 time.sleep(0.2)
 if (root/'fail-history').exists(): sys.exit(1)
 print(json.dumps(rows))
elif command=='seen': print('{}')
elif command=='contacts': print('[]')
elif command in ['watch','watch-messages']: time.sleep(3600)
elif command=='text-stdin':
 request=json.load(sys.stdin)
 sent=json.loads((root/'sent.json').read_text()) if (root/'sent.json').exists() else []
 sent.append({'body':request['body'],'timestamp':now,'incoming':False,'attachments':[]})
 (root/'sent.json').write_text(json.dumps(sent))
 print(json.dumps({'version':1,'ok':True,'state':'accepted','code':'accepted'}))
PY
chmod +x "$work/bin/omalink"
exec qs -p "$work"
