"""Adversarial fixed-input checks; no child/runtime/network is started."""
import copy
import ast
import hashlib
import importlib.util
from pathlib import Path, PurePosixPath
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import json

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('route', ROOT/'tools/diagnostics/retained_handoff_route.py')
route = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(route)
sys.path.insert(0, str(ROOT/'tools/diagnostics'))
import current_handoff_route as current

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

class DisposablePathTests(unittest.TestCase):
    def create_paths(self, root, output):
        # Execute only the actual finite directory/environment loop, with no child.
        source = ast.parse((ROOT/'tools/diagnostics/retained_handoff_route.py').read_text())
        run = next(node for node in source.body if isinstance(node, ast.FunctionDef) and node.name == 'run')
        loop = next(node for node in run.body if isinstance(node, ast.For)
                    and isinstance(node.iter, ast.List)
                    and [item.value for item in node.iter.elts] ==
                    ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'TMPDIR'])
        namespace = {'root': root, 'output': output, 'child_env': {}}
        exec(compile(ast.Module(body=[loop], type_ignores=[]), '<owned-directory-loop>', 'exec'), namespace)
        return namespace['child_env']

    def test_original_linux_workspace_socket_fits_with_only_tmpdir_changed(self):
        created = []
        class Directory(PurePosixPath):
            def mkdir(self, **kwargs):
                created.append((self, kwargs))
        root = Directory('/home/runner/work/little-leaf/little-leaf/current')
        output = root/'diagnostic-output'
        env = self.create_paths(root, output)
        socket_suffix = PurePosixPath('com.google.Chrome.DbvziA/SingletonSocket')
        self.assertEqual(len(str(output/'disposable/TMPDIR'/socket_suffix).encode()), 126)
        self.assertLess(len(str(PurePosixPath(env['TMPDIR'])/socket_suffix).encode()), 108)
        self.assertEqual(PurePosixPath(env['TMPDIR']), root/'tmp')
        for name in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
            self.assertEqual(env[name], str(output/'disposable'/name))
        self.assertTrue(all(root in folder.parents for folder, _ in created))
        self.assertTrue(all(kwargs == {'parents': True} for _, kwargs in created))

    def test_existing_tmpdir_is_refused_without_touching_its_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); output = root/'diagnostic-output'
            output.mkdir(); (root/'tmp').mkdir()
            sentinel = root/'tmp/other-owner'; sentinel.write_bytes(b'preserve')
            with self.assertRaises(FileExistsError):
                self.create_paths(root, output)
            self.assertEqual(sentinel.read_bytes(), b'preserve')
            self.assertEqual(list((root/'tmp').iterdir()), [sentinel])

