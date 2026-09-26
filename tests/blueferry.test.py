#!/usr/bin/python3
"""Run only in omabox: owns a fake BlueFerry session service, never Bluetooth."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest

if os.environ.get('OMABOX') != '1':
    sys.exit('Run this session D-Bus fixture inside omabox')
ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'bin/omalink-blueferry'
loader = importlib.machinery.SourceFileLoader('blueferry_adapter', str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
model = importlib.util.module_from_spec(spec)
loader.exec_module(model)

if '--server' in sys.argv:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(model.SERVICE, bus)
    state = {'mode': 'ok', 'calls': [], 'replacements': []}
    def status():
        locked = state['mode'] == 'locked' or (state['mode'] == 'lock_after' and 'ListThreads' in state['calls'])
        return {'api_version': 1 if state['mode'] == 'old_api' else 2,
                'daemon': True, 'storage_policy': 'encrypted', 'storage_state': 'locked' if locked else 'ready',
                'connectivity_state': 'degraded' if state['mode'] == 'offline' else 'ready',
                'map': False if state['mode'] == 'offline' else True, 'pbap': True, 'ancs': False,
                'backend_release': '0.6.2', 'storage_detail': 'SECRET DETAIL', 'iphone_mac': 'SECRET ID'}
    def threads():
        message = {'handle': 'h1', 'body': 'Hello <b>plain</b> 🔒', 'timestamp': '2026-09-25T12:34:56+00:00',
                   'outgoing': False, 'read': False, 'sender': 'Person', 'body_truncated': False}
        if state['mode'] == 'bad_time':
            message['timestamp'] = 'not a date'
        if state['mode'] == 'huge_body':
            message['body'] = '🙂' * 3000
        row = {'key': 'group:opaque/雪', 'name': 'Friends', 'is_group': True, 'recipients': ['test@example.org'],
               'messages': [message], 'last_ts': '2026-09-25T12:34:56+00:00', 'messages_truncated': True,
               'secret_extra': 'never retained'}
        return [row, dict(row, key='other:key', name='Other', messages=[])]
    class Service(dbus.service.Object):
        @dbus.service.method(model.INTERFACE, in_signature='', out_signature='s')
        def GetStatus(self):
            state['calls'].append('GetStatus')
            if state['mode'] in ('authorization', 'rate'):
                suffix = 'AuthorizationRequired' if state['mode'] == 'authorization' else 'RateLimited'
                raise dbus.DBusException('SECRET backend exception', name=model.SERVICE + '.Error.' + suffix)
            return json.dumps(status())
        @dbus.service.method(model.INTERFACE, in_signature='u', out_signature='s')
        def ListThreads(self, limit):
            state['calls'].append('ListThreads')
            assert int(limit) == 200
            if state['mode'] == 'restart':
                bus.release_name(model.SERVICE)
                connection = dbus.SessionBus(private=True)
                newname = dbus.service.BusName(model.SERVICE, connection)
                state['replacements'].append((connection, newname, Service(connection, model.PATH)))
            if state['mode'] == 'oversize':
                return ' ' * (model.WIRE_LIMIT + 1)
            if state['mode'] == 'malformed':
                return 'bad json'
            return json.dumps(threads())
        @dbus.service.method(model.INTERFACE, in_signature='uu', out_signature='s')
        def ListContacts(self, offset, limit):
            state['calls'].append('ListContacts')
            assert (int(offset), int(limit)) == (0, 100)
            return json.dumps([{'name': 'Person', 'phones': ['+15555550123'], 'emails': ['person@example.org']}])
        @dbus.service.method(model.INTERFACE, in_signature='s', out_signature='s', async_callbacks=('done', 'fail'))
        def FindContacts(self, query, done, fail):
            state['calls'].append('FindContacts')
            assert str(query) == 'Private query 🚀'
            def finish():
                done(json.dumps([{'name': 'Person', 'address': 'person@example.org'}]))
                return False
            GLib.timeout_add(400, finish)
        @dbus.service.method('org.omalink.Test', in_signature='s', out_signature='')
        def Mode(self, mode):
            for connection, newname, service in state['replacements']:
                connection.release_name(model.SERVICE)
            state['replacements'] = []
            bus.request_name(model.SERVICE)
            if mode == 'absent':
                bus.release_name(model.SERVICE)
            state['mode'] = str(mode); state['calls'] = []
        @dbus.service.method('org.omalink.Test', in_signature='', out_signature='s')
        def Calls(self):
            return json.dumps(state['calls'])
    service = Service(bus, model.PATH)
    print(bus.get_unique_name(), flush=True)
    GLib.MainLoop().run()
    sys.exit(0)


class BlueFerry(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import dbus
        cls.server = subprocess.Popen(['/usr/bin/python3', __file__, '--server'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cls.owner = cls.server.stdout.readline().decode().strip()
        assert model.valid_owner(cls.owner)
        cls.bus = dbus.SessionBus()
        cls.control = dbus.Interface(cls.bus.get_object(cls.owner, model.PATH), 'org.omalink.Test')
    @classmethod
    def tearDownClass(cls):
        cls.server.terminate(); cls.server.communicate(timeout=5)
    def setUp(self):
        self.control.Mode('ok')
    def request(self, operation='status', **extra):
        value = {'version': 1, 'operation': operation}
        if operation != 'status':
            value.update(endpoint=dict(model.ENDPOINT), expectedOwner=self.owner)
        value.update(extra)
        return value
    def run_helper(self, request, inspect=False, command=None):
        process = subprocess.Popen(command or [str(HELPER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.stdin.write(json.dumps(request).encode()); process.stdin.close(); process.stdin = None
        if inspect:
            time.sleep(.15)
            self.assertIsNone(process.poll())
            for pid in [process.pid, self.server.pid]:
                for entry in ['cmdline', 'environ']:
                    self.assertNotIn(request['query'].encode(), Path(f'/proc/{pid}/{entry}').read_bytes())
                self.assertEqual(Path(f'/proc/{pid}/task/{pid}/children').read_text().strip(), '')
        out, err = process.communicate(timeout=20)
        self.assertEqual(err, b'')
        self.assertLessEqual(len(out), model.OUTPUT_LIMIT)
        self.assertNotIn(b'SECRET', out)
        self.assertNotIn(b'never retained', out)
        result = json.loads(out)
        self.assertEqual(result['version'], 1)
        self.assertEqual(process.returncode, 0 if result['ok'] else 1)
        return result
    def test_status_and_redaction(self):
        result = self.run_helper(self.request())
        self.assertTrue(result['ok']); self.assertEqual(result['endpoint'], model.ENDPOINT)
        self.assertEqual(result['backendOwner'], self.owner)
        self.assertTrue(result['canReadHistory'])
        self.assertEqual(result['items'], [])
    def test_threads_and_exact_opaque_messages(self):
        result = self.run_helper(self.request('threads'))
        self.assertTrue(result['items'][0]['unread'])
        self.assertEqual(result['items'][0]['threadId'], 'group:opaque/雪')
        self.assertTrue(result['items'][0]['messagesTruncated'])
        result = self.run_helper(self.request('messages', threadId='group:opaque/雪'))
        self.assertEqual(len(result['items']), 1)
        self.assertEqual(result['items'][0]['body'], 'Hello <b>plain</b> 🔒')
        self.assertFalse(result['items'][0]['bodyTruncated'])
        self.assertTrue(result['history']['truncated'])
        self.assertEqual(self.run_helper(self.request('messages', threadId='absent'))['code'], 'thread_unavailable')
    def test_contacts_and_private_query(self):
        result = self.run_helper(self.request('contacts'))
        self.assertEqual([r['number'] for r in result['items']], ['+15555550123', 'person@example.org'])
        result = self.run_helper(self.request('contacts', query='Private query 🚀'), inspect=True)
        self.assertEqual(result['items'], [{'name': 'Person', 'number': 'person@example.org'}])
    def test_no_owner_no_activation(self):
        self.control.Mode('absent')
        self.assertEqual(self.run_helper(self.request())['code'], 'backend_unavailable')
        self.assertEqual(json.loads(self.control.Calls()), [])
    def test_stale_owner_cannot_read(self):
        self.assertEqual(self.run_helper(self.request('threads', expectedOwner=':1.99999'))['code'], 'backend_changed')
        self.assertEqual(json.loads(self.control.Calls()), [])
    def test_replacement_discards_read_without_retry(self):
        self.control.Mode('restart')
        self.assertEqual(self.run_helper(self.request('threads'))['code'], 'backend_changed')
        self.assertEqual(json.loads(self.control.Calls()).count('ListThreads'), 1)
    def test_api_version_and_storage(self):
        self.control.Mode('old_api')
        self.assertEqual(self.run_helper(self.request('threads'))['code'], 'api_incompatible')
        self.assertNotIn('ListThreads', json.loads(self.control.Calls()))
        self.control.Mode('locked')
        self.assertFalse(self.run_helper(self.request())['canReadHistory'])
        self.assertEqual(self.run_helper(self.request('threads'))['code'], 'storage_unavailable')
        self.assertNotIn('ListThreads', json.loads(self.control.Calls()))
        self.control.Mode('lock_after')
        self.assertEqual(self.run_helper(self.request('threads'))['code'], 'storage_unavailable')
    def test_offline_cached_history_allowed(self):
        self.control.Mode('offline')
        result = self.run_helper(self.request('threads'))
        self.assertTrue(result['ok']); self.assertEqual(result['connection'], 'offline')
    def test_errors_are_fixed_codes(self):
        for mode, code in [('authorization', 'authorization_required'), ('rate', 'rate_limited'),
                           ('oversize', 'response_too_large'), ('malformed', 'invalid_response')]:
            self.control.Mode(mode)
            self.assertEqual(self.run_helper(self.request('threads'))['code'], code)
    def test_input_and_dependency_fail_closed(self):
        for value in [self.request('send'), self.request('threads', endpoint=dict(model.ENDPOINT, deviceId='somephone')),
                      self.request('messages', threadId='x\n'), self.request('messages', threadId='x' * 1025),
                      self.request('contacts', query='x' * 257), self.request('threads', expectedOwner=model.SERVICE)]:
            self.assertEqual(self.run_helper(value)['code'], 'invalid_request')
        self.assertEqual(self.run_helper(self.request(), command=['/usr/bin/python3', '-S', str(HELPER)])['code'], 'dependency')
        self.assertEqual(json.loads(self.control.Calls()), [])
    def test_content_and_timestamp_bounds(self):
        self.control.Mode('huge_body')
        message = self.run_helper(self.request('messages', threadId='group:opaque/雪'))['items'][0]
        self.assertEqual(len(message['body'].encode()), 8192); self.assertTrue(message['bodyTruncated'])
        self.control.Mode('bad_time')
        self.assertEqual(self.run_helper(self.request('messages', threadId='group:opaque/雪'))['items'], [])
    def test_output_and_wire_shape_bounds(self):
        with self.assertRaises(model.Rejected):
            model.encode({'body': 'x' * model.OUTPUT_LIMIT})
        for value in [[], {}, {'api_version': True}, {'api_version': '2'}, {'api_version': 3}]:
            with self.assertRaises(model.Rejected):
                model.normalized_status(value)
        for rows in [[{}], [{'key': 'x', 'messages': []}] * 201]:
            with self.assertRaises(model.Rejected):
                model.threads_from(rows)
        self.assertIsNone(model.timestamp('2026-09-25T12:00:00'))
        self.assertIsNone(model.timestamp('nonsense'))
    def test_stalled_input_deadline(self):
        process = subprocess.Popen([str(HELPER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.stdin.write(b'{'); process.stdin.flush()
        started = time.monotonic(); process.wait(timeout=20)
        out, err = process.communicate()
        self.assertLess(time.monotonic() - started, 20)
        self.assertEqual(json.loads(out)['code'], 'read_failed'); self.assertEqual(err, b'')


if __name__ == '__main__':
    unittest.main()
