#!/usr/bin/env bash
# Run only inside omabox. Leaves the fixture running for screenshots/input.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${OMALINK_PREVIEW_DIR:-$HOME/.local/state/omalink-preview}"
mkdir -p "$work/bin"
if [[ ${OMALINK_PREVIEW_RICH:-0} == 1 ]]; then touch "$work/bin/rich"; else rm -f "$work/bin/rich"; fi
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
if (root/'rich').exists():
 samples=[
  ('I found a quieter place for lunch. The little cafe on Oak Street has tables outside.',True,90000000),
  ('Perfect. Send me the address when you get a chance.',False,89940000),
  ('Morning! Are we still meeting at noon?',True,960000),
  ('The address is 24 Oak Street. I booked a table in the courtyard.',True,900000),
  ('Yes, see you there. I might be five minutes late.',False,780000),
  ('No rush. I will grab a coffee while I wait.',True,720000),
  ('One more thing: the entrance is around the corner, beside the bookshop.\n\nThere is a small blue sign by the door.',True,600000),
  ('Got it. Walking over now!',False,120000)]
 rows=[{'body':body,'timestamp':now-age,'incoming':incoming,'attachments':[]} for body,incoming,age in samples]
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
elif command in ['conversations','conversations-cached']:
 threads=[thread]
 if (root/'rich').exists():
  thread['names']=['Alex Morgan']
  thread['preview']='Got it. Walking over now!'
  names=['Maya Patel','Design studio','Dana Lee','Jules Rivera','Riley Chen','Zoe Bennett','Weekend plans']
  previews=['The photos turned out beautifully.','Sam: I pushed the final mockups.','Thanks again for your help yesterday.','Let me know when you are free.','See you at the trailhead at eight.','You: Sounds good to me.','Noor: Saturday works for everyone.']
  for i,(name,preview) in enumerate(zip(names,previews)):
   threads.append({'threadId':8+i,'names':[name],'addresses':['+1555000000'+str(i+2)],
    'preview':preview,'timestamp':now-(i+1)*3600000,'incoming':True,'unread':i==0})
 print(json.dumps(threads))
elif command=='messages':
 with (root/'history-reads').open('a') as stream: stream.write('read\n')
 time.sleep(0.2)
 if (root/'fail-history').exists(): sys.exit(1)
 print(json.dumps(rows))
elif command=='seen': print('{}')
elif command=='contacts':
 print(json.dumps([{'name':name,'number':'+1555000000'+str(i+1)} for i,name in enumerate(['Alex Morgan','Maya Patel','Dana Lee','Jules Rivera'])]) if (root/'rich').exists() else '[]')
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
