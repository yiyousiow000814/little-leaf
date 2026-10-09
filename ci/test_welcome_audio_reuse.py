"""Synthetic-only immutable artifact and source-map negative tests; no network."""
import copy
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import welcome_audio_reuse as gate


class ArtifactReuseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        pins = patch.dict(gate.PINS); pins.start(); self.addCleanup(pins.stop)
        self.root = Path(self.temp.name); self.web = self.root / 'web'; self.web.mkdir()
        self.artifact = {'id': gate.PINS['artifact_id'], 'expired': False,
                         'digest': 'sha256:' + gate.PINS['archive_sha256'],
                         'workflow_run': {'id': gate.PINS['run_id'], 'head_sha': gate.PINS['run_head']}}
        self.run = {'id': gate.PINS['run_id'], 'head_sha': gate.PINS['run_head'],
                    'repository': {'full_name': gate.PINS['repository']}, 'status': 'in_progress', 'conclusion': None}
        production = {'scripts/cafe_intro.gd': gate.digest(b'frozen synthetic intro'), 'project.godot': gate.digest(b'synthetic project')}
        self.source = {'commit': gate.PINS['source_commit'], 'tree': gate.PINS['source_tree'], 'production': production}
        self.qa = {'commit': 'a' * 40, 'tree': 'b' * 40, 'production': dict(production)}
        files = {}
        for name in ['index.html', 'index.js', 'index.wasm', 'index.pck']:
            payload = ('synthetic export ' + name).encode(); (self.web / name).write_bytes(payload)
            files[name] = {'bytes': len(payload), 'sha256': gate.digest(payload)}
        self.manifest = {'source_commit': gate.PINS['source_commit'], 'source_tree': gate.PINS['source_tree'],
                         'toolchain_verification': 'checksum-pinned-official-archives', 'packed_smoke': 'passed',
                         'engine_checks': gate.PINS['engine_checks'], 'test_processes': gate.PINS['test_processes'],
                         'workflow_run': str(gate.PINS['run_id']), 'production_sha256': production, 'files': files}
        self.save()

    def save(self):
        (self.web / 'release-manifest.json').write_text(json.dumps(self.manifest))
        gate.PINS['manifest_sha256'] = gate.digest((self.web / 'release-manifest.json').read_bytes())

    def test_exact_active_run_is_diagnostic_only(self):
        self.assertTrue(gate.validate_records(self.artifact, self.run)['diagnostic_only'])
        gate.validate_export(self.web, self.source, self.qa)

    def test_wrong_artifact_id_digest_expiry_or_run_rejected(self):
        for key, value in [('id', 1), ('digest', 'sha256:' + '0' * 64), ('expired', True)]:
            row = copy.deepcopy(self.artifact); row[key] = value
            with self.subTest(key=key), self.assertRaises(AssertionError): gate.validate_records(row, self.run)
        for key, value in [('id', 1), ('head_sha', '0' * 40)]:
            row = copy.deepcopy(self.artifact); row['workflow_run'][key] = value
            with self.subTest(key=key), self.assertRaises(AssertionError): gate.validate_records(row, self.run)

    def test_wrong_run_head_or_repository_rejected(self):
        for change in [{'id': 1}, {'head_sha': '0' * 40}, {'repository': {'full_name': 'other/repo'}}]:
            with self.subTest(change=change), self.assertRaises(AssertionError): gate.validate_records(self.artifact, {**self.run, **change})

    def test_wrong_checkout_commit_or_tree_rejected(self):
        for key in ['commit', 'tree']:
            with self.subTest(key=key), self.assertRaises(AssertionError): gate.validate_export(self.web, {**self.source, key: '0' * 40}, self.qa)

    def test_wrong_manifest_commit_tree_or_toolchain_rejected(self):
        for key, value in [('source_commit', '0' * 40), ('source_tree', '0' * 40), ('toolchain_verification', 'local'), ('packed_smoke', 'failed'), ('engine_checks', 0), ('test_processes', 1), ('workflow_run', 'other')]:
            before = self.manifest[key]; self.manifest[key] = value; self.save()
            with self.subTest(key=key), self.assertRaises(AssertionError): gate.validate_export(self.web, self.source, self.qa)
            self.manifest[key] = before

    def test_incomplete_extra_or_changed_production_maps_rejected(self):
        for production in [{}, {**self.qa['production'], 'web/extra.js': '0' * 64}, {**self.qa['production'], 'project.godot': '0' * 64}]:
            with self.subTest(production=production), self.assertRaises(AssertionError): gate.validate_export(self.web, self.source, {**self.qa, 'production': production})
        self.manifest['production_sha256'] = {}; self.save()
        with self.assertRaises(AssertionError): gate.validate_export(self.web, self.source, self.qa)

    def test_manifest_digest_is_pinned(self):
        gate.PINS['manifest_sha256'] = '0' * 64
        with self.assertRaisesRegex(AssertionError, 'manifest SHA256'): gate.validate_export(self.web, self.source, self.qa)

    def test_changed_export_bytes_rejected(self):
        (self.web / 'index.pck').write_bytes(b'replaced')
        with self.assertRaises(AssertionError): gate.validate_export(self.web, self.source, self.qa)

    def test_missing_or_unbound_export_files_rejected(self):
        (self.web / 'extra.js').write_text('unbound')
        with self.assertRaises(AssertionError): gate.validate_export(self.web, self.source, self.qa)
        (self.web / 'extra.js').unlink(); (self.web / 'index.js').unlink()
        with self.assertRaises(AssertionError): gate.validate_export(self.web, self.source, self.qa)

    def test_manifest_cannot_omit_required_web_files(self):
        del self.manifest['files']['index.pck']; self.save()
        with self.assertRaises(AssertionError): gate.validate_export(self.web, self.source, self.qa)

    def archive(self, names):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as z:
            for name in names: z.writestr(name, b'synthetic')
        archive = self.root / 'artifact.zip'; archive.write_bytes(buffer.getvalue()); return archive

    def test_exact_zip_digest_is_required_before_unpack(self):
        archive = self.archive(['index.html']); output = self.root / 'unpacked'
        with self.assertRaises(AssertionError): gate.unpack(archive, output)
        self.assertFalse(output.exists())
        with patch.dict(gate.PINS, archive_sha256=gate.digest(archive.read_bytes())): gate.unpack(archive, output)
        self.assertEqual((output / 'index.html').read_bytes(), b'synthetic')

    def test_zip_traversal_absolute_and_duplicate_members_rejected(self):
        for names in [['../escape'], ['/absolute'], ['back\\slash'], ['a//b'], ['index.html', 'index.html']]:
            archive = self.archive(names)
            with self.subTest(names=names), patch.dict(gate.PINS, archive_sha256=gate.digest(archive.read_bytes())), self.assertRaises(AssertionError): gate.unpack(archive, self.root / 'unpacked')

    def test_zip_symlink_rejected(self):
        archive = self.root / 'link.zip'; entry = zipfile.ZipInfo('link'); entry.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(archive, 'w') as z: z.writestr(entry, 'target')
        with patch.dict(gate.PINS, archive_sha256=gate.digest(archive.read_bytes())), self.assertRaises(AssertionError): gate.unpack(archive, self.root / 'unpacked')


class DiagnosticWorkflowTests(unittest.TestCase):
    def test_scope_pins_and_no_rebuild_or_security_changes(self):
        text = (Path(__file__).resolve().parents[1] / '.github/workflows/welcome-audio-reuse.yml').read_text()
        self.assertIn('branches: [qa/welcome-system-chrome-artifact]', text)
        self.assertIn("if: github.ref == 'refs/heads/qa/welcome-system-chrome-artifact'", text)
        self.assertIn('WELCOME_AUDIO_BROWSER: system-chrome', text)
        self.assertIn(gate.PINS['source_commit'], text)
        for identifier in ['artifact_id', 'run_id']: self.assertIn(str(gate.PINS[identifier]), text)
        for forbidden in ['--no-sandbox', '--enable-automation', 'autoplay-policy', 'sysctl', 'apparmor', 'build_web.py', 'run_integration_candidate.py', 'continue-on-error']:
            self.assertNotIn(forbidden, text)
        self.assertIn('contents: read', text); self.assertIn('actions: read', text)
        self.assertIn('if: always()', text)


if __name__ == '__main__': unittest.main()
