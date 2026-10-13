"""Offline mocked Hosting protocol and credential-boundary checks; no deployment."""
import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit
from release import deploy_firebase_hosting as hosting

SHA = 'a' * 40
TREE = 'b' * 40
OLD = hosting.SITE_PATH + '/versions/old'
NEW = hosting.SITE_PATH + '/versions/new'


class FakeAPI:
    def __init__(self, fail=None, existing=OLD):
        self.head = existing
        self.fail = fail
        self.calls = []
        self.finalized = False
        self.releases = 0
        self.release_name = hosting.SITE_PATH + "/releases/original"
        self.config = {'headers': [{'glob': '/**', 'headers': {'Content-Security-Policy': "frame-ancestors 'none'"}}],
                       'rewrites': [{'glob': '/game/**', 'path': '/index.html'}], 'futureField': {'retained': True}}
        self.created_config = None

    def request(self, method, path, data=None, upload=False):
        self.calls.append((method, path, data, upload))
        if method == 'GET':
            if '/versions/' in path:
                return {'name': path, 'status': 'FINALIZED',
                        'config': self.created_config if path == NEW else self.config}
            head = hosting.SITE_PATH + '/versions/intervening' if self.fail == 'concurrent' and self.finalized else self.head
            return {'releases': [{'name': hosting.SITE_PATH + '/releases/intervening' if self.fail == 'concurrent-same-version' and self.finalized else self.release_name, 'version': {'name': head}}]} if head else {'releases': []}
        if path == hosting.SITE_PATH + '/versions':
            self.created_config = data['config']
            return {'name': NEW, 'status': 'CREATED'}
        if ':populateFiles' in path:
            self.files = data['files']
            return {'uploadUrl': 'https://evil.invalid/upload' if self.fail == 'upload-url' else 'https://upload-firebasehosting.googleapis.com/upload/' + NEW + '/files',
                    'uploadRequiredHashes': list(set(self.files.values()))}
        if upload:
            if self.fail == 'upload': raise RuntimeError('simulated upload uncertainty')
            assert hashlib.sha256(data).hexdigest() == path.rsplit('/', 1)[1]
            gzip.decompress(data)
            return {}
        if method == 'PATCH':
            self.finalized = True
            return {'name': NEW, 'status': 'CREATED' if self.fail == 'finalize' else 'FINALIZED'}
        if '/releases?' in path:
            if self.fail == 'release': raise RuntimeError('simulated release uncertainty')
            self.head = parse_qs(urlsplit(path).query)['versionName'][0]
            self.releases += 1
            self.release_name = hosting.SITE_PATH + '/releases/r' + str(self.releases)
            return {'name': self.release_name, 'type': 'DEPLOY',
                    'version': {'name': self.head, 'status': 'FINALIZED'}}
        raise AssertionError('unexpected API call')


class HostingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / 'variant';(self.package / 'public').mkdir(parents=True)
        for name in ['index.html','index.js','index.wasm','index.pck']:
            (self.package / 'public' / name).write_text(name)
        (self.package / 'public/index.html').write_text('<!doctype html><script src="index.js"></script>')
        self.marker = {'schema_version': 1, 'source_commit': SHA, 'source_tree': TREE,
                       'ci_run_id': 'local', 'base_web_manifest_sha256': 'c' * 64}
        (self.package / 'public/hosting-release.json').write_text(json.dumps(self.marker))
        # Sensitive configuration is outside public/ and must never be uploaded.
        (self.package / 'firestore.rules').write_text('fixture rules')
        self.base = {'source_commit': 'd'*40, 'source_tree': 'e'*40, 'test_report_sha256': 'f'*64,
            'packed_smoke': 'passed', 'engine_checks': 10, 'test_processes': 2, 'workflow_run': 'local',
            'toolchain_verification': 'local-tools-unverified-for-release',
            'files': {name: {'bytes': (self.package/'public'/name).stat().st_size, 'sha256': hosting.digest(self.package/'public'/name)} for name in ['index.js','index.wasm','index.pck']}}
        self.manifest = {'base_web_manifest': self.base, 'engine_reuse': {'source_commit': 'd'*40,
            'gameplay_godot_inputs_byte_identical': True, 'base_test_report_sha256': 'f'*64, 'native_checks': 10, 'native_processes': 2}, 'source_commit': SHA, 'source_tree': TREE,
            'status': 'prepared-local-test-artifact-not-deployed', 'base_web_manifest_sha256': 'c'*64,
            'canonical_game_url': hosting.ORIGIN,
            'files': {p.relative_to(self.package).as_posix(): hosting.digest(p) for p in self.package.rglob('*') if p.is_file()}}
        manifest_path = self.package / 'firebase-variant-manifest.json'
        manifest_path.write_text(json.dumps(self.manifest));self.hash = hosting.digest(manifest_path)
        self.output = self.root / 'receipt/deployment.json'

    def deploy(self, api, smoke=True):
        return hosting.deploy(self.package, SHA, self.hash, self.output, api, lambda expected: smoke)

    def test_static_test_deploy_does_not_claim_account_acceptance(self):
        api = FakeAPI();receipt = self.deploy(api)
        self.assertEqual(receipt['status'], 'published-pending-hosted-acceptance')
        self.assertEqual(receipt['previous_hosting_version'], OLD)
        self.assertEqual(api.head, NEW)
        self.assertEqual(receipt['hosted_acceptance'], 'not-yet-tested')
        self.assertNotIn('/firestore.rules', api.files)
        self.assertTrue(all(method != 'DELETE' for method, *_ in api.calls))
        self.assertFalse(any('firestore' in path or 'iam' in path for _, path, *_ in api.calls))
        self.assertEqual(api.created_config, api.config)
        self.assertEqual(receipt['preserved_hosting_config'], api.config)

    def test_corrupt_package_stops_before_any_network(self):
        (self.package / 'public/index.js').write_text('tampered')
        api = FakeAPI()
        with self.assertRaises(ValueError): self.deploy(api)
        self.assertEqual(api.calls, [])

    def rewrite_manifest(self):
        self.manifest['files'] = {p.relative_to(self.package).as_posix(): hosting.digest(p)
            for p in self.package.rglob('*') if p.is_file() and p.name != 'firebase-variant-manifest.json'}
        path = self.package / 'firebase-variant-manifest.json'
        path.write_text(json.dumps(self.manifest));self.hash = hosting.digest(path)

    def test_live_refuses_preview_and_diagnostic_identity_before_network(self):
        cases = [
            ('manifest', 'production_release_eligible', False),
            ('manifest', 'ancestor_origins', hosting.ANCESTORS),
            ('manifest', 'runtime_origin', hosting.FIXTURE_ORIGIN),
            ('marker', 'runtime_origin', hosting.FIXTURE_ORIGIN),
            ('marker', 'test_surface', 'trusted-itch-frame'),
            ('marker', 'diagnostic_only', True),
            ('marker', 'auth_verification_only', True),
            ('marker', 'game_start_allowed', False),
        ]
        for target, key, value in cases:
            record = self.manifest if target == 'manifest' else self.marker
            record[key] = value
            (self.package / 'public/hosting-release.json').write_text(json.dumps(self.marker))
            self.rewrite_manifest();api = FakeAPI()
            with self.subTest(target=target, key=key), self.assertRaises(ValueError):
                self.deploy(api)
            self.assertEqual(api.calls, [])
            self.assertFalse(self.output.exists())
            del record[key]

    def test_live_refuses_auth_only_html_even_with_retained_engine_files(self):
        for html in [
            '<!doctype html><p>Game and saves remain paused.</p>',
            '<!-- <script src="index.js"></script> -->',
            '<script src="index.js"></script><script>start({}, {"authVerificationOnly": true});</script>',
            "<script src='index.js'></script><script>start({}, {authVerificationOnly:true});</script>",
            '<script src="index.js"></script><script>start({}, {"surface":"trusted-itch-frame"});</script>',
        ]:
            (self.package / 'public/index.html').write_text(html)
            self.rewrite_manifest();api = FakeAPI()
            # Complete source/hash/binary provenance remains valid. Only live entry eligibility fails.
            hosting.verify_package(self.package, SHA, self.hash)
            with self.subTest(html=html), self.assertRaises(ValueError):self.deploy(api)
            self.assertEqual(api.calls, [])
            self.assertFalse(self.output.exists())

    def test_live_accepts_normal_entry_and_shared_boot_module(self):
        self.manifest['production_release_eligible'] = True
        self.manifest['runtime_origin'] = hosting.ORIGIN.rstrip('/')
        self.marker.update(diagnostic_only=False, auth_verification_only=False, game_start_allowed=True,
                           runtime_origin=hosting.ORIGIN)
        (self.package / 'public/hosting-release.json').write_text(json.dumps(self.marker))
        (self.package / 'public/little_leaf_firebase_boot.mjs').write_text('function verifyAuthOnly() { return new Promise(() => {}); }')
        (self.package / 'public/index.html').write_text("<script src='./index.js'></script><script>start({});</script>")
        self.rewrite_manifest()
        result = self.deploy(FakeAPI())
        self.assertEqual(result['status'], 'published-pending-hosted-acceptance')

    def test_wrong_manifest_or_source_refused(self):
        for sha, digest in [('d'*40,self.hash),(SHA,'d'*64)]:
            with self.assertRaises(ValueError):hosting.verify_package(self.package,sha,digest)

    def test_staging_failure_preserves_previous_and_does_not_retry(self):
        for failure in ['upload-url', 'upload', 'finalize', 'concurrent', 'concurrent-same-version']:
            api = FakeAPI(failure)
            with self.subTest(failure=failure),self.assertRaises((ValueError,RuntimeError)):self.deploy(api)
            self.assertEqual(api.releases, 0)
            self.assertEqual(api.head, OLD)
            self.assertEqual(sum(path == hosting.SITE_PATH + '/versions' for _,path,*_ in api.calls), 1)

    def test_uncertain_release_never_retries_or_blindly_rolls_back(self):
        api = FakeAPI('release')
        with self.assertRaises(RuntimeError):self.deploy(api)
        self.assertEqual(sum(method == 'POST' and '/releases?' in path for method,path,*_ in api.calls), 1)
        self.assertEqual(json.loads(self.output.read_text())['status'], 'release-outcome-pending')

    def test_failed_live_smoke_requires_inspection_without_automatic_rollback(self):
        api = FakeAPI()
        with self.assertRaises(RuntimeError):self.deploy(api, False)
        self.assertEqual(api.head, NEW)
        self.assertEqual(api.releases, 1)
        self.assertEqual(json.loads(self.output.read_text())['status'], 'smoke-failed-inspection-required')

    def test_failed_smoke_never_rolls_back_an_intervening_release(self):
        api = FakeAPI()
        intervening = hosting.SITE_PATH + '/versions/other'
        def smoke(expected):
            api.head = intervening
            return False
        with self.assertRaises(RuntimeError):
            hosting.deploy(self.package, SHA, self.hash, self.output, api, smoke)
        self.assertEqual(api.head, intervening)
        self.assertEqual(api.releases, 1)

    def test_failed_smoke_never_rolls_back_a_new_release_of_the_same_version(self):
        api = FakeAPI()
        def smoke(expected):
            api.release_name = hosting.SITE_PATH + '/releases/manual-republish'
            return False
        with self.assertRaises(RuntimeError):
            hosting.deploy(self.package, SHA, self.hash, self.output, api, smoke)
        self.assertEqual(api.head, NEW)
        self.assertEqual(api.releases, 1)

    def test_missing_base_or_engine_binary_relabel_refused_even_with_new_manifest_hash(self):
        for mutate in [lambda m: m.pop('base_web_manifest'),
                       lambda m: m['base_web_manifest']['files']['index.pck'].update(sha256='0'*64),
                       lambda m: m['engine_reuse'].update(gameplay_godot_inputs_byte_identical=False)]:
            manifest = json.loads((self.package/'firebase-variant-manifest.json').read_text())
            mutate(manifest)
            path = self.package/'firebase-variant-manifest.json';old=path.read_text();path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError): hosting.verify_package(self.package,SHA,hosting.digest(path))
            path.write_text(old)

    def test_first_deploy_failed_smoke_has_no_fake_rollback_or_delete(self):
        api = FakeAPI(existing=None)
        with self.assertRaises(ValueError):self.deploy(api, False)
        self.assertEqual(api.releases, 0)
        self.assertFalse(any(method == 'POST' for method, *_ in api.calls))

    def test_changed_candidate_config_stops_before_release(self):
        api = FakeAPI(); original = api.request
        def request(method, path, data=None, upload=False):
            result = original(method, path, data, upload)
            if method == 'GET' and path == NEW:
                result['config'] = {'different': True}
            return result
        api.request = request
        with self.assertRaises(RuntimeError): self.deploy(api)
        self.assertEqual(api.releases, 0)

    def test_configuration_type_change_is_not_equal_preservation(self):
        for target in [NEW, OLD]:
            api = FakeAPI(); original = api.request
            def request(method, path, data=None, upload=False):
                result = original(method, path, data, upload)
                if method == 'GET' and path == target and api.finalized:
                    import copy
                    result = copy.deepcopy(result)
                    result['config']['futureField']['retained'] = 1
                return result
            api.request = request
            with self.subTest(target=target), self.assertRaises(RuntimeError): self.deploy(api)
            self.assertEqual(api.releases, 0)

    def test_transport_refuses_arbitrary_credential_destinations(self):
        api = hosting.Transport('synthetic-token-not-a-credential')
        for path in ['https://upload-firebasehostingXgoogleapisXcom/upload/' + NEW + '/files/' + 'a'*64, 'https://evil.invalid/files/hash', 'https://upload-firebasehosting.googleapis.com/upload/sites/other/versions/x/files/' + 'a'*64]:
            with self.assertRaises(ValueError):api.request('POST', path, b'fixture', upload=True)
        with self.assertRaises(ValueError):api.request('GET', 'projects/other/iam')


class WorkflowTests(unittest.TestCase):
    def test_main_manual_selection_then_verify_before_short_lived_auth(self):
        root = Path(__file__).resolve().parents[2]
        text = (root / '.github/workflows/deploy-firebase.yml').read_text()
        self.assertIn("github.ref == 'refs/heads/main'", text)
        self.assertIn("github.event_name == 'workflow_dispatch'", text)
        self.assertIn('id-token: write', text)
        self.assertIn('contents: read', text)
        self.assertIn('actions: read', text)
        self.assertIn('access_token_scopes: https://www.googleapis.com/auth/firebase.hosting', text)
        self.assertIn('create_credentials_file: false', text)
        self.assertIn('digest-mismatch: error', text)
        self.assertIn('cancel-in-progress: false', text)
        self.assertLess(text.index('--verify-only'), text.index('uses: google-github-actions/auth@'))
        self.assertNotIn('credentials_json:', text)
        self.assertNotIn('firebase deploy', text)
        self.assertNotIn('secrets.', text)
        self.assertIn("run['head_repository']['full_name'] == repository", text)
        self.assertIn("artifact['workflow_run']['id'] == run['id']", text)

if __name__ == '__main__':unittest.main()
