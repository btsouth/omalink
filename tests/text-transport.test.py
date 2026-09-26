#!/usr/bin/python3
"""Run in omabox: real private session D-Bus fixture, never a real phone."""
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'bin/omalink-text'

if os.environ.get('OMABOX') != '1':
    sys.exit('Run this session D-Bus test inside omabox')

if '--server' in sys.argv:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName('org.kde.kdeconnect', bus)
    state = {'mode': 'ok', 'calls': []}
    iface = 'org.kde.kdeconnect.device'
    class Base(dbus.service.Object):
        @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
        def Get(self, interface, prop):
            if state['mode'] == 'invalid_property':
                return dbus.String('true')
            return dbus.Boolean(state['mode'] != prop)
        @dbus.service.method(iface, in_signature='s', out_signature='b')
        def hasPlugin(self, plugin):
            return state['mode'] != 'disabled'
        @dbus.service.method(iface + '.conversations', in_signature='avsav', out_signature='', async_callbacks=('done', 'fail'))
        def sendWithoutConversation(self, addresses, body, attachments, done, fail):
            assert len(addresses) == 1 and len(addresses[0]) == 1 and isinstance(addresses[0][0], dbus.String) and addresses[0].variant_level == 1
            assert not attachments
            self.sent('sms', str(addresses[0][0]), body, done, fail)
        @dbus.service.method(iface + '.conversations', in_signature='xsav', out_signature='', async_callbacks=('done', 'fail'))
        def replyToConversation(self, thread, body, attachments, done, fail):
            self.sent('reply', str(thread), body, done, fail)
        def sent(self, operation, target, body, done, fail):
            state['calls'].append([operation, target, str(body)])
            def finish():
                if state['mode'] == 'dispatch_error':
                    fail(dbus.DBusException('untrusted error contains ' + body))
                else:
                    done()
                return False
            GLib.timeout_add(500, finish)
        @dbus.service.method('org.omalink.Test', in_signature='s', out_signature='')
        def Mode(self, mode):
            state['mode'] = str(mode)
            state['calls'] = []
        @dbus.service.method('org.omalink.Test', in_signature='', out_signature='s')
        def Calls(self):
            return json.dumps(state['calls'])
    class Share(Base):
        @dbus.service.method(iface + '.share', in_signature='s', out_signature='', async_callbacks=('done', 'fail'))
        def shareText(self, body, done, fail):
            self.sent('share', 'text', body, done, fail)
        @dbus.service.method(iface + '.share', in_signature='s', out_signature='', async_callbacks=('done', 'fail'))
        def shareUrl(self, body, done, fail):
            self.sent('share', 'url', body, done, fail)
    class Notifications(Base):
        @dbus.service.method(iface + '.notifications', in_signature='ss', out_signature='', async_callbacks=('done', 'fail'))
        def sendReply(self, reply, body, done, fail):
            self.sent('notify-reply', str(reply), body, done, fail)
    base = '/modules/kdeconnect/devices/phone1'
    objects = [Base(bus, base), Share(bus, base + '/share'), Notifications(bus, base + '/notifications')]
    print('ready', flush=True)
    GLib.MainLoop().run()
    sys.exit(0)

