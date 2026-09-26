#!/usr/bin/env bash
# Run only in omabox. Generic provider transport with synthetic helper data.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$project_dir/ProviderRequest.qml" "$work/"
cp "$project_dir/tests/provider-request-runtime.qml" "$work/shell.qml"
cat >"$work/bin/provider" <<'PY'
#!/usr/bin/env python3
import json
import os
import pathlib
import signal
import sys
import time

root = pathlib.Path(__file__).resolve().parent
assert len(sys.argv) == 1
request = json.load(sys.stdin)
assert request['body'] == '  private provider fixture\ntext 😀 café  '
for pid in (os.getpid(), os.getppid()):
    assert request['body'].encode() not in pathlib.Path(f'/proc/{pid}/cmdline').read_bytes()
with (root / 'requests.jsonl').open('a') as stream:
    stream.write(json.dumps({'mode':request['operation'], 'pid':os.getpid()}) + '\n')
mode = request['operation']
if mode == 'wrongexit':
    print('PRIVATE_PROVIDER_STDERR_SENTINEL', file=sys.stderr)
if mode == 'timeout':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(60)
if mode == 'cancel':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    print('{"mode":"cancel",', end='', flush=True)
    time.sleep(0.5)
    try:
        print('"late":true}', flush=True)
    except BrokenPipeError:
        os._exit(0)
    sys.exit(0)
if mode == 'malformed':
    print('not JSON')
    sys.exit(0)
if mode == 'array':
    print('[]')
    sys.exit(0)
if mode in ('large', 'unicodeLarge'):
    try:
        print(json.dumps({'data':('x' * 2200000 if mode == 'large' else 'é' * 1100000)}, ensure_ascii=False), flush=True)
    except BrokenPipeError:
        os._exit(0)
    sys.exit(0)
print(json.dumps({'mode':mode, 'body':request['body']}), flush=True)
os.close(sys.stdout.fileno())
# EOF precedes exit. A success-shaped object must not hide a nonzero exit.
time.sleep(0.15)
sys.exit(1 if mode == 'rejected' else 2 if mode == 'wrongexit' else 0)
PY
chmod +x "$work/bin/provider"
timeout --kill-after=2s 45s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink provider request runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:|PRIVATE_PROVIDER_STDERR_SENTINEL' "$work/log"; then exit 1; fi
python3 - "$work/bin/requests.jsonl" <<'PY'
import json
import pathlib
import sys
rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert [row['mode'] for row in rows] == ['accepted', 'rejected', 'malformed', 'array', 'wrongexit', 'large', 'unicodeLarge', 'timeout', 'cancel', 'replacement']
assert all(not pathlib.Path(f"/proc/{row['pid']}").exists() for row in rows), 'Helper survived cancellation or completion'
print('provider stdin, argv, single-dispatch, cancellation, and helper cleanup checks passed')
PY
