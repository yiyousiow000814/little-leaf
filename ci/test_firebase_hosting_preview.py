"""Mocked preview-only channel protocol; no cloud authentication or deployment."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import unittest
from urllib.parse import parse_qs, urlsplit
import deploy_firebase_hosting as hosting
import test_firebase_hosting_deploy as fixtures

SHA, NEW = fixtures.SHA, fixtures.NEW

REAL_ORIGIN = 'https://' + hosting.SITE + '--itch-embed-test-abc123.web.app'


class PreviewFakeAPI(fixtures.FakeAPI):
    def __init__(self, fail=None):
        super().__init__(fail)
        now = datetime.now(timezone.utc)
        self.channel = {'name':hosting.PREVIEW_PATH, 'url':REAL_ORIGIN,
                        'createTime':now.isoformat(), 'expireTime':(now+timedelta(days=1)).isoformat()}
        if fail == 'wrong-expiry':self.channel['expireTime'] = (now+timedelta(days=2)).isoformat()
        if fail == 'wrong-origin':self.channel['url'] = 'https://evil.invalid'

    def request(self, method, path, data=None, upload=False):
        if path == hosting.SITE_PATH + '/channels?pageSize=100':
            self.calls.append((method, path, data, upload))
            return {'channels':[self.channel]} if self.fail == 'existing-channel' else {'channels':[]}
        if path == hosting.SITE_PATH + '/channels?channelId=' + hosting.PREVIEW_CHANNEL:
            self.calls.append((method, path, data, upload));return self.channel
        if path.startswith(hosting.PREVIEW_PATH + '/releases?'):
            self.calls.append((method, path, data, upload))
            if self.fail == 'preview-release':raise RuntimeError('uncertain preview release')
            version = parse_qs(urlsplit(path).query)['versionName'][0]
            release = {'name':hosting.PREVIEW_PATH+'/releases/p1', 'type':'DEPLOY', 'version':{'name':version}}
            self.channel = {**self.channel, 'release':release}
            return release
        if path == hosting.PREVIEW_PATH:
            self.calls.append((method, path, data, upload));return self.channel
        return super().request(method, path, data, upload)


class PreviewTests(unittest.TestCase):
    def setUp(self):
        fixture = fixtures.HostingTests('test_corrupt_package_stops_before_any_network')
        fixture.setUp();self.addCleanup(fixture.doCleanups)
        self.root, self.package, self.output = fixture.root, fixture.package, fixture.output
        self.manifest = fixture.manifest
        self.manifest.update(runtime_origin=hosting.FIXTURE_ORIGIN, ancestor_origins=hosting.ANCESTORS,
                             auth_domains_modified=False, production_release_eligible=False)
        marker = fixture.marker
        marker.update(runtime_origin=hosting.FIXTURE_ORIGIN, test_surface='trusted-itch-frame')
        (self.package / 'public/hosting-release.json').write_text(json.dumps(marker))
        (self.package / 'public/index.html').write_text('owned runtime '+hosting.FIXTURE_ORIGIN)
        wrapper = self.package / 'itch-wrapper';wrapper.mkdir()
        (wrapper / 'index.html').write_text('no SDK wrapper '+hosting.FIXTURE_ORIGIN)
        (self.package / 'firebase.json').write_text(json.dumps({'hosting':{
            'site':hosting.SITE, 'public':'public', 'headers':[{'source':path, 'headers':[
                {'key':'Content-Security-Policy','value':hosting.FRAME_POLICY}]} for path in ['/', '/index.html']]}}))
        self.manifest['source_sha256'] = {}
        for name in ['little_leaf_firebase_boot.mjs','little_leaf_firebase.js','little_leaf_firebase_session.js','little_leaf_update.js']:
            path = self.package / 'public' / name;path.write_text('synthetic owned runtime '+name)
            self.manifest['source_sha256']['web/'+name] = hosting.digest(path)
        self.write_manifest()

    def write_manifest(self):
        self.manifest['files'] = {p.relative_to(self.package).as_posix():hosting.digest(p)
                                  for p in self.package.rglob('*') if p.is_file() and p.name != 'firebase-variant-manifest.json'}
        path = self.package / 'firebase-variant-manifest.json';path.write_text(json.dumps(self.manifest));self.hash = hosting.digest(path)

    def deploy(self, api, smoke=True):
        def check(origin, marker):
            self.assertEqual(origin, REAL_ORIGIN);self.assertEqual(marker['runtime_origin'], REAL_ORIGIN)
            return smoke
        return hosting.deploy_preview(self.package, SHA, self.hash, self.output, api, check)

    def test_success_binds_origin_and_never_publishes_live(self):
        api = PreviewFakeAPI();before = api.head;result = self.deploy(api)
        self.assertEqual(result['status'], 'preview-published-pending-auth-acceptance')
        self.assertEqual(api.head, before);self.assertTrue(result['live_release_unchanged'])
        self.assertFalse(result['auth_domains_modified']);self.assertEqual(result['exact_hostname'], urlsplit(REAL_ORIGIN).hostname)
        self.assertEqual(api.releases, 0)
        self.assertFalse(any(method == 'POST' and path.startswith(hosting.SITE_PATH+'/releases') for method, path, *_ in api.calls))
        self.assertFalse(any('firestore' in path or 'identitytoolkit' in path or 'iam' in path for _, path, *_ in api.calls))
        self.assertTrue((self.output.parent/'itch-wrapper.zip').is_file())
        self.assertEqual(hosting.digest(self.package/'firebase-variant-manifest.json'), self.hash, 'reviewed input packet is immutable')
        self.assertNotIn(hosting.FIXTURE_ORIGIN, (self.output.parent/'preview-bound-package/itch-wrapper/index.html').read_text())
        self.assertNotIn('/firestore.rules', api.files)

    def test_api_gate_refuses_live_arbitrary_channels_delete_and_auth(self):
        api = PreviewFakeAPI();gate = hosting.PreviewAPI(api)
        for method, path in [('POST',hosting.SITE_PATH+'/releases?versionName='+NEW),
                             ('POST',hosting.SITE_PATH+'/channels/live/releases?versionName='+NEW),
                             ('POST',hosting.SITE_PATH+'/channels/other/releases?versionName='+NEW),
                             ('DELETE',hosting.PREVIEW_PATH), ('POST','https://identitytoolkit.googleapis.com/v1/projects')]:
            with self.subTest(path=path), self.assertRaises(ValueError):gate.request(method, path, {})
        self.assertEqual(api.calls, [])

    def test_packet_corruption_wrong_source_and_frame_policy_stop_before_network(self):
        api = PreviewFakeAPI()
        with self.assertRaises(ValueError):hosting.deploy_preview(self.package, 'c'*40, self.hash, self.output, api, lambda *_:True)
        self.assertEqual(api.calls, [])
        self.manifest['ancestor_origins'] = ['https://evil.invalid'];self.write_manifest()
        with self.assertRaises(ValueError):self.deploy(api)
        self.assertEqual(api.calls, [])

    def test_existing_channel_and_wrong_server_origin_or_expiry_stop_before_upload(self):
        for failure in ['existing-channel', 'wrong-origin', 'wrong-expiry']:
            self.output = self.root / failure / 'deployment.json';api = PreviewFakeAPI(failure)
            with self.subTest(failure=failure), self.assertRaises(ValueError):self.deploy(api)
            self.assertFalse(any(path == hosting.SITE_PATH+'/versions' for _, path, *_ in api.calls))

    def test_uncertain_release_and_failed_smoke_never_retry_rollback_or_delete(self):
        for failure in ['preview-release', 'smoke']:
            self.output = self.root / failure / 'deployment.json';api = PreviewFakeAPI(failure)
            with self.subTest(failure=failure), self.assertRaises(RuntimeError):self.deploy(api, smoke=failure!='smoke')
            self.assertEqual(sum(path.startswith(hosting.PREVIEW_PATH+'/releases?') for _, path, *_ in api.calls), 1)
            self.assertFalse(any(method == 'DELETE' or (method == 'POST' and path.startswith(hosting.SITE_PATH+'/releases')) for method, path, *_ in api.calls))

    def test_existing_receipt_is_not_overwritten_or_retried(self):
        self.output.parent.mkdir();self.output.write_text('retain uncertain result');api = PreviewFakeAPI()
        with self.assertRaises(ValueError):self.deploy(api)
        self.assertEqual(api.calls, []);self.assertEqual(self.output.read_text(), 'retain uncertain result')


if __name__ == '__main__':
    unittest.main()
