"""Source/attempt fences and production-deploy separation for released staging."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import stage_released_firebase as staging
from artifacts import sha256
from deploy_firebase_hosting import verify_package


class ReleasedStagingTests(unittest.TestCase):
    def fixtures(self, folder):
        for name in staging.build_firebase.FOCUSED_LOGS:
            log = folder / name
            log.write_text('passed synthetic fixture\n')
            (folder / (name + '.json')).write_text(json.dumps({'schema_version': 1, 'status': 'passed',
                'exit_code': 0, 'command': staging.COMMANDS[name], 'source_commit': 'a' * 40,
                'source_tree': 'b' * 40, 'workflow_run': '10', 'workflow_attempt': '1',
                'log_sha256': sha256(log)}))

    def test_all_focused_gates_required_at_exact_source_and_attempt(self):
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d); self.fixtures(folder)
            self.assertEqual(len(staging.validate_focused(folder, folder, 'a' * 40, 'b' * 40, 10, 1)), 20)
            with self.assertRaises(ValueError): staging.validate_focused(folder, folder, 'a' * 40, 'b' * 40, 10, 2)
            with self.assertRaises(ValueError): staging.validate_focused(folder, folder, 'c' * 40, 'b' * 40, 10, 1)

    def test_failed_missing_or_mutated_focused_receipt_is_rejected(self):
        for mode in ['failed', 'mutated', 'missing']:
            with tempfile.TemporaryDirectory() as d:
                folder = Path(d); self.fixtures(folder)
                log = folder / 'rules.log'
                if mode == 'missing': log.unlink()
                elif mode == 'mutated': log.write_text('changed')
                else:
                    receipt = folder / 'rules.log.json'
                    data = json.loads(receipt.read_text()); data['exit_code'] = 1
                    receipt.write_text(json.dumps(data))
                with self.subTest(mode=mode), self.assertRaises(ValueError):
                    staging.validate_focused(folder, folder, 'a' * 40, 'b' * 40, 10, 1)

    def test_complete_synthetic_stage_preserves_runtime_and_remains_undeployable(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d)
            reuse = folder / 'reuse'; web = reuse / 'web'; web.mkdir(parents=True)
            html = (root / 'platform/web/little_leaf_shell.html').read_text().replace('$GODOT_URL', 'index.js')
            (web / 'index.html').write_text(html)
            for name, data in [('index.js', b'fixture'), ('index.wasm', b'\0asmfixture'), ('index.pck', b'GDPCfixture')]:
                (web / name).write_bytes(data)
            evidence = folder / 'evidence'; (evidence / 'engine-evidence').mkdir(parents=True)
            native = evidence / 'engine-evidence/summary.json'
            native.write_text(json.dumps({'source_commit': 'a' * 40, 'status': 'passed', 'player_save_used': False}))
            qualification = {'qualification_run_id': 20, 'qualification_attempt': 1, 'artifact_id': 30,
                'artifact_digest': 'sha256:' + 'c' * 64, 'qualified_manifest_sha256': 'd' * 64,
                'source_commit': 'a' * 40, 'source_tree': 'b' * 40, 'version': '0.1.10c'}
            base = {'source_commit': 'a' * 40, 'source_tree': 'b' * 40, 'version': '0.1.10c',
                'workflow_run': '20', 'test_report_sha256': sha256(native), 'release_reuse': qualification,
                'files': {p.name: {'bytes': p.stat().st_size, 'sha256': sha256(p)} for p in web.iterdir()}}
            (web / 'release-manifest.json').write_text(json.dumps(base))
            (reuse / 'qualification.json').write_text(json.dumps(qualification))
            (evidence / 'reuse-inputs.json').write_text(json.dumps({'qualification': qualification,
                'original_native_summary_sha256': sha256(native), 'new_engine_run': False}))
            (evidence / 'web-build/evidence').mkdir(parents=True)
            (evidence / 'web-build/evidence/export-report.json').write_text('{}')
            focused = folder / 'focused'; focused.mkdir(); self.fixtures(focused)
            fullflow = folder / 'fullflow'; fullflow.mkdir()
            report = {'passed': True, 'source_commit': 'a' * 40, 'source_tree': 'b' * 40,
                'export_manifest_sha256': sha256(web / 'release-manifest.json'),
                'native_report_sha256': sha256(native), 'real_compiled_ui': True, 'real_firestore_rules': True,
                'synthetic_only': True, 'browser_sandbox': True, 'real_google_sign_in': False,
                'diagnostic_only': False, 'checks': ['fixture'],
                'source_sha256': {n: sha256(staging.source_path(root, n)) for n in staging.FULLFLOW_SOURCES}}
            path = fullflow / 'firebase-fullflow.json'; path.write_text(json.dumps(report))
            selection = {'source_commit': 'a' * 40, 'source_tree': 'b' * 40,
                'qualification': qualification, 'release_run_id': 40, 'release_tag': 'v0.1.10c'}
            output = folder / 'variant'
            with patch.object(staging, 'source_identity'):
                result = staging.stage(root, reuse, selection, evidence, focused, fullflow, output, 10, 1)
            manifest = json.loads((output / 'firebase-variant-manifest.json').read_text())
            self.assertEqual(manifest['status'], 'qualified-release-staged-not-deployable')
            self.assertFalse(manifest['live_activation_allowed'])
            for name in ['index.js', 'index.wasm', 'index.pck']:
                self.assertEqual((output / 'public' / name).read_bytes(), (web / name).read_bytes())
            with self.assertRaisesRegex(ValueError, 'Unexpected Firebase package stage'):
                verify_package(output, 'a' * 40, result['manifest_sha256'])
            report['diagnostic_only'] = True; path.write_text(json.dumps(report))
            with patch.object(staging, 'source_identity'), self.assertRaisesRegex(ValueError, 'full-flow'):
                staging.stage(root, reuse, selection, evidence, focused, fullflow, folder / 'bad', 10, 1)

    def test_new_staging_contract_is_rejected_by_legacy_live_deployer(self):
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d)
            path = folder / 'firebase-variant-manifest.json'
            path.write_text(json.dumps({'status': 'qualified-release-staged-not-deployable',
                'source_commit': 'a' * 40, 'source_tree': 'b' * 40, 'live_activation_allowed': False}))
            with self.assertRaisesRegex(ValueError, 'Unexpected Firebase package stage'):
                verify_package(folder, 'a' * 40, sha256(path))

    def test_automatic_stage_has_no_google_token_or_deploy_step(self):
        root = Path(__file__).resolve().parents[2]
        for name in ['release-firebase.yml', 'stage-firebase.yml']:
            text = (root / '.github/workflows' / name).read_text()
            self.assertNotIn('id-token:', text)
            self.assertNotIn('google-github-actions/auth', text)
            self.assertNotIn('deploy_firebase_hosting.py', text)
        text = (root / '.github/workflows/stage-firebase.yml').read_text()
        self.assertIn('tools/reuse_released_web.py', text)
        self.assertIn('fullflow.test.mjs', text)
        self.assertIn('rules.log', text)
        self.assertIn('ref: ${{ steps.select.outputs.source_sha }}', text)


if __name__ == '__main__':
    unittest.main()
