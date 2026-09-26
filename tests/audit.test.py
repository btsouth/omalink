#!/usr/bin/env python3
"""Adversarial helper tests. Run inside omabox; all phone/desktop tools are mocks."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

HELPER = str(Path(__file__).resolve().parents[1] / 'bin/omalink')

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    for folder in ('bin', 'tmp', 'runtime', 'data', 'home'):
        (root / folder).mkdir(mode=0o700)
    env = dict(os.environ, PATH=f'{root}/bin:/usr/bin', HOME=str(root / 'home'),
               TMPDIR=str(root / 'tmp'), XDG_RUNTIME_DIR=str(root / 'runtime'),
               XDG_DATA_HOME=str(root / 'data'), AUDIT_ROOT=str(root))

    def script(name, source):
        path = root / 'bin' / name
        path.write_text('#!/usr/bin/python3\n' + source)
        path.chmod(0o755)

    script('kdeconnect-cli', "import sys\nprint('kdeconnect-cli 26.08.1' if '--version' in sys.argv else '')\n")

    script('busctl', '''
import json, os, signal, sys, time
from pathlib import Path
root = Path(os.environ['AUDIT_ROOT'])
args = sys.argv[1:]
with (root / 'args').open('a') as log: log.write(json.dumps(args) + '\\n')
mode = os.environ.get('AUDIT_MODE', '')
if 'GetNameOwner' in args:
    print('{"type":"s","data":[":1.99"]}'); sys.exit(0)
if args[-4:] == ['devices', 'bb', 'false', 'false']:
    print('{"type":"as","data":[["abc123"]]}'); sys.exit(0)
if args[-1:] == ['name']:
    print('s ' + json.dumps('N' * 100000)); sys.exit(0)
if args[-1:] == ['type']: print('s "phone"'); sys.exit(0)
if args[-1:] in (['isPaired'], ['isReachable']): print('b true'); sys.exit(0)
if args[-1:] == ['supportedPlugins']: print('{"type":"as","data":[]}'); sys.exit(0)
if args[-1:] == ['loadedPlugins']: print('{"type":"as","data":[["kdeconnect_sms","kdeconnect_notifications"]]}'); sys.exit(0)
if 'isPluginEnabled' in args: print('{"type":"b","data":[true]}'); sys.exit(0)
if 'monitor' in args or 'requestConversation' in args or 'requestAttachmentFile' in args:
    with (root / 'pids').open('a') as log: log.write(str(os.getpid()) + '\\n')
if 'monitor' in args:
    if mode == 'flood':
        # Wait until the request is really pending, then flood and stall.
        while not (root / 'pending').exists(): time.sleep(.01)
        try:
            while True: os.write(1, b'X' * 65536)
        except BrokenPipeError: pass
    elif mode == 'crossphone':
        for device, body in [('other123', 'wrong phone'), ('abc123', 'right phone')]:
            print(json.dumps(dict(type='signal', path='/modules/kdeconnect/devices/' + device,
                interface='org.kde.kdeconnect.device.conversations', member='conversationUpdated',
                payload=dict(data=[dict(data=[1,body,[],1000,1,0,7,1,-1,[]])]))), flush=True)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    while True: time.sleep(1)
if 'requestConversation' in args or 'requestAttachmentFile' in args:
    if mode in ('flood', 'pending'):
        (root / 'pending').touch()
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        while True: time.sleep(1)
    sys.exit(0)
if 'activeConversations' in args:
    print(json.dumps(dict(data=[[dict(data=[1,'hello',[['+15550000001']],1000,1,0,7,1,-1,[]])]])))
    sys.exit(0)
if args[-1:] == ['playerList']:
    # A doubled mprisremote suffix must not pass a mock accidentally.
    if any('/mprisremote/mprisremote' in arg for arg in args): sys.exit(1)
    print('{"data":["Player"]}'); sys.exit(0)
if args[-1:] == ['position']: print('i 900'); sys.exit(0)
if args[-1:] == ['activeNotifications']:
    print(json.dumps(dict(data=[[f'n{i}' for i in range(300)]]))); sys.exit(0)
if args[-1:] == ['text']: print(json.dumps(dict(data='B' * 8192))); sys.exit(0)
if args[-1:] == ['appName']: print('{"data":"Messages"}'); sys.exit(0)
if args[-1:] == ['internalId']: print('{"data":"0|com.test.messages|1"}'); sys.exit(0)
sys.exit(0)
''')
    script('head', '''
import os, stat, subprocess, sys
from pathlib import Path
result = subprocess.run(['/usr/bin/head'] + sys.argv[1:])
info = os.fstat(1)
if stat.S_ISREG(info.st_mode):
    with (Path(os.environ['AUDIT_ROOT']) / 'sizes').open('a') as log: log.write(str(info.st_size) + '\\n')
sys.exit(result.returncode)
''')

    def run(*args, mode='', timeout=10):
        return subprocess.run([HELPER, *args], env=dict(env, AUDIT_MODE=mode),
                              capture_output=True, text=True, timeout=timeout)

    def no_children():
        pids = (root / 'pids').read_text().splitlines()
        for _ in range(100):
            if not any(Path('/proc', pid).exists() for pid in pids):
                return
            time.sleep(.02)
        raise AssertionError(f'capture left processes: {pids}')

    for args in [('messages', 'abc123', '7'), ('attachment', 'abc123', '42', 'photo.jpg')]:
        (root / 'pending').unlink(missing_ok=True)
        (root / 'pids').write_text('')
        (root / 'sizes').write_text('')
        started = time.monotonic()
        result = run(*args, mode='flood', timeout=8)
        assert result.returncode != 0, result
        assert 'capture limit' in result.stderr, result.stderr
        assert time.monotonic() - started < 5
        assert (root / 'pending').exists(), 'request never entered pending state'
        sizes = [int(size) for size in (root / 'sizes').read_text().splitlines()]
        assert sizes and max(sizes) == 16 * 1024 * 1024, sizes
        no_children()
        assert not list((root / 'tmp').iterdir()), 'capture directory leaked'

    # Closing the window terminates a request as well as its monitor.
    (root / 'pending').unlink()
    (root / 'pids').write_text('')
    process = subprocess.Popen([HELPER, 'messages', 'abc123', '7'],
                               env=dict(env, AUDIT_MODE='pending'), stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    for _ in range(200):
        if (root / 'pending').exists(): break
        time.sleep(.01)
    assert (root / 'pending').exists()
    process.terminate()
    process.communicate(timeout=5)
    no_children()
    assert not list((root / 'tmp').iterdir())

    result = run('messages', 'abc123', '7', mode='crossphone')
    assert result.returncode == 0, result.stderr
    assert [item['body'] for item in json.loads(result.stdout)] == ['right phone']
    no_children()

    # Content-bearing argv commands fail closed. The stdin transport suite
    # checks verbatim flag-like bodies without exposing them to subprocesses.
    for message in ('--popups', '--notify-apps', '$(touch /tmp/never)'):
        before = (root / 'args').read_text()
        result = run('reply', 'abc123', '7', message)
        assert result.returncode == 2, result.stderr
        assert (root / 'args').read_text() == before
    assert run('--popups', 'invalid', 'status').returncode == 2
    result = run('media-seek', 'abc123', '001000')
    assert result.returncode == 0, result.stderr
    assert json.loads((root / 'args').read_text().splitlines()[-1])[-1] == '100'
    assert run('media-seek', 'abc123', '99999999999999999999999').returncode == 2
    assert run('media-volume', 'abc123', '099').returncode == 0

    # Many individually valid notification bodies exceed the OS argv limit.
    result = run('status', timeout=30)
    assert result.returncode == 0, result.stderr
    device = json.loads(result.stdout)['devices'][0]
    assert len(device['name']) == 256
    assert len(device['notifications']) == 25
    assert all(len(item['text']) == 8192 for item in device['notifications'])

    # Maximum-sized contacts must not be passed as one oversize argv string.
    contacts = root / 'data/kpeoplevcard/kdeconnect-abc123'
    contacts.mkdir(parents=True)
    (contacts / 'contacts.vcf').write_text(''.join(
        f'BEGIN:VCARD\nFN:{"N" * 240}{i}\nTEL:+1555{i:07d}\nEND:VCARD\n'
        for i in range(2000)))
    result = run('conversations', 'abc123')
    assert result.returncode == 0, result.stderr
    assert len(json.loads(result.stdout)) == 1
    assert not list((root / 'tmp').iterdir())

    (root / 'args').write_text('')
    result = run('dismiss-all', 'abc123')
    assert result.returncode == 0, result.stderr
    calls = [json.loads(line) for line in (root / 'args').read_text().splitlines()]
    assert len([args for args in calls if args[-1] == 'dismiss']) == 100

    # Thread ids overlap between devices and late writes must not lower a mark.
    assert run('mark-seen', 'abc123', '7', '2000').returncode == 0
    assert run('mark-seen', 'abc123', '7', '1000').returncode == 0
    assert json.loads(run('seen', 'abc123').stdout) == {'7': 2000}
    assert json.loads(run('seen', 'other123').stdout) == {}

    # Flooding notification signals creates at most four popup workers.
    script('dbus-monitor', '''
import sys
for i in range(100):
    print("signal path=/modules/kdeconnect/devices/abc123/notifications; member=notificationPosted")
    print('   string "n' + str(i) + '"')
''')
    script('notify-send', '''
import os, time
from pathlib import Path
with (Path(os.environ['AUDIT_ROOT']) / 'popups').open('a') as log: log.write('popup\\n')
time.sleep(1)
''')
    result = run('watch')
    assert result.returncode == 0, result.stderr
    assert len((root / 'popups').read_text().splitlines()) == 4
    assert not (root / 'home/.config/kdeconnect.notifyrc').exists()
    assert not list((root / 'runtime').glob('omalink-watch.*[0-9A-Z]'))

print('audit tests passed: hard capture ceiling, pending cleanup, device isolation, arguments, contacts, popup flood')
