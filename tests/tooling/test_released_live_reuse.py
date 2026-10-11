"""Offline adversarial exact-source manual reuse; no account or network access."""
import copy
import base64
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from qualification.artifacts import sha256
import build_firebase
import deploy_firebase_hosting as hosting
import released_live_provenance as live
import stage_released_firebase as staging
from tests.tooling import test_stage_released_firebase as fixtures
from tests.tooling.test_firebase_hosting_deploy import FakeAPI

SOURCE = 'a' * 40
TREE = 'b' * 40


class ManualReuseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name); self.root = Path(__file__).resolve().parents[2]
        self.reuse = self.folder / 'reuse'; web = self.reuse / 'web'; web.mkdir(parents=True)
        html = (self.root / 'platform/web/little_leaf_shell.html').read_text().replace('$GODOT_URL', 'index.js')
        (web / 'index.html').write_text(html)
        for name, data in [('index.js', b'fixture'), ('index.wasm', b'\0asmfixture'), ('index.pck', b'GDPCfixture')]:
            (web / name).write_bytes(data)
        self.evidence = self.folder / 'ordinary'; (self.evidence / 'engine-evidence').mkdir(parents=True)
        native = self.evidence / 'engine-evidence/summary.json'
        native.write_text(json.dumps({'source_commit': SOURCE, 'status': 'passed', 'player_save_used': False,
            'total_checks': 10, 'test_processes': 2}))
        self.base = {'schema_version': 1, 'source_commit': SOURCE, 'source_tree': TREE,
            'version': '0.1.11-pre.aaaaaaaa', 'tag': '', 'workflow_run': '20', 'workflow_attempt': '1',
            'test_report_sha256': sha256(native), 'packed_smoke': 'passed', 'engine_checks': 10,
            'test_processes': 2, 'toolchain_verification': 'checksum-pinned-official-archives',
            'production_sha256': {name: sha256(staging.source_path(self.root, name)) for name in staging.FULLFLOW_SOURCES},
            'files': {p.name: {'bytes': p.stat().st_size, 'sha256': sha256(p)} for p in web.iterdir()}}
        original = self.reuse / 'main-release-manifest.json'; original.write_text(json.dumps(self.base, indent=2) + '\n')
        qualification = {'schema_version': 1, 'repository': live.REPOSITORY, 'workflow': '.github/workflows/ci.yml',
            'qualification_run_id': 20, 'qualification_attempt': 1, 'artifact_id': 30,
            'artifact_digest': 'sha256:' + 'c' * 64, 'qualified_manifest_sha256': sha256(original),
            'source_commit': SOURCE, 'source_tree': TREE, 'version': self.base['version'], 'tag': '',
            'mandatory_gate_success': True, 'packed_startup': 'passed', 'qualified_payload_unchanged': True}
        self.base['release_reuse'] = qualification
        (web / 'release-manifest.json').write_text(json.dumps(self.base, indent=2) + '\n')
        (self.reuse / 'qualification.json').write_text(json.dumps(qualification))
        (self.evidence / 'reuse-inputs.json').write_text(json.dumps({'qualification': qualification,
            'original_native_summary_sha256': sha256(native), 'new_engine_suite_run': False}))
        export_dir = self.evidence / 'web-build/evidence'; export_dir.mkdir(parents=True)
        (export_dir / 'export-report.json').write_text(json.dumps({'manifest': json.loads(original.read_text()),
            'stages': [{'stage': 'export', 'exit_code': 0}]}))
        for name, (relative, key, expected) in build_firebase.BROWSER_GATES.items():
            if name != 'firebase-fullflow':
                path = export_dir / relative; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps({key: expected}))
        self.focused = self.folder / 'focused'; self.focused.mkdir()
        fixtures.ReleasedStagingTests().fixtures(self.focused)
        self.fullflow = self.folder / 'fullflow'; self.fullflow.mkdir()
        flow = {'passed': True, 'source_commit': SOURCE, 'source_tree': TREE,
            'export_manifest_sha256': sha256(web / 'release-manifest.json'), 'native_report_sha256': sha256(native),
            'real_compiled_ui': True, 'real_firestore_rules': True, 'synthetic_only': True, 'browser_sandbox': True,
            'real_google_sign_in': False, 'diagnostic_only': False, 'checks': ['synthetic fixture'],
            'source_sha256': {name: sha256(staging.source_path(self.root, name)) for name in staging.FULLFLOW_SOURCES}}
        (self.fullflow / 'firebase-fullflow.json').write_text(json.dumps(flow))
        publication = {'source_commit': SOURCE, 'version': self.base['version'], 'tag': 'v' + self.base['version'],
            'target': live.TARGET, 'state': 'completed', 'workflow_run': 40, 'workflow_attempt': '1',
            'itch_build_id': 50, 'itch_channel_version': 60, 'qualification': {**qualification, 'tag': 'v' + self.base['version']}}
        self.selection = {'status': 'qualified-release-selected-staging-only', 'source_commit': SOURCE,
            'source_tree': TREE, 'qualification': publication['qualification'], 'publication': publication,
            'release_run_id': 40, 'release_tag': publication['tag']}
        coordinator_sha = subprocess.check_output(['git','-C',str(self.root),'rev-parse','HEAD'],text=True).strip()
        self.environment = {'GITHUB_REPOSITORY': live.REPOSITORY, 'GITHUB_EVENT_NAME': 'workflow_dispatch',
            'GITHUB_REF': 'refs/heads/main', 'GITHUB_SHA': coordinator_sha, 'GITHUB_WORKFLOW': 'Stage Firebase preview',
            'GITHUB_RUN_ID': '10', 'GITHUB_RUN_ATTEMPT': '1'}
        self.output = self.folder / 'variant'
        self.origin = {'run': {'id': 10, 'run_attempt': 1, 'repository': {'full_name': live.REPOSITORY},
            'head_repository': {'full_name': live.REPOSITORY}, 'path': live.WORKFLOW, 'event': 'workflow_dispatch',
            'status': 'completed', 'conclusion': 'success', 'head_branch': 'main', 'head_sha': coordinator_sha},
            'artifact': {'id': 70, 'name': 'little-leaf-firebase-' + SOURCE + '-1', 'expired': False,
            'workflow_run': {'id': 10, 'head_sha': coordinator_sha}, 'digest': 'sha256:' + 'f' * 64}}

    def stage(self, manual=True):
        with patch.object(staging, 'source_identity'), patch.dict(os.environ, self.environment):
            result = staging.stage(self.root, self.reuse, self.selection, self.evidence, self.focused,
                self.fullflow, self.output, 10, 1, manual_live=manual)
        if manual:
            manifest = self.manifest(); proof = manifest['qualified_release_reuse']; packet = manifest['manual_live_reuse']
            self.origin.update(coordinator_source_tree=proof['coordinator_source_tree'],
                coordinator_sha256=proof['coordinator_sha256'], released_transformer_sha256=proof['released_transformer_sha256'],
                public_config_sha256=packet['public_config_sha256'], compiled_source_sha256=packet['compiled_source_sha256'],
                source_is_coordinator_ancestor=True,
                publication_and_qualification={'qualification_run_id': 20, 'qualification_attempt': 1,
                    'artifact_id': 30, 'artifact_digest': 'sha256:' + 'c' * 64, 'release_run_id': 40,
                    'release_attempt': 1, 'source_commit': SOURCE, 'release_tag': self.selection['release_tag']})
        return result

    def manifest(self):
        return json.loads((self.output / 'firebase-variant-manifest.json').read_text())

    def rewrite(self, manifest):
        path = self.output / 'firebase-variant-manifest.json'
        manifest['files'] = {p.relative_to(self.output).as_posix(): sha256(p) for p in self.output.rglob('*')
            if p.is_file() and p != path}
        path.write_text(json.dumps(manifest)); return sha256(path)

    def verify(self, digest=None, origin=None):
        return hosting.verify_live_package(self.output, SOURCE,
            digest or sha256(self.output / 'firebase-variant-manifest.json'), staging_origin=origin or self.origin)

    def test_real_manual_stage_chain_reuses_all_runtime_and_separate_contract(self):
        result = self.stage(); manifest, _ = self.verify(result['manifest_sha256'])
        self.assertEqual(manifest['status'], live.STATUS)
        self.assertFalse(manifest['qualified_release_reuse']['live_activation_allowed'])
        self.assertFalse(manifest['live_activation_allowed'])
        self.assertEqual(manifest['manual_live_reuse']['runtime_sha256'],
            {name: sha256(self.reuse / 'web' / name) for name in live.RUNTIME})

    def test_automatic_packet_and_relabelled_automatic_remain_refused(self):
        self.stage(False); manifest = self.manifest()
        with self.assertRaises(ValueError): self.verify()
        manifest['status'] = 'staged-not-published'
        with self.assertRaises(ValueError): self.verify(self.rewrite(manifest))
        manifest['status'] = live.STATUS
        with self.assertRaises((ValueError, FileNotFoundError)): self.verify(self.rewrite(manifest))

    def test_manual_context_rejects_pr_invalid_coordinator_ref_and_rerun_before_output(self):
        for key, value in [('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_SHA', 'invalid'),
                           ('GITHUB_REF', 'refs/heads/candidate'), ('GITHUB_RUN_ATTEMPT', '2')]:
            with self.subTest(key=key), patch.dict(os.environ, {**self.environment, key: value}, clear=True), self.assertRaises(ValueError):
                live.manual_context(self.selection, os.environ, 10, 1)
        self.assertFalse(self.output.exists())
        self.selection['publication']['itch_channel_version'] = None
        with self.assertRaises(ValueError): self.stage()
        self.assertFalse(self.output.exists())

    def test_missing_and_stale_authenticated_origin_refused(self):
        self.stage()
        with self.assertRaises(ValueError): hosting.verify_live_package(self.output, SOURCE, sha256(self.output/'firebase-variant-manifest.json'))
        for section, key, value in [('run', 'event', 'workflow_run'), ('run', 'conclusion', 'failure'),
            ('run', 'head_sha', 'c' * 40), ('run', 'run_attempt', 2), ('artifact', 'expired', True),
            ('artifact', 'digest', ''), ('artifact', 'name', 'wrong')]:
            origin = copy.deepcopy(self.origin); origin[section][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.verify(origin=origin)

    def test_missing_browser_receipt_unqualified_receipt_and_preview_flags_refused(self):
        self.stage(); original = self.manifest()
        path = self.output/'evidence/original-browser/tutorial.json'; saved = path.read_bytes(); path.unlink()
        with self.assertRaises((ValueError, FileNotFoundError)): self.verify(self.rewrite(copy.deepcopy(original)))
        path.write_bytes(saved)
        altered = copy.deepcopy(original); altered['manual_live_reuse']['qualification']['mandatory_gate_success'] = False
        receipt = self.output/'evidence/manual-live-reuse.json'; before = receipt.read_text()
        receipt.write_text(json.dumps(altered['manual_live_reuse']))
        with self.assertRaises(ValueError): self.verify(self.rewrite(altered))
        receipt.write_text(before)
        altered = copy.deepcopy(original); altered['production_release_eligible'] = False
        with self.assertRaises(ValueError): self.verify(self.rewrite(altered))
        self.rewrite(original)

    def api(self):
        from qualification.reuse_main_ci import REQUIRED_JOBS
        test = self
        class API:
            def __init__(self): self.change = None; self.calls = []; self.release_attempt = 1
            def read(self, path):
                self.calls.append(path)
                if path == 'actions/runs/10': value = copy.deepcopy(test.origin['run'])
                elif path == 'actions/artifacts/70': value = copy.deepcopy(test.origin['artifact'])
                elif path.startswith('compare/'):
                    value = {'status': 'ahead'}
                elif path.startswith('git/commits/'):
                    value = {'tree': {'sha': test.origin['coordinator_source_tree']}}
                elif path.startswith('git/ref/tags/'):
                    value = {'object': {'type': 'commit', 'sha': SOURCE}}
                elif path == 'actions/runs/20':
                    value = {**test.origin['run'], 'id': 20, 'head_sha': SOURCE, 'path': '.github/workflows/ci.yml', 'event': 'push'}
                elif path == 'actions/artifacts/30':
                    value = {'id': 30, 'expired': False, 'digest': 'sha256:'+'c'*64,
                        'name': 'little-leaf-web-'+SOURCE+'-1', 'workflow_run': {'id': 20, 'head_sha': SOURCE}}
                elif path == 'actions/runs/40':
                    value = {**test.origin['run'], 'id': 40, 'head_sha': SOURCE, 'head_branch': test.selection['release_tag'],
                        'path': '.github/workflows/release-itch.yml', 'event': 'push', 'run_attempt': self.release_attempt}
                elif path.startswith('contents/'):
                    name = path[9:].split('?ref=')[0]
                    value = {'encoding': 'base64', 'content': base64.b64encode((test.root/name).read_bytes()).decode()}
                else: raise AssertionError(path)
                if self.change and self.change[0] == path: value[self.change[1]] = self.change[2]
                return value
            def pages(self, path, key):
                if path.startswith('actions/runs/20/'):
                    rows = [{'name': name, 'status': 'completed', 'conclusion': 'success'} for name in REQUIRED_JOBS]
                    if self.change and self.change[0] == 'main-jobs': rows[0]['conclusion'] = 'failure'
                    return rows
                return [{'name': 'publish', 'run_id': 40, 'run_attempt': self.release_attempt, 'status': 'completed', 'conclusion': 'success'}]
        return API()

    def test_fresh_api_authenticates_dual_identity_and_rejects_changed_history_source_or_gates(self):
        self.stage(); manifest = self.manifest(); api = self.api()
        self.assertNotEqual(manifest['source_commit'], self.origin['run']['head_sha'])
        authenticated = live.authenticate_origin(api, manifest, {'run': self.origin['run'], 'artifact': self.origin['artifact']})
        live.validate_origin(manifest, authenticated)
        for change in [('compare/'+SOURCE+'...'+self.environment['GITHUB_SHA'], 'status', 'behind'),
            ('actions/runs/20', 'run_attempt', 2), ('actions/runs/40', 'conclusion', 'failure'),
            ('actions/artifacts/30', 'expired', True), ('main-jobs', '', '')]:
            api = self.api(); api.change = change
            with self.subTest(change=change), self.assertRaises(ValueError):
                live.authenticate_origin(api, manifest, {'run': self.origin['run'], 'artifact': self.origin['artifact']})
        manifest['qualified_release_reuse']['coordinator_sha256']['tools/stage_released_firebase.py'] = '0'*64
        with self.assertRaises(ValueError): live.authenticate_origin(self.api(), manifest, {'run': self.origin['run'], 'artifact': self.origin['artifact']})

    def test_publisher_string_attempt_matches_exact_api_attempt_and_rejects_bad_receipts(self):
        self.selection['publication']['workflow_attempt'] = '3'
        self.stage(); manifest = self.manifest(); api = self.api(); api.release_attempt = 3
        origin = {'run': self.origin['run'], 'artifact': self.origin['artifact']}
        authenticated = live.authenticate_origin(api, manifest, origin)
        self.assertEqual(authenticated['publication_and_qualification']['release_attempt'], 3)
        live.validate_origin(manifest, authenticated)
        for value in [3, '3']:
            valid = copy.deepcopy(manifest); valid['manual_live_reuse']['publication']['workflow_attempt'] = value
            live.authenticate_origin(api, valid, origin)
            live.validate_origin(valid, authenticated)
        for value in [None, True, False, 0, -1, 3.0, '', '0', '-3', '03', '+3',
                      ' 3', '3 ', '3.0', '3e0', '٣', {}, [], 2, '2']:
            invalid = copy.deepcopy(manifest); invalid['manual_live_reuse']['publication']['workflow_attempt'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                live.authenticate_origin(api, invalid, origin)
            with self.subTest(origin_value=value), self.assertRaises(ValueError):
                live.validate_origin(invalid, authenticated)
        missing = copy.deepcopy(manifest); del missing['manual_live_reuse']['publication']['workflow_attempt']
        with self.assertRaises(ValueError): live.authenticate_origin(api, missing, origin)
        with self.assertRaises(ValueError): live.validate_origin(missing, authenticated)
        for value in [None, True, False, 0, -1, '3', 3.0]:
            api.change = ('actions/runs/40', 'run_attempt', value)
            with self.subTest(api_value=value), self.assertRaises(ValueError):
                live.authenticate_origin(api, manifest, origin)

    def test_authenticated_origin_attempt_remains_an_exact_api_integer(self):
        self.stage(); manifest = self.manifest()
        for value in [None, True, False, 0, -1, '1', 1.0, 2]:
            origin = copy.deepcopy(self.origin)
            origin['publication_and_qualification']['release_attempt'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                live.validate_origin(manifest, origin)

    def test_rehashed_changed_native_browser_focus_flow_and_runtime_refused(self):
        self.stage(); original = self.manifest()
        for relative in ['evidence/base-native-summary.json', 'evidence/base-web-manifest.json',
            'evidence/original-browser/tutorial.json', 'evidence/rules.log', 'evidence/firebase-fullflow.json', 'public/index.wasm']:
            path = self.output / relative; before = path.read_bytes(); path.write_bytes(before + b' ')
            with self.subTest(relative=relative), self.assertRaises(ValueError): self.verify(self.rewrite(copy.deepcopy(original)))
            path.write_bytes(before)
        self.rewrite(original)

    def test_forged_rehashed_focused_and_compiled_receipts_refused(self):
        self.stage(); original = self.manifest()
        for relative, key, value in [('rules.log.json', 'status', 'failed'),
            ('session.log.json', 'workflow_attempt', '2'), ('firebase-fullflow.json', 'real_compiled_ui', False),
            ('firebase-fullflow.json', 'source_commit', 'd' * 40)]:
            path = self.output / 'evidence' / relative; before = path.read_text()
            data = json.loads(before); data[key] = value; path.write_text(json.dumps(data))
            with self.subTest(key=key), self.assertRaises(ValueError): self.verify(self.rewrite(copy.deepcopy(original)))
            path.write_text(before)
        self.rewrite(original)

    def test_rehashed_inline_marker_config_and_adapter_refused_before_network(self):
        self.stage(); original = self.manifest()
        for relative, old, new in [('public/index.html', 'window.__littleLeafRelease=', 'window.stale='),
            ('public/index.html', 'little-leaf-41e5d.firebaseapp.com', 'wrong.firebaseapp.com'),
            ('public/little_leaf_firebase.js', "'use strict'", "'changed'")]:
            path = self.output / relative; before = path.read_text(); self.assertIn(old, before)
            path.write_text(before.replace(old, new)); digest = self.rewrite(copy.deepcopy(original)); api = FakeAPI()
            with self.subTest(relative=relative), self.assertRaises(ValueError):
                hosting.deploy(self.output, SOURCE, digest, self.folder/'receipt.json', api, lambda _: True, staging_origin=self.origin)
            self.assertEqual(api.calls, []); path.write_text(before)
        self.rewrite(original)

    def test_workflow_mode_skips_fresh_matrix_preserves_permissions_and_distinct_gates(self):
        workflow = (self.root/'.github/workflows/stage-firebase.yml').read_text()
        self.assertIn('!inputs.released_live_run_id', workflow.split('  fresh:', 1)[1].split('  released:', 1)[0])
        self.assertIn('--manual-live', workflow); self.assertIn('manual_context(selection', workflow)
        self.assertIn('fullflow.test.mjs', workflow); self.assertIn('rules.log', workflow)
        self.assertNotIn('id-token:', workflow); self.assertNotIn('google-github-actions/auth', workflow)
        deploy = (self.root/'.github/workflows/deploy-firebase.yml').read_text()
        self.assertIn('--staging-origin', deploy)


if __name__ == '__main__': unittest.main()