class CurrentRetainedTests(unittest.TestCase):
    def values(self):
        identifier, name, digest = current.ARTIFACTS['web']
        return ({'id': identifier, 'name': name, 'digest': 'sha256:'+digest, 'expired': False,
                 'expires_at': '2099-01-01T00:00:00Z',
                 'workflow_run': {'id': current.RUN, 'head_sha': current.SOURCE}},
                {'id': current.RUN, 'run_attempt': 1, 'head_sha': current.SOURCE, 'status': 'completed',
                 'conclusion': 'failure', 'event': 'workflow_dispatch', 'path': '.github/workflows/stage-firebase.yml'})

    def test_current_profile_never_aliases_legacy_input(self):
        values = self.values()
        route.validate_metadata('web', *values, artifacts=current.ARTIFACTS,
                                source=current.SOURCE, run_id=current.RUN)
        with self.assertRaises(ValueError):
            route.validate_metadata('web', *values)
        for field, value in [('head_sha', route.SOURCE), ('run_attempt', 2), ('event', 'pull_request')]:
            artifact, run = self.values(); run[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                route.validate_metadata('web', artifact, run, artifacts=current.ARTIFACTS,
                                        source=current.SOURCE, run_id=current.RUN)

    def test_headed_report_and_complete_original_sources_required(self):
        hashes = {name: '0'*64 for name in current.FLOW_SOURCES}
        report = {'source_commit':current.SOURCE, 'source_tree':current.TREE,
                  'export_manifest_sha256':current.EXPORT, 'native_report_sha256':current.NATIVE,
                  'itch_entry_sha256':current.ENTRY, 'headless_browser':False, 'passed':False,
                  'source_sha256':hashes}
        current.validate_report(report, hashes)
        for key, value in [('headless_browser',True), ('headless_browser',0), ('passed',True),
                           ('source_commit',route.SOURCE), ('itch_entry_sha256','0'*64),
                           ('source_sha256',dict(list(hashes.items())[1:]))]:
            changed=copy.deepcopy(report);changed[key]=value
            with self.subTest(key=key), self.assertRaises(ValueError):
                current.validate_report(changed, hashes)

    def variant(self, root):
        inner=root/'variant/public/itch';inner.mkdir(parents=True)
        web=root/'build/web';web.mkdir(parents=True)
        report={'source_sha256':{}}
        for name in ['little_leaf_firebase.js','little_leaf_firebase_session.js',
                     'little_leaf_firebase_boot.mjs','little_leaf_update.js']:
            (inner/name).write_bytes(b'original current module')
            report['source_sha256']['web/'+name]=route.sha(inner/name)
        base={'files':{}}
        for name in ['index.js','index.wasm','index.pck']:
            (inner/name).write_bytes(b'original compiled runtime')
            base['files'][name]={'sha256':route.sha(inner/name)}
        (web/'release-manifest.json').write_text(json.dumps(base))
        (inner/'hosting-release.json').write_text(json.dumps({'source_commit':current.SOURCE,
            'source_tree':current.TREE,'ci_run_id':str(current.RUN),'runtime_path':'/itch/',
            'base_web_manifest_sha256':current.EXPORT}))
        (inner/'index.html').write_bytes(b'original LF entry\n')
        self.seal(root)
        return report, route.sha(inner/'index.html')

    def seal(self, root):
        folder=root/'variant';manifest=folder/'firebase-variant-manifest.json'
        files={p.relative_to(folder).as_posix():route.sha(p) for p in folder.rglob('*')
               if p.is_file() and p!=manifest}
        manifest.write_text(json.dumps({'files':files}))

    def test_original_linux_entry_not_normalized_or_windows_relabelled(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);report, entry=self.variant(root)
            with patch.object(current,'ENTRY',entry):
                current.validate_variant(root,report)
                (root/'variant/public/itch/index.html').write_bytes(b'original LF entry\r\n')
                self.seal(root)
                with self.assertRaises(ValueError):current.validate_variant(root,report)

    def test_self_consistent_inventory_cannot_replace_source_module(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);report,entry=self.variant(root)
            (root/'variant/public/itch/little_leaf_firebase.js').write_bytes(b'changed client')
            self.seal(root)
            with patch.object(current,'ENTRY',entry), self.assertRaises(ValueError):
                current.validate_variant(root,report)

    def test_frozen_overlay_is_separate_from_original_fullflow(self):
        folder=ROOT/'platform/firebase/diagnostics'
        self.assertEqual(route.sha(folder/'current_handoff_driver.mjs'),current.DRIVER)
        self.assertEqual(route.sha(folder/'current_handoff_observer.mjs'),current.OBSERVER)
        # Current fixture pin; retained runs still validate their own exact source checkout/report.
        self.assertEqual(route.sha(ROOT/'platform/firebase/fullflow.test.mjs'),
                         'e07cf5c7c6e22eb164468f5747a70bb50f5dc1c6f3611d52d77db0e04ebf76ca')

    def test_expired_preparation_and_arbitrary_driver_stop_before_runtime(self):
        with patch.dict(current.os.environ,{'LL_RETAINED_START_MONOTONIC':'0'}), \
                patch.object(current.time,'monotonic',return_value=420.1), self.assertRaises(TimeoutError):
            current.remaining()
        with self.assertRaises(ValueError):route.run(Path('unused'),{},driver='../other.mjs')

    def test_changed_preparation_receipt_stops_before_source_or_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'diagnostic-binding.json').write_text('{}')
            args=['route','--root',str(root),'--coordinator',str(root),'--run']
            with patch.object(sys,'argv',args), patch.object(current,'remaining',return_value=10), \
                    patch.dict(current.os.environ,{'LL_CURRENT_BINDING_SHA256':'0'*64}), \
                    patch.object(current,'retained_report',side_effect=AssertionError('must stop first')), \
                    self.assertRaises(ValueError):
                current.main()

    def test_geometry_change_after_preparation_stops_before_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);geometry=root/'evidence'/current.PREFIX
            geometry.mkdir(parents=True);(geometry/'geometry-1-input.json').write_text('changed')
            binding={'reconstructed_variant_manifest_sha256':'a'*64,'source_sha256':{},
                     'geometry_input_sha256':'0'*64,'geometry_result_sha256':'0'*64}
            receipt=root/'diagnostic-binding.json';receipt.write_text(json.dumps(binding))
            args=['route','--root',str(root),'--coordinator',str(root),'--run']
            with patch.object(sys,'argv',args), patch.object(current,'remaining',return_value=10), \
                    patch.dict(current.os.environ,{'LL_CURRENT_BINDING_SHA256':route.sha(receipt)}), \
                    patch.object(current,'retained_report',return_value={}), \
                    patch.object(current,'validate_variant',return_value='a'*64), \
                    patch.object(current,'source_hashes',return_value={}), \
                    patch.object(current,'run',side_effect=AssertionError('no runtime')), \
                    self.assertRaises(ValueError):
                current.main()



