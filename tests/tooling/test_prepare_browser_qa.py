"""Selected preparation behavior with synthetic coordinates; never start Godot."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from qualification import prepare_browser_qa as qa


class PreparationTests(unittest.TestCase):
    def test_dispatch_runs_only_requested_scenario(self):
        for scenario in ('wall', 'cloud'):
            with patch.object(qa, 'wall_main') as wall, patch.object(qa, 'cloud_main') as cloud:
                qa.main([scenario, '--output', 'synthetic-output'])
                selected, other = (wall, cloud) if scenario == 'wall' else (cloud, wall)
                selected.assert_called_once_with(['--output', 'synthetic-output'])
                other.assert_not_called()

    def test_profiles_are_disposable_for_all_platforms(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / 'profile'
            env = qa.synthetic_profile(folder)
            for key in ('HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
                self.assertEqual(Path(env[key]).parent, folder)
                self.assertTrue(Path(env[key]).is_dir())

    def test_existing_output_refused_before_copy_or_engine(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(qa.shutil, 'copytree') as copy, patch.object(qa.subprocess, 'run') as engine:
            with self.assertRaises(ValueError):
                qa.main(['cloud', '--output', tmp])
            copy.assert_not_called()
            engine.assert_not_called()

    def cloud(self, invalid=False):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'output'
            def run(command, **kwargs):
                if '--script' not in command:
                    return
                self.assertEqual(command[command.index('--script') + 1], 'res://tests/probe_cloud_recovery_geometry.gd')
                project = Path(command[command.index('--path') + 1])
                self.assertEqual((project / 'tests/probe_cloud_recovery_geometry.gd').read_bytes(),
                                 (qa.ROOT / 'tests/diagnostics/probe_cloud_recovery_geometry.gd').read_bytes())
                value = json.loads(Path(command[-2]).read_text())
                width = value['viewport']['width']
                reason = value['snapshot']['reason']
                text = reason + (' Current progress is protected on this device.' if 'nativeCallback' in value else '')
                result = {'text': text, 'buttons': {'switch': [width if invalid else 1, len(reason), 20, 20]}}
                Path(command[-1]).write_text(json.dumps(result))
            def stage_directory(source, destination, **kwargs):
                Path(destination).mkdir(parents=True, exist_ok=True)
            with patch.object(qa.shutil, 'copytree', side_effect=stage_directory), patch.object(qa.subprocess, 'run', side_effect=run) as engine, patch.object(qa.subprocess, 'check_output', return_value='synthetic-source\n'), patch.object(qa, 'sha256', return_value='synthetic-hash'):
                if invalid:
                    with self.assertRaises(ValueError):
                        qa.main(['cloud', '--output', str(out)])
                    self.assertFalse((out / 'binding.json').exists())
                else:
                    qa.main(['cloud', '--output', str(out)])
                    self.assertEqual(engine.call_count, 7)  # one import, six layouts
                    layouts = json.loads((out / 'regressions.json').read_text())
                    self.assertEqual(len(layouts), 6)
                    self.assertEqual({x['message'] for x in layouts}, {'short', 'wrapped', 'protected'})
                    self.assertTrue(json.loads((out / 'binding.json').read_text())['synthetic_only'])
                    for call in engine.call_args_list:
                        self.assertTrue(Path(call.kwargs['env']['HOME']).is_relative_to(out))

    def test_cloud_retains_six_layouts_and_receipt(self):
        self.cloud()

    def test_bad_coordinates_cannot_produce_success_receipt(self):
        self.cloud(invalid=True)

    def wall(self, missing_historical_resource=False):
        fixture_bytes = (qa.ROOT / 'tests/fixtures/wall_compatibility_layout.gd').read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixtures = root / 'tests/fixtures/wall-compatibility'
            fixtures.mkdir(parents=True)
            source_fixture = fixtures.parent / 'wall_compatibility_layout.gd'
            source_fixture.write_bytes(fixture_bytes)
            for name in ('old-format1.json', 'new-format2.json'):
                (fixtures / name).write_bytes(b'{}')
            builds = {}
            production = {}
            for label, resource in [('old', 'scripts/cafe_web_save.gd'),
                                    ('new', 'scripts/persistence/cafe_web_save.gd')]:
                builds[label] = root / label
                path = builds[label] / 'project' / resource
                path.parent.mkdir(parents=True)
                if label != 'old' or not missing_historical_resource:
                    path.write_bytes(b'extends RefCounted\n# unchanged production\n')
                    production[path] = path.read_bytes()
                (builds[label] / 'web').mkdir()
                (builds[label] / 'web/release-manifest.json').write_bytes(b'{}')
            def run(command, **kwargs):
                project = Path(command[command.index('--path') + 1])
                label = 'new' if '--new-layout' in command else 'old'
                expected = fixture_bytes if label == 'new' else fixture_bytes.replace(
                    b'res://scripts/persistence/cafe_web_save.gd', b'res://scripts/cafe_web_save.gd')
                self.assertEqual((project / 'tests/wall_compatibility_layout.gd').read_bytes(), expected)
                result = Path(next(x.removeprefix('--layout-output=') for x in command if x.startswith('--layout-output=')))
                result.write_text(json.dumps({'checks': 1, 'failures': []}), encoding='utf-8')
                return SimpleNamespace(returncode=0, stdout=b'synthetic layout pass\n')
            manifest = {'source_commit': 'synthetic-source', 'toolchain_receipt': {}, 'production_sha256': {}}
            with patch.object(qa, 'ROOT', root), patch.object(qa, 'FIXTURES', fixtures), \
                    patch.object(qa, 'CONTRACT', {'fixture_sha256': {}}), \
                    patch.object(qa, 'validate_export', return_value=manifest), \
                    patch.object(qa, 'verify_installer_receipt', return_value={}), \
                    patch.dict(qa.os.environ, {'GODOT_TEMPLATE': 'synthetic-template', 'GODOT_TOOLCHAIN_RECEIPT': 'synthetic-receipt'}), \
                    patch.object(qa.subprocess, 'run', side_effect=run) as engine:
                args = ['--old-source', str(root), '--old-build', str(builds['old']),
                        '--new-build', str(builds['new']), '--output', str(root / 'output')]
                if missing_historical_resource:
                    with self.assertRaisesRegex(RuntimeError, 'exact WebSave resource'):
                        qa.wall_main(args)
                    engine.assert_not_called()
                else:
                    qa.wall_main(args)
                    self.assertEqual(engine.call_count, 2)
                    self.assertEqual(set(json.loads((root / 'output/preflight.json').read_text())['layouts']), {'old', 'new'})
            self.assertEqual(source_fixture.read_bytes(), fixture_bytes)
            for path, content in production.items():
                self.assertEqual(path.read_bytes(), content)

    def test_wall_preflight_uses_each_source_namespace_without_mutating_inputs(self):
        self.wall()

    def test_missing_historical_web_save_refused_before_engine(self):
        self.wall(missing_historical_resource=True)


if __name__ == '__main__':
    unittest.main()
