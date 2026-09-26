#!/usr/bin/env python3
"""Run inside omabox. Metadata, diagnostics and send preflight use fake tools."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

HELPER = Path(__file__).resolve().parents[1] / 'bin/omalink'
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    env = dict(os.environ, PATH=f'{root}:/usr/bin', CAP_TEST_ROOT=str(root))
    cli = root / 'kdeconnect-cli'
    cli.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['CAP_TEST_ROOT'])
mode = os.environ.get('CAP_MODE', '')
if '--version' in sys.argv:
    print('kdeconnect-cli 26.08.1' if mode != 'bad-version' else 'kdeconnect-cli 26.08.1\\nPRIVATE-NAME')
elif '--list-devices' in sys.argv:
    print('known1\\noffline2\\nunpaired3' if mode != 'many' else '\\n'.join('device' + str(i) for i in range(12)))
elif '--send-sms' in sys.argv:
    with (root / 'sent').open('a') as stream: stream.write('sms\\n')
else: sys.exit(1)
''')
    bus = root / 'busctl'
    bus.write_text('''#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ['CAP_TEST_ROOT'])
mode = os.environ.get('CAP_MODE', '')
args = sys.argv[1:]
with (root / 'calls').open('a') as stream: stream.write(json.dumps(args) + '\\n')
if 'GetNameOwner' in args:
    if mode == 'absent': sys.exit(1)
    count = root / 'owners'
    number = int(count.read_text()) + 1 if count.exists() else 1
    count.write_text(str(number))
    print(json.dumps(dict(type='s', data=[':1.100' if mode == 'restart' and number > 1 else ':1.99'])))
    sys.exit(1 if mode == 'partial-owner' else 0)
service = args[args.index('--') + 1]
assert service == ':1.99', ('not owner bound', args)
path = args[args.index('--') + 2]
device = path.rsplit('/', 1)[-1]
prop = args[-1]
plugins = ['kdeconnect_sms','kdeconnect_notifications','kdeconnect_contacts','kdeconnect_share',
           'kdeconnect_clipboard','kdeconnect_findmyphone','kdeconnect_mprisremote','kdeconnect_battery',
           'kdeconnect_sftp','kdeconnect_connectivity_report']
if 'replyToConversation' in args or 'sendReply' in args:
    with (root / 'sent').open('a') as stream: stream.write('reply\\n')
elif prop == 'name': print('s "PRIVATE-NAME"')
elif prop == 'type': print('s "phone"')
elif prop == 'isPaired': print('b false' if device == 'unpaired3' else 'b true')
elif prop == 'isReachable':
    print('b false' if device == 'offline2' or mode == 'offline' else 'b true')
    if mode == 'timeout-ready':
        sys.stdout.flush(); time.sleep(3)
    if mode == 'partial-ready': sys.exit(1)
elif prop == 'supportedPlugins':
    print(json.dumps(dict(type='as', data=[] if mode == 'unsupported' else plugins)))
elif prop == 'loadedPlugins':
    print(json.dumps(dict(type='as', data=[[] if mode in ('disabled','unloaded') else plugins])))
    if mode == 'oversize-plugins': print(' ' * 70000)
    if mode == 'partial-plugins': sys.exit(1)
elif 'isPluginEnabled' in args:
    print(json.dumps(dict(type='b', data=[mode != 'disabled'])))
    if mode == 'partial-enabled': sys.exit(1)
elif prop == 'activeNotifications': print('{"type":"as","data":[[]]}')
elif prop == 'playerList': print('{"type":"as","data":[]}')
else: sys.exit(1)
''')
    cli.chmod(0o755)
    bus.chmod(0o755)

    def run(*args, mode=''):
        (root / 'owners').unlink(missing_ok=True)
        (root / 'calls').write_text('')
        result = subprocess.run([str(HELPER), *args], env=dict(env, CAP_MODE=mode),
                                capture_output=True, text=True, timeout=45)
        return result

    report = run('diagnostics')
    assert report.returncode == 0, report.stderr
    data = json.loads(report.stdout)
    assert data['backend']['version'] == '26.08.1'
    assert data['observedAt'] > 0
    assert data['devices'][0]['capabilities']['messaging']['state'] == 'available'
    assert data['devices'][0]['capabilities']['messaging']['permission'] == 'unknown'
    assert data['devices'][1]['connectionState'] == 'offline'
    assert data['devices'][2]['connectionState'] == 'unpaired'
    assert 'PRIVATE' not in report.stdout and 'known1' not in report.stdout and '/modules/' not in report.stdout
    assert all(not any(field in call for field in ('activeNotifications','playerList','activeConversations'))
               for call in (json.loads(line) for line in (root / 'calls').read_text().splitlines()))

    for mode, expected in [('disabled','disabled'), ('unsupported','unsupported'), ('unloaded','unknown'),
                           ('partial-ready','unknown'), ('timeout-ready','unknown'), ('partial-plugins','unknown'),
                           ('oversize-plugins','unknown'), ('partial-enabled','unknown')]:
        result = run('diagnostics', mode=mode)
        assert result.returncode == 0, (mode, result.stderr)
        assert json.loads(result.stdout)['devices'][0]['capabilities']['messaging']['state'] == expected, mode

    for mode in ('absent', 'partial-owner', 'restart'):
        result = run('status', mode=mode)
        assert result.returncode != 0, mode
        assert json.loads(result.stdout)['backend']['available'] is False
        result = run('diagnostics', mode=mode)
        assert result.returncode == 0, (mode, result.stderr)
        data = json.loads(result.stdout)
        assert data['ok'] is False and data['failureReason'] in ('backend-unavailable','backend-restarted')

    assert json.loads(run('diagnostics', mode='bad-version').stdout)['backend']['version'] is None
    data = json.loads(run('diagnostics', mode='many').stdout)
    assert len(data['devices']) == 8 and data['discoveryTruncated'] is True

    for command in [('sms','known1','+15550000001','exact'), ('reply','known1','7','exact'),
                    ('notify-reply','known1','reply1','exact')]:
        for mode in ('offline','partial-ready','partial-plugins','restart','absent'):
            (root / 'sent').unlink(missing_ok=True)
            result = run(*command, mode=mode)
            assert result.returncode != 0 and not (root / 'sent').exists(), (command, mode)
        result = run(*command)
        # Legacy argv content entry points fail closed; private D-Bus sends
        # and capability checks are covered by text-transport.test.py.
        assert result.returncode == 2, (command, result.stderr)
        assert not (root / 'sent').exists()

print('capability and diagnostics tests passed')
