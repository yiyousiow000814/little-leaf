"""Adversarial fixed-input checks; no child/runtime/network is started."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('route', ROOT/'tools/diagnostics/retained_handoff_route.py')
route = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(route)

class RetainedMetadataTests(unittest.TestCase):
    def values(self):
        identifier, name, digest = route.ARTIFACTS['web']
        return ({'id': identifier, 'name': name, 'digest': 'sha256:'+digest, 'expired': False,
            'expires_at': '2099-01-01T00:00:00Z', 'workflow_run': {'id': route.RUN, 'head_sha': route.SOURCE}},
            {'id': route.RUN, 'run_attempt': 1, 'head_sha': route.SOURCE, 'status': 'completed',
             'conclusion': 'failure', 'event': 'workflow_dispatch', 'path': '.github/workflows/stage-firebase.yml'})
    def test_exact_failed_source_is_diagnostic_input(self):
        route.validate_metadata('web', *self.values())
    def test_wrong_expired_unbound_and_pr_sources_rejected(self):
        for field, value in [('id', True), ('id', 1), ('name', 'ordinary'), ('digest', 'sha256:'+'0'*64),
                             ('expired', True), ('expired', 0), ('expires_at', '2000-01-01T00:00:00Z'),
                             ('expires_at', '2099-01-01T00:00:00')]:
            artifact, run = self.values(); artifact[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                route.validate_metadata('web', artifact, run)
        for field, value in [('run_attempt', 2), ('run_attempt', True), ('head_sha', '0'*40), ('event', 'pull_request'),
                             ('path', '.github/workflows/ci.yml'), ('status', 'in_progress')]:
            artifact, run = self.values(); run[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                route.validate_metadata('web', artifact, run)
    def test_different_runner_is_not_silently_substituted(self):
        route.image_gate({'ImageOS': 'ubuntu24', 'ImageVersion': route.IMAGE})
        for env in [{}, {'ImageOS':'ubuntu24','ImageVersion':'new'}, {'ImageOS':'ubuntu22','ImageVersion':route.IMAGE}]:
            with self.subTest(env=env), self.assertRaises(ValueError):
                route.image_gate(env)

class RetainedArchiveTests(unittest.TestCase):
    def archive(self, root, name='safe/file'):
        archive = root/'input.zip'
        with zipfile.ZipFile(archive, 'w') as zipped:
            info = zipfile.ZipInfo('safe')
            info.filename = name  # Preserve malicious separator instead of Windows normalization.
            zipped.writestr(info, b'exact retained bytes')
        return archive
    def test_integrity_and_exact_selected_members(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); archive = self.archive(root)
            route.unpack(archive, root/'out', route.sha(archive), ['safe/file'])
            self.assertEqual((root/'out/safe/file').read_bytes(), b'exact retained bytes')
            with self.assertRaises(ValueError): route.unpack(archive, root/'out', route.sha(archive))
            with self.assertRaises(ValueError): route.unpack(archive, root/'missing', route.sha(archive), ['missing'])
            with self.assertRaises(ValueError): route.unpack(archive, root/'digest', '0'*64)
    def test_unsafe_paths_and_symlinks_refused(self):
        for name in ['../escape', '/absolute', 'C:/drive', 'back\\slash']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); archive = self.archive(root, name)
                with self.assertRaises(ValueError): route.unpack(archive, root/'out', route.sha(archive))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); archive = root/'input.zip'; info = zipfile.ZipInfo('link')
            info.create_system = 3; info.external_attr = (stat.S_IFLNK|0o777)<<16
            with zipfile.ZipFile(archive, 'w') as zipped: zipped.writestr(info, 'target')
            with self.assertRaises(ValueError): route.unpack(archive, root/'out', route.sha(archive))

class FrozenObserverTests(unittest.TestCase):
    def test_corrected_observer_and_original_network_bytes(self):
        folder = ROOT/'platform/firebase/diagnostics'
        self.assertEqual(route.sha(folder/'retained_handoff_driver.mjs'), route.DRIVER)
        self.assertEqual(route.sha(folder/'retained_handoff_network.mjs'), route.NETWORK)
    def test_runtime_does_not_pass_credentials_or_new_browser_flags(self):
        source = (ROOT/'tools/diagnostics/retained_handoff_route.py').read_text()
        self.assertNotIn('--no-sandbox', source)
        self.assertNotIn('disable-web-security', source)
        self.assertNotIn("child_env = os.environ", source)
        self.assertNotIn('GODOT_BIN', source)
        driver = (ROOT/'platform/firebase/diagnostics/retained_handoff_driver.mjs').read_text()
        self.assertIn("scope:'retained-first-two-cases'", driver)
        self.assertIn('release_qualification:false,deployable:false', driver)
        self.assertIn('report.timingCheckpointUnavailable=true', driver)

class DerivedVariantTests(unittest.TestCase):
    def fixture(self, root):
        manifest = root/'variant/firebase-variant-manifest.json'
        entry = root/'variant/public/itch/index.html'
        entry.parent.mkdir(parents=True)
        manifest.write_bytes(b'{"diagnostic_only":true}\n')
        entry.write_bytes(b'<html>\n<body>retained entry</body>\n</html>\n')
        return manifest, entry

    def test_exact_manifest_and_linux_entry_are_both_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); manifest, entry = self.fixture(root)
            with mock.patch.object(route, 'VARIANT', route.sha(manifest)), mock.patch.object(route, 'EMBEDDED_ENTRY', route.sha(entry)):
                route.validate_derived_variant(root)
                entry.write_bytes(entry.read_bytes().replace(b'\n', b'\r\n'))
                with self.assertRaisesRegex(ValueError, 'Original derived variant not reproduced'):
                    route.validate_derived_variant(root)
            evidence = json.loads((root/'diagnostic-prepare-failure.json').read_bytes())
            self.assertEqual(evidence['actual_entry_sha256'], route.sha(entry))
            self.assertNotEqual(evidence['actual_entry_sha256'], evidence['expected_entry_sha256'])
            self.assertFalse(evidence['runtime_started'])
            self.assertFalse(evidence['deployable'])

    def test_manifest_mismatch_retains_only_fixed_hash_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); manifest, entry = self.fixture(root)
            with mock.patch.object(route, 'VARIANT', route.sha(manifest)), mock.patch.object(route, 'EMBEDDED_ENTRY', route.sha(entry)):
                manifest.write_bytes(manifest.read_bytes().replace(b'\n', b'\r\n'))
                with self.assertRaises(ValueError): route.validate_derived_variant(root)
            evidence = json.loads((root/'diagnostic-prepare-failure.json').read_bytes())
            self.assertEqual(set(evidence), {'diagnostic_only', 'release_qualification', 'deployable',
                'phase', 'expected_manifest_sha256', 'actual_manifest_sha256',
                'expected_entry_sha256', 'actual_entry_sha256', 'runtime_started'})
            self.assertEqual(evidence['actual_entry_sha256'], evidence['expected_entry_sha256'])
            self.assertEqual(evidence['actual_manifest_sha256'], route.sha(manifest))

    def test_evidence_write_failure_cannot_mask_original_guard(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch.object(route, 'sha', side_effect=['0'*64, '1'*64]), mock.patch.object(Path, 'open', side_effect=PermissionError('unavailable')):
                with self.assertRaisesRegex(ValueError, 'Original derived variant not reproduced'):
                    route.validate_derived_variant(root)

class AbsoluteCutoffTests(unittest.TestCase):
    def test_expired_cleanup_has_zero_wait_not_positive_floor(self):
        self.assertEqual(route.cleanup_timeout(480, 5, 480.1), 0)
        self.assertEqual(route.cleanup_timeout(480, 10, 479.9), 480-479.9)
    def test_late_physical_terminal_is_incomplete(self):
        late = route.completion_flags(True, True, 480, 480.1)
        self.assertTrue(late['physically_released'])
        self.assertFalse(late['complete_within_hard_cap'])
        self.assertFalse(late['queue_release'])
    def test_durability_crossing_cutoff_and_unknown_terminal_hold(self):
        self.assertTrue(route.completion_flags(True, True, 480, 479.9)['queue_release'])
        self.assertFalse(route.completion_flags(True, True, 480, 480.01)['queue_release'])
        self.assertFalse(route.completion_flags(True, False, 480, 479)['queue_release'])
        self.assertFalse(route.completion_flags(False, True, 480, 479)['queue_release'])

if __name__ == '__main__':
    unittest.main()
