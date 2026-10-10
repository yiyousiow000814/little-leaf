"""Mocked exact-channel update/rollback; never authenticates or deploys."""
from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit
import update_auth_preview as update
import deploy_firebase_hosting as hosting

NOW = datetime(2026, 10, 10, tzinfo=timezone.utc)
OLD, NEW = hosting.SITE_PATH + '/versions/old', hosting.SITE_PATH + '/versions/new'
CONFIG = {'headers': [{'glob': p, 'headers': {'Content-Security-Policy': hosting.FRAME_POLICY}}
                      for p in ['/', '/index.html']], 'cleanUrls': False}


class API:
    def __init__(self, failure=None):
        self.calls = []; self.failure = failure; self.config = deepcopy(CONFIG)
        self.channel = {'name': hosting.PREVIEW_PATH, 'url': update.ORIGIN, 'expireTime': update.EXPIRY,
                        'release': {'name': hosting.PREVIEW_PATH + '/releases/old', 'version': {'name': OLD}}}
        self.live = {'releases': [{'name': hosting.SITE_PATH + '/releases/live', 'version': {'name': OLD}}]}
        if failure == 'host': self.channel['url'] = 'https://evil.test'
        if failure == 'expiry': self.channel['expireTime'] = '2026-10-12T00:00:00Z'

    def request(self, method, path, data=None, upload=False):
        self.calls.append((method, path, data, upload))
        if path == hosting.PREVIEW_PATH:
            return deepcopy(self.channel)
        if path == hosting.SITE_PATH + '/releases?pageSize=1': return self.live
        if method == 'GET' and path == OLD: return {'name': OLD, 'status': 'FINALIZED', 'config': self.config}
        if path == hosting.SITE_PATH + '/versions':
            assert data == {'config': CONFIG};return {'name': NEW}
        if path == NEW + ':populateFiles':
            return {'uploadUrl': 'https://upload-firebasehosting.googleapis.com/upload/' + NEW + '/files', 'uploadRequiredHashes': []}
        if method == 'PATCH':
            if self.failure == 'concurrent': self.channel['release']['name'] += 'concurrent'
            return {'name': NEW, 'status': 'FINALIZED'}
        if '/releases?' in path:
            if self.failure == 'release': raise RuntimeError('uncertain')
            self.channel['release'] = {'name': hosting.PREVIEW_PATH + '/releases/new', 'version': {'name': NEW}, 'type': 'DEPLOY'}
            return self.channel['release']
        raise AssertionError((method, path))


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / 'receipt.json'

    def run_update(self, api, mode='update', observe=None, now=NOW):
        with patch.object(update, 'verify_archive', return_value={'index.html': b'fixture'}):
            return update.deploy(Path('fixture.zip'), mode, self.output, api,
                                 observe or (lambda *_: None), now=now)

    def test_update_and_rollback_preserve_config_expiry_and_live(self):
        for mode in ['update', 'rollback']:
            with self.subTest(mode=mode):
                self.output = Path(self.temp.name) / (mode + '.json');api = API();seen = []
                receipt = self.run_update(api, mode, observe=lambda origin, files: seen.append((origin, files)))
                self.assertEqual(receipt['expire_time'], update.EXPIRY)
                self.assertEqual(receipt['origin'], update.ORIGIN)
                self.assertEqual(len(seen), 2)
                self.assertEqual(seen[0][1], update.recipe()['archives']['rollback' if mode == 'update' else 'update']['files'])
                self.assertEqual(seen[1][1], update.recipe()['archives'][mode]['files'])
                self.assertFalse(any(method == 'DELETE' or path.startswith(hosting.SITE_PATH + '/channels?')
                                     or method != 'GET' and path.startswith(hosting.SITE_PATH + '/releases') for method, path, *_ in api.calls))
                self.assertEqual(sum(method == 'POST' and '/releases?' in path for method, path, *_ in api.calls), 1)

    def test_bad_archive_rejected_before_network(self):
        archive = Path(self.temp.name) / 'bad.zip';archive.write_bytes(b'corrupt');api = API()
        with self.assertRaises(ValueError): update.deploy(archive, 'update', self.output, api, now=NOW)
        self.assertEqual(api.calls, [])

    def test_host_expiry_and_expiration_stop_before_mutation(self):
        for failure, now in [('host', NOW), ('expiry', NOW), (None, datetime(2026, 10, 12, tzinfo=timezone.utc))]:
            api = API(failure)
            with self.subTest(failure=failure), self.assertRaises(ValueError): self.run_update(api, now=now)
            self.assertTrue(all(method == 'GET' for method, *_ in api.calls))

    def test_unexpected_current_public_bytes_stop_before_mutation(self):
        api = API()
        def fail(*_): raise ValueError('Wrong current public inventory')
        with self.assertRaises(ValueError): self.run_update(api, observe=fail)
        self.assertTrue(all(method == 'GET' for method, *_ in api.calls))

    def test_concurrent_preview_change_stops_before_release(self):
        api = API('concurrent')
        with self.assertRaises(ValueError): self.run_update(api)
        self.assertFalse(any(method == 'POST' and '/releases?' in path for method, path, *_ in api.calls))

    def test_uncertain_release_retains_receipt_and_never_retries(self):
        api = API('release')
        with self.assertRaises(RuntimeError): self.run_update(api)
        self.assertEqual(json.loads(self.output.read_text())['status'], 'preview-release-outcome-pending')
        self.assertEqual(sum(method == 'POST' and '/releases?' in path for method, path, *_ in api.calls), 1)
        calls = len(api.calls)
        with self.assertRaises(ValueError): self.run_update(api)
        self.assertEqual(len(api.calls), calls)

    def test_gate_rejects_live_creation_arbitrary_versions_and_credentials_apis(self):
        api = API();gate = update.UpdateAPI(api)
        for method, path in [('POST', hosting.SITE_PATH + '/releases?versionName=' + NEW),
                             ('POST', hosting.SITE_PATH + '/channels?channelId=itch-embed-test'),
                             ('PATCH', hosting.PREVIEW_PATH), ('DELETE', hosting.PREVIEW_PATH),
                             ('GET', NEW), ('POST', NEW + ':populateFiles'),
                             ('POST', 'https://identitytoolkit.googleapis.com/v1/projects')]:
            with self.subTest(path=path), self.assertRaises(ValueError): gate.request(method, path, {})
        self.assertEqual(api.calls, [])


if __name__ == '__main__':
    unittest.main()