class Current59FixedInputTests(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location('current59_test', ROOT/'tools/diagnostics/current_handoff_route.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.select_current59_profile()
        return module

    def test_actual59_overlay_and_old9_profile_are_distinct(self):
        actual = self.module()
        self.assertEqual(actual.SOURCE, '59e3e572e5d7723b7515f1a0a2af226bafe38b2f')
        self.assertEqual(actual.TREE, '2dc00d31ff80b9d1ca3e24bdf8f6f712f3d8e199')
        self.assertEqual(actual.RUN, 38298556083)
        self.assertEqual(current.SOURCE, '9ecd88481f0f4c3faf06662b992efab6c99a3849')
        self.assertEqual(actual.DRIVER, route.sha(ROOT/'platform/firebase/diagnostics/current59_handoff_driver.mjs'))
        self.assertEqual(actual.FROZEN_DRIVER, 'current59_handoff_driver.mjs')
        self.assertNotEqual(actual.DRIVER, current.DRIVER)
        self.assertEqual(actual.OBSERVER, current.OBSERVER)

    def test_mixed_old_source_and_artifact_refused(self):
        actual = self.module()
        identifier, name, digest = actual.ARTIFACTS['web']
        artifact = {'id': identifier, 'name': name, 'digest': 'sha256:'+digest, 'expired': False,
            'expires_at': '2099-01-01T00:00:00Z', 'workflow_run': {'id': actual.RUN, 'head_sha': actual.SOURCE}}
        run = {'id': actual.RUN, 'run_attempt': 1, 'head_sha': actual.SOURCE, 'status': 'completed',
            'conclusion': 'failure', 'event': 'workflow_dispatch', 'path': '.github/workflows/stage-firebase.yml'}
        route.validate_metadata('web', artifact, run, artifacts=actual.ARTIFACTS, source=actual.SOURCE, run_id=actual.RUN)
        for field, value in [('head_sha',current.SOURCE), ('id',current.RUN), ('run_attempt',2)]:
            changed = copy.deepcopy(run); changed[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                route.validate_metadata('web', artifact, changed, artifacts=actual.ARTIFACTS, source=actual.SOURCE, run_id=actual.RUN)
        artifact['digest'] = 'sha256:'+current.ARTIFACTS['web'][2]
        with self.assertRaises(ValueError):
            route.validate_metadata('web', artifact, run, artifacts=actual.ARTIFACTS, source=actual.SOURCE, run_id=actual.RUN)

    def test_old_report_or_windows_entry_cannot_cover59(self):
        actual = self.module()
        report = {'source_commit': actual.SOURCE, 'source_tree': actual.TREE,
            'export_manifest_sha256': actual.EXPORT, 'native_report_sha256': actual.NATIVE,
            'itch_entry_sha256': actual.ENTRY, 'headless_browser': False, 'passed': False, 'source_sha256': {'fixed':'hash'}}
        actual.validate_report(report, {'fixed':'hash'})
        for field, value in [('source_commit',current.SOURCE), ('itch_entry_sha256',current.ENTRY),
            ('native_report_sha256',current.NATIVE), ('headless_browser',True), ('passed',True)]:
            changed = copy.deepcopy(report); changed[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                actual.validate_report(changed, {'fixed':'hash'})

    def test_nonboolean_mode_rejected_before_any_setup(self):
        with self.assertRaises(ValueError):
            current.main(current59=1)

class Current11FixedInputTests(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location('current11_test', ROOT/'tools/diagnostics/current_handoff_route.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.select_current11_profile()
        return module

    def test_current11_does_not_alias_prior_modes_or_overlay(self):
        actual = self.module()
        self.assertEqual(actual.SOURCE, '11b3d9b864fc764654fdfc25c30cd0ea85d300cd')
        self.assertEqual(actual.TREE, '950655dbb59a4549ada6082031cf6331c1e44d12')
        self.assertEqual(actual.RUN, 38314607257)
        self.assertEqual(actual.ARTIFACTS['web'][0], 11776123114)
        self.assertEqual(actual.ARTIFACTS['evidence'][0], 11776855171)
        self.assertEqual(actual.DRIVER, route.sha(ROOT/'platform/firebase/diagnostics/current11_handoff_driver.mjs'))
        self.assertEqual(actual.OBSERVER, current.OBSERVER)
        self.assertEqual(current.SOURCE, '9ecd88481f0f4c3faf06662b992efab6c99a3849')
        actual.select_current59_profile()
        self.assertEqual(actual.SOURCE, '59e3e572e5d7723b7515f1a0a2af226bafe38b2f')

    def test_old_or_mixed_source_and_successful_stage_cannot_cover11(self):
        actual = self.module()
        identifier, name, digest = actual.ARTIFACTS['web']
        artifact = {'id': identifier, 'name': name, 'digest': 'sha256:'+digest,
            'expired': False, 'expires_at': '2099-01-01T00:00:00Z',
            'workflow_run': {'id': actual.RUN, 'head_sha': actual.SOURCE}}
        run = {'id': actual.RUN, 'run_attempt': 1, 'head_sha': actual.SOURCE,
            'status': 'completed', 'conclusion': 'failure', 'event': 'workflow_dispatch',
            'path': '.github/workflows/stage-firebase.yml'}
        route.validate_metadata('web', artifact, run, artifacts=actual.ARTIFACTS,
                                source=actual.SOURCE, run_id=actual.RUN)
        for field, value in [('head_sha', current.SOURCE),
                             ('head_sha', '59e3e572e5d7723b7515f1a0a2af226bafe38b2f'),
                             ('conclusion', 'success'), ('run_attempt', 2)]:
            changed = dict(run); changed[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                route.validate_metadata('web', artifact, changed, artifacts=actual.ARTIFACTS,
                                        source=actual.SOURCE, run_id=actual.RUN)


if __name__ == '__main__':
    unittest.main()
