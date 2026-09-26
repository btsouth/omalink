#!/usr/bin/env bash
# Run only in omabox. Real PrivateRequest.qml with a synthetic stdin transport.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir/PrivateRequest.qml" "$project_dir/PrivateText.js" "$work/"
cp "$project_dir/tests/private-request-runtime.qml" "$work/shell.qml"
cat >"$work/bin/omalink" <<'PY'
#!/usr/bin/env python3
import json
import os
import pathlib
import sys
import time

root = pathlib.Path(__file__).resolve().parent
assert sys.argv[1:] == ['text-stdin']
request = json.load(sys.stdin)
assert request['body'] == '  private fixture\ntext 😀 café  '
# Check both this helper and its timeout parent, rather than only the QML
# command declaration. No private body should appear in either process argv.
for pid in (os.getpid(), os.getppid()):
    assert request['body'].encode() not in pathlib.Path(f'/proc/{pid}/cmdline').read_bytes()
with (root / 'requests.jsonl').open('a') as stream:
    stream.write(json.dumps(request) + '\n')
mode = request['deviceId']
if mode == 'rejected':
    print(json.dumps({'version':1, 'ok':False, 'state':'not-submitted', 'code':'offline'}))
    sys.exit(1)
if mode == 'malformed':
    print('not a result')
    sys.exit(0)
print(json.dumps({'version':1, 'ok':True, 'state':'accepted', 'code':'accepted'}), flush=True)
# EOF before exit exercises the sender's need to join both observations.
os.close(sys.stdout.fileno())
time.sleep(0.15)
sys.exit(1 if mode == 'wrongexit' else 0)
PY
chmod +x "$work/bin/omalink"
timeout --kill-after=2s 15s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink private request runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:' "$work/log"; then exit 1; fi
python3 - "$work/bin/requests.jsonl" <<'PY'
import json
import pathlib
import sys
rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert len(rows) == 4, 'Expected one dispatch per valid start, without retries'
assert [row['deviceId'] for row in rows] == ['accepted', 'rejected', 'malformed', 'wrongexit']
assert all(row['body'] == '  private fixture\ntext 😀 café  ' for row in rows)
print('private stdin, argv, destination, and single-dispatch checks passed')
PY