loader = importlib.machinery.SourceFileLoader('omalink_text', str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def request(operation='share', **extra):
    return dict(version=1, operation=operation, deviceId='phone1', body='  Private 🚀 secret\n', **extra)


class Validation(unittest.TestCase):
    def test_body_preserved_and_bounds(self):
        for body in ['  text\n', '--popups', '--notify-apps', '$(touch /tmp/never)', 'é' * 4096, '🙂' * 2048]:
            value = request(); value['body'] = body
            self.assertEqual(module.parse_request(io.BytesIO(json.dumps(value).encode()))['body'], body)
        for body in ['', '🙂' * 2049, '\0', '\ud800', 3]:
            value = request(); value['body'] = body
            with self.assertRaises(module.Rejected):
                module.parse_request(io.BytesIO(json.dumps(value).encode()))
    def test_changed_owner_never_dispatches(self):
        import dbus
        class ChangedOwner(module.Transport):
            def __init__(self):
                self.dbus = dbus
                self.dispatched = False
                self.owners = iter([':1.2', ':1.3'])
            def owner(self):
                return next(self.owners)
            def call(self, *args, **kwargs):
                self.assert_no_dispatch = not kwargs.get('effect', False)
                return dbus.Boolean(True)
        transport = ChangedOwner()
        with self.assertRaises(module.Rejected) as caught:
            transport.submit(request())
        self.assertEqual(caught.exception.code, 'backend_changed')
        self.assertFalse(transport.dispatched)

    def test_invalid_envelopes(self):
        invalid = [b'{', b'\xff', b'[]', b' ' * 65537, b'{"version":1,"version":1}']
        for updates in [dict(version=True), dict(operation=[]), dict(deviceId='../phone'), dict(extra=1),
                        dict(operation='sms', destination='--address=bad'), dict(operation='reply', threadId='9223372036854775808'),
                        dict(operation='reply', threadId=7), dict(operation='notify-reply', replyId='--user')]:
            value = request(); value.update(updates); invalid.append(json.dumps(value).encode())
        for raw in invalid:
            with self.subTest(raw=raw[:100]), self.assertRaises(module.Rejected):
                module.parse_request(io.BytesIO(raw))


class SessionTransport(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import dbus
        cls.dbus = dbus
        cls.server = subprocess.Popen(['/usr/bin/python3', __file__, '--server'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if cls.server.stdout.readline() != b'ready\n':
            raise AssertionError('Fixture failed to start')
        cls.bus = dbus.SessionBus()
        cls.control = dbus.Interface(cls.bus.get_object('org.kde.kdeconnect', '/modules/kdeconnect/devices/phone1'), 'org.omalink.Test')
    @classmethod
    def tearDownClass(cls):
        cls.server.terminate(); cls.server.communicate(timeout=5)
    def setUp(self):
        self.control.Mode('ok')
    def submit(self, value, inspect_process=False, command=None):
        process = subprocess.Popen(command or [str(ROOT / 'bin/omalink'), 'text-stdin'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        payload = json.dumps(value).encode()
        process.stdin.write(payload); process.stdin.close(); process.stdin = None
        if inspect_process:
            time.sleep(.2)
            if process.poll() is not None:
                early_out, early_err = process.communicate()
                self.fail('helper exited before blocked dispatch: ' + repr((early_out, early_err)))
            for pid in [process.pid, self.server.pid]:
                for entry in ['cmdline', 'environ']:
                    process_data = Path(f'/proc/{pid}/{entry}').read_bytes()
                    self.assertNotIn(value['body'].encode(), process_data)
                    if 'destination' in value:
                        self.assertNotIn(value['destination'].encode(), process_data)
                children = Path(f'/proc/{pid}/task/{pid}/children').read_text().strip()
                self.assertEqual(children, '')
        out, err = process.communicate(timeout=22)
        self.assertEqual(err, b'')
        self.assertNotIn(value['body'].encode(), out)
        result = json.loads(out)
        self.assertEqual(result['version'], 1)
        return result, process.returncode
    def test_operations_exact_and_private(self):
        cases = [('share', {}, 'text'), ('sms', {'destination': '+1 (555) 000-0001'}, '+1 (555) 000-0001'),
                 ('reply', {'threadId': '9223372036854775807'}, '9223372036854775807'),
                 ('notify-reply', {'replyId': 'reply.id:1'}, 'reply.id:1')]
        for op, fields, target in cases:
            with self.subTest(operation=op):
                self.control.Mode('ok')
                value = request(op, **fields)
                result, code = self.submit(value, inspect_process=True)
                self.assertEqual((result['state'], code), ('accepted', 0))
                self.assertEqual(json.loads(self.control.Calls()), [[op, target, value['body']]])
    def test_url(self):
        value = request(); value['body'] = 'https://example.org/private?q=secret'
        self.assertEqual(self.submit(value)[0]['state'], 'accepted')
        self.assertEqual(json.loads(self.control.Calls())[0][1], 'url')
    def test_url_with_surrounding_text_stays_exact_text(self):
        for body in ['https://example.org\nA second line', 'https://example.org trailing text',
                     'https://example.org\n', ' https://example.org', 'https://example.org\u00a0']:
            self.control.Mode('ok')
            value = request(); value['body'] = body
            self.assertEqual(self.submit(value)[0]['state'], 'accepted')
            self.assertEqual(json.loads(self.control.Calls()), [['share', 'text', body]])

    def test_preflight_prevents_dispatch(self):
        for mode in ['isPaired', 'isReachable', 'disabled', 'invalid_property']:
            self.control.Mode(mode)
            result, code = self.submit(request())
            self.assertEqual((result['state'], code), ('not-submitted', 1))
            self.assertEqual(json.loads(self.control.Calls()), [])
    def test_error_after_dispatch_is_unknown_without_exception_text(self):
        self.control.Mode('dispatch_error')
        result, code = self.submit(request())
        self.assertEqual((result['state'], code), ('unconfirmed', 1))
        self.assertEqual(len(json.loads(self.control.Calls())), 1)
    def test_missing_dependency(self):
        result, code = self.submit(request(), command=['/usr/bin/python3', '-S', str(HELPER)])
        self.assertEqual((result['state'], result['code'], code), ('not-submitted', 'dependency', 1))
    def test_stalled_stdin_deadline(self):
        process = subprocess.Popen([str(HELPER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        started = time.monotonic()
        process.stdin.write(b'{'); process.stdin.flush()
        process.wait(timeout=22)
        out, err = process.communicate()
        self.assertLess(time.monotonic() - started, 22)
        self.assertEqual(json.loads(out)['state'], 'not-submitted')
        self.assertEqual(err, b'')


if __name__ == '__main__':
    unittest.main()
