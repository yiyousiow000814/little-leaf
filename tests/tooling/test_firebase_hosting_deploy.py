"""Offline mocked Hosting protocol and credential-boundary checks; no deployment."""
import copy
import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from urllib.parse import parse_qs, urlsplit
from release import deploy_firebase_hosting as hosting
from build import build_itch_trusted_preview as producer

SHA = 'a' * 40
TREE = 'b' * 40
OLD = hosting.SITE_PATH + '/versions/old'
NEW = hosting.SITE_PATH + '/versions/new'

PACKET_HEADERS = [
    {'source': '/itch/', 'headers': [
        {'key': 'Content-Security-Policy', 'value': hosting.FRAME_POLICY},
        {'key': 'Cache-Control', 'value': 'no-cache'}]},
    {'source': '/itch/index.html', 'headers': [
        {'key': 'Content-Security-Policy', 'value': hosting.FRAME_POLICY}]},
    {'source': '/itch/hosting-release.json', 'headers': [
        {'key': 'Cache-Control', 'value': 'no-store'}]},
]


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
        self.original_files = {path: hashlib.sha256(('old:' + path).encode()).hexdigest() for path in [
            '/index.html', '/hosting-release.json', '/index.js', '/index.wasm', '/index.pck',
            '/itch/index.html', '/itch/hosting-release.json', '/itch/runtime.wasm', '/retained.txt']}
        self.inventory_reads = {}
        self.paginated = False

    def request(self, method, path, data=None, upload=False):
        self.calls.append((method, path, data, upload))
        if method == 'GET':
            if '/files?' in path:
                version = path.split('/files?', 1)[0]
                query = parse_qs(urlsplit(path).query)
                assert query['status'] == ['ACTIVE'] and query['pageSize'] == ['1000']
                page = query.get('pageToken', [''])[0]
                if not page:
                    self.inventory_reads[version] = self.inventory_reads.get(version, 0) + 1
                values = dict(self.files if version == NEW else self.original_files)
                if self.fail == 'inventory-missing': return {}
                if self.fail == 'inventory-empty': return {'files': []}
                if self.fail == 'baseline-files-before-finalize' and version == OLD and self.inventory_reads[OLD] >= 2:
                    values['/retained.txt'] = 'f' * 64
                if self.fail == 'baseline-files-before-release' and version == OLD and self.inventory_reads[OLD] >= 3:
                    values['/retained.txt'] = 'f' * 64
                if self.fail == 'candidate-files' and version == NEW:
                    del values['/retained.txt']
                rows = [{'path': name, 'hash': value, 'status': 'ACTIVE'} for name, value in sorted(values.items())]
                if self.fail == 'inventory-invalid': rows[0]['hash'] = 'invalid'
                if self.fail == 'inventory-duplicate': rows.append(dict(rows[0]))
                if self.fail == 'candidate-mode' and version == NEW: rows[0]['status'] = 'DELETED'
                if self.paginated:
                    if not page: return {'files': rows[:2], 'nextPageToken': 'second'}
                    assert page == 'second'
                    return {'files': rows[2:]}
                return {'files': rows}
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
                    'uploadRequiredHashes': list(set(self.files.values()) - set(self.original_files.values())) +
                    ([self.original_files['/retained.txt']] if self.fail == 'retained-upload' else [])}
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

    def test_root_preserves_complete_paginated_baseline_and_existing_itch(self):
        api = FakeAPI();api.paginated = True
        receipt = self.deploy(api)
        root_paths = {'/' + path.relative_to(self.package / 'public').as_posix()
                      for path in (self.package / 'public').rglob('*') if path.is_file()}
        self.assertEqual(set(api.files), set(api.original_files) | root_paths)
        for path, value in api.original_files.items():
            if path not in root_paths:
                self.assertEqual(api.files[path], value)
        self.assertEqual(receipt['previous_files_sha256'], hosting.record_digest(api.original_files))
        self.assertEqual(receipt['candidate_files_sha256'], hosting.record_digest(api.files))
        self.assertEqual(receipt['previous_file_count'], len(api.original_files))
        self.assertEqual(receipt['candidate_file_count'], len(api.files))
        self.assertEqual(receipt['preserved_hosting_config_sha256'], hosting.record_digest(api.config))
        self.assertEqual(receipt['candidate_hosting_config_sha256'], hosting.record_digest(api.created_config))
        self.assertEqual(api.inventory_reads[OLD], 3)
        self.assertTrue(any('pageToken=second' in path for _, path, *_ in api.calls))
        uploaded = {path.rsplit('/', 1)[1] for _, path, _, upload in api.calls if upload}
        self.assertTrue(uploaded.isdisjoint(api.original_files.values()))

    def common_deploy(self, api, additions=None, smoke=None, expected_previous=None):
        manifest = {'status': hosting.COMMON_LIVE_STATUS,
                    'hosting_header_additions': copy.deepcopy(PACKET_HEADERS if additions is None else additions)}
        baseline = {'source_commit': 'd' * 40}
        with mock.patch.object(hosting, 'verify_live_package', return_value=(manifest, self.marker)), \
                mock.patch('release.common_firebase.current_marker', return_value=baseline):
            return hosting.deploy(self.package, SHA, self.hash, self.output, api, smoke or (lambda _: True),
                                  staging_origin={'live_baseline': baseline}, expected_previous=expected_previous)

    def recovery_baseline(self, api):
        return {'release': api.release_name, 'version': OLD, 'config_sha256': hosting.record_digest(api.config)}

    def test_owned_failed_smoke_restores_exact_previous_version_once_and_still_fails(self):
        api = FakeAPI(); expected = self.recovery_baseline(api)
        with mock.patch.object(hosting, 'live_smoke', return_value=True) as verify_old:
            with self.assertRaisesRegex(RuntimeError, 'Hosted marker verification failed'):
                self.common_deploy(api, smoke=lambda _: False, expected_previous=expected)
        self.assertEqual(api.head, OLD)
        self.assertEqual(api.releases, 2)
        verify_old.assert_called_once_with({'source_commit': 'd'*40})
        receipt = json.loads(self.output.read_text())
        self.assertEqual(receipt['rollback_status'], 'previous-version-restored')
        self.assertEqual(receipt['status'], 'restored-after-smoke-failure')
        self.assertFalse(any(method=='DELETE' for method,*_ in api.calls))

    def test_recovery_refuses_changed_release_even_if_candidate_version_is_same(self):
        api = FakeAPI(); expected = self.recovery_baseline(api)
        def fail_after_concurrent_release(_):
            api.release_name = hosting.SITE_PATH+'/releases/intervening'
            return False
        with self.assertRaisesRegex(RuntimeError, 'Hosted marker verification failed'):
            self.common_deploy(api, smoke=fail_after_concurrent_release, expected_previous=expected)
        self.assertEqual(api.head, NEW); self.assertEqual(api.releases, 1)
        self.assertEqual(json.loads(self.output.read_text())['rollback_status'], 'inspection-required')

    def test_recovery_refuses_mutated_previous_file_inventory(self):
        api = FakeAPI(); expected = self.recovery_baseline(api)
        def fail_after_old_map_changed(_):
            api.original_files['/retained.txt'] = 'f'*64
            return False
        with self.assertRaisesRegex(RuntimeError, 'Hosted marker verification failed'):
            self.common_deploy(api, smoke=fail_after_old_map_changed, expected_previous=expected)
        self.assertEqual(api.releases, 1)

    def test_uncertain_restore_uses_get_only_and_never_retransmits(self):
        api = FakeAPI(); expected = self.recovery_baseline(api); request = api.request
        def uncertain(method, path, data=None, upload=False):
            value = request(method, path, data, upload)
            if method=='POST' and '/releases?' in path and parse_qs(urlsplit(path).query)['versionName']==[OLD]:
                raise RuntimeError('simulated lost restore response')
            return value
        api.request = uncertain
        with self.assertRaisesRegex(RuntimeError, 'Hosted marker verification failed'):
            self.common_deploy(api, smoke=lambda _: False, expected_previous=expected)
        receipt = json.loads(self.output.read_text())
        self.assertEqual(api.head, OLD); self.assertEqual(api.releases, 2)
        self.assertEqual(receipt['rollback_observed_head']['version'], OLD)
        self.assertEqual(receipt['rollback_status'], 'inspection-required')

    def test_insufficient_restore_budget_stops_before_any_live_release(self):
        api = FakeAPI(); api.deadline = hosting.time.monotonic()+30
        with self.assertRaisesRegex(RuntimeError, 'Insufficient smoke/restore budget'):
            self.common_deploy(api, expected_previous=self.recovery_baseline(api))
        self.assertEqual(api.head, OLD); self.assertEqual(api.releases, 0)

    def test_approved_baseline_drift_stops_before_candidate_creation(self):
        api = FakeAPI(); expected = self.recovery_baseline(api); expected['config_sha256'] = 'e'*64
        with self.assertRaisesRegex(ValueError, 'Approved previous'):
            self.common_deploy(api, expected_previous=expected)
        self.assertFalse(any(method=='POST' for method,*_ in api.calls))

    def test_common_root_overlays_qualified_itch_and_exact_reviewed_headers(self):
        api = FakeAPI();api.paginated = True
        original_config = copy.deepcopy(api.config)
        (self.package / 'public/itch').mkdir()
        payload = b'new qualified same-page entry'
        (self.package / 'public/itch/index.html').write_bytes(payload)
        receipt = self.common_deploy(api)
        self.assertEqual(api.files['/itch/index.html'], hashlib.sha256(gzip.compress(payload, mtime=0)).hexdigest())
        self.assertEqual(api.files['/itch/runtime.wasm'], api.original_files['/itch/runtime.wasm'])
        self.assertEqual(api.files['/retained.txt'], api.original_files['/retained.txt'])
        self.assertEqual(api.created_config, {**original_config,
            'headers': original_config['headers'] + hosting.ITCH_HEADERS})
        self.assertEqual(api.config, original_config)
        self.assertEqual(receipt['approved_hosting_header_additions'], hosting.ITCH_HEADERS)
        self.assertEqual(receipt['preserved_hosting_config_sha256'], hosting.record_digest(original_config))
        self.assertEqual(receipt['candidate_hosting_config_sha256'], hosting.record_digest(api.created_config))
        self.assertNotIn('preserved_hosting_config', json.loads(self.output.read_text()))
        self.assertEqual(api.releases, 1)

    def test_common_header_merge_preserves_unmanaged_fields_without_duplicates(self):
        api = FakeAPI()
        retained_row = {'glob': '/itch/', 'headers': {'X-Retained': 'yes', 'Cache-Control': 'old'},
                        'futureField': {'keep': True}}
        api.config['headers'].append(copy.deepcopy(retained_row))
        self.common_deploy(api)
        rows = [row for row in api.created_config['headers'] if row.get('glob') == '/itch/']
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0], {**retained_row,
            'headers': {**retained_row['headers'], **hosting.ITCH_HEADERS[0]['headers']}})
        self.assertEqual(api.created_config['rewrites'], api.config['rewrites'])
        self.assertEqual(api.created_config['futureField'], api.config['futureField'])

    def test_common_unreviewed_headers_stop_before_hosting_api(self):
        cases = [[], PACKET_HEADERS + [{'source': '/**', 'headers': [{'key': 'X-Frame-Options', 'value': 'DENY'}]}]]
        changed = copy.deepcopy(PACKET_HEADERS)
        changed[0]['headers'][0]['value'] = 'frame-ancestors *'
        cases.append(changed)
        for additions in cases:
            api = FakeAPI()
            with self.subTest(additions=additions), self.assertRaises(ValueError):
                self.common_deploy(api, additions)
            self.assertEqual(api.calls, [])
            self.assertFalse(self.output.exists())

    def test_common_packet_header_projection_is_strict_before_any_network(self):
        cases = [None, {}, copy.deepcopy(hosting.ITCH_HEADERS)]
        duplicate_key = copy.deepcopy(PACKET_HEADERS)
        duplicate_key[0]['headers'].append(copy.deepcopy(duplicate_key[0]['headers'][0]))
        duplicate_source = copy.deepcopy(PACKET_HEADERS)
        duplicate_source[1] = copy.deepcopy(duplicate_source[0])
        extra_row_field = copy.deepcopy(PACKET_HEADERS)
        extra_row_field[0]['glob'] = '/itch/'
        extra_value_field = copy.deepcopy(PACKET_HEADERS)
        extra_value_field[0]['headers'][0]['extra'] = True
        non_string = copy.deepcopy(PACKET_HEADERS)
        non_string[0]['headers'][0]['value'] = ['frame-ancestors *']
        non_list = copy.deepcopy(PACKET_HEADERS)
        non_list[0]['headers'] = {'Content-Security-Policy': hosting.FRAME_POLICY}
        empty = copy.deepcopy(PACKET_HEADERS)
        empty[0]['headers'] = []
        cases.extend([duplicate_key, duplicate_source, extra_row_field, extra_value_field,
                      non_string, non_list, empty])
        for additions in cases:
            api = FakeAPI()
            manifest = {'status': hosting.COMMON_LIVE_STATUS, 'hosting_header_additions': additions}
            with self.subTest(additions=additions), \
                    mock.patch.object(hosting, 'verify_live_package', return_value=(manifest, self.marker)), \
                    self.assertRaises(ValueError):
                hosting.deploy(self.package, SHA, self.hash, self.output, api, lambda _: True)
            self.assertEqual(api.calls, [])
            self.assertFalse(self.output.exists())

    def test_common_accepts_actual_prepare_stable_header_output(self):
        build = self.root / 'producer-build'
        web = build / 'web';web.mkdir(parents=True)
        shell = (producer.ROOT / 'platform/web/little_leaf_shell.html').read_text().replace('$GODOT_URL', 'index.js')
        (web / 'index.html').write_text(shell)
        for name in ['index.js', 'index.wasm', 'index.pck']:
            (web / name).write_bytes(b'synthetic engine fixture')
        base = {'source_commit': SHA, 'source_tree': TREE, 'workflow_run': '1', 'version': 'synthetic',
                'packed_smoke': 'passed', 'engine_checks': 1, 'test_processes': 1,
                'production_sha256': {'project.godot': hosting.digest(producer.ROOT / 'game/project.godot')},
                'files': {p.name: {'sha256': hosting.digest(p), 'bytes': p.stat().st_size} for p in web.iterdir()}}
        (web / 'release-manifest.json').write_text(json.dumps(base))
        public_config = json.loads((producer.ROOT / 'platform/firebase/public-config.json').read_text())
        self.package = self.root / 'producer-output'
        manifest = producer.prepare_stable(build, self.package, public_config, SHA, TREE)
        proposed = copy.deepcopy(manifest['hosting_header_additions'])
        self.assertEqual(proposed, PACKET_HEADERS)
        self.assertFalse(manifest['production_release_eligible'])
        api = FakeAPI();api.paginated = True
        receipt = self.common_deploy(api, manifest['hosting_header_additions'])
        self.assertEqual(api.created_config['headers'], api.config['headers'] + hosting.ITCH_HEADERS)
        self.assertEqual(receipt['approved_hosting_header_additions'], hosting.ITCH_HEADERS)
        self.assertEqual(manifest['hosting_header_additions'], proposed)
        for path, value in api.original_files.items():
            if not (self.package / 'public' / path.lstrip('/')).is_file():
                self.assertEqual(api.files[path], value)
        self.assertEqual(api.releases, 1)

    def test_ambiguous_managed_header_rows_stop_before_version_creation(self):
        api = FakeAPI()
        api.config['headers'] += [copy.deepcopy(hosting.ITCH_HEADERS[0]), copy.deepcopy(hosting.ITCH_HEADERS[0])]
        with self.assertRaises(ValueError):
            self.common_deploy(api)
        self.assertFalse(any(method == 'POST' for method, *_ in api.calls))

    def test_missing_invalid_or_duplicate_inventory_stops_before_mutation(self):
        for failure in ['inventory-missing', 'inventory-empty', 'inventory-invalid', 'inventory-duplicate']:
            api = FakeAPI(failure)
            with self.subTest(failure=failure), self.assertRaises(ValueError):
                self.deploy(api)
            self.assertFalse(any(method == 'POST' for method, *_ in api.calls))

    def test_baseline_inventory_drift_stops_before_finalize(self):
        api = FakeAPI('baseline-files-before-finalize')
        with self.assertRaises(RuntimeError):
            self.deploy(api)
        self.assertFalse(any(method == 'PATCH' for method, *_ in api.calls))
        self.assertEqual(api.releases, 0)
        self.assertEqual(api.head, OLD)

    def test_baseline_inventory_drift_after_finalize_stops_before_release(self):
        api = FakeAPI('baseline-files-before-release')
        with self.assertRaises(RuntimeError):
            self.deploy(api)
        self.assertTrue(api.finalized)
        self.assertEqual(api.releases, 0)
        self.assertEqual(api.head, OLD)

    def test_candidate_inventory_or_mode_mismatch_stops_before_release(self):
        for failure in ['candidate-files', 'candidate-mode']:
            api = FakeAPI(failure)
            with self.subTest(failure=failure), self.assertRaises((ValueError, RuntimeError)):
                self.deploy(api)
            self.assertTrue(api.finalized)
            self.assertEqual(api.releases, 0)

    def test_configuration_drift_stops_before_finalize(self):
        api = FakeAPI();original = api.request;reads = 0
        def request(method, path, data=None, upload=False):
            nonlocal reads
            result = original(method, path, data, upload)
            if method == 'GET' and path == OLD:
                reads += 1
                if reads >= 2:
                    result = copy.deepcopy(result)
                    result['config']['futureField']['retained'] = 1
            return result
        api.request = request
        with self.assertRaises(RuntimeError):
            self.deploy(api)
        self.assertFalse(any(method == 'PATCH' for method, *_ in api.calls))
        self.assertEqual(api.releases, 0)

    def test_retained_hash_upload_request_stops_without_fetch_or_release(self):
        api = FakeAPI('retained-upload')
        with self.assertRaises(ValueError):
            self.deploy(api)
        self.assertFalse(any(upload for _, _, _, upload in api.calls))
        self.assertFalse(any(method == 'PATCH' for method, *_ in api.calls))
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
