"""Native entrypoint contracts with synthetic processes and disposable inputs."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]


class NativeUiRunnerTests(unittest.TestCase):
    def exercise(self, entry, native=False, payload='valid', cache=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'source'
            (root / 'scripts').mkdir(parents=True)
            (root / 'scripts/cafe_web_save.gd').write_text(
                'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"\n')
            (root / 'assets').mkdir()
            (root / 'assets/input.png').write_bytes(b'synthetic asset')
            (root / '.godot/imported').mkdir(parents=True)
            (root / '.godot/imported/input.ctex').write_bytes(b'imported fixture')
            output = Path(directory) / 'output'
            spec = importlib.util.spec_from_file_location('native_entry', ROOT / ('tests/run_' + entry + '_ui.py'))
            module = importlib.util.module_from_spec(spec)
            # The retained entrypoints are POSIX tools; this shim tests their
            # orchestration on Windows without claiming a native GL run.
            with mock.patch.dict(sys.modules, {'fcntl': types.SimpleNamespace(LOCK_EX=2, flock=mock.Mock())}), mock.patch.object(sys, 'path', [str(ROOT / 'tests'), *sys.path]):
                spec.loader.exec_module(module)
            runner = getattr(module, 'runner', module)
            calls = []
            marker = entry.upper() + '_UI_RESULT'
            def process(command, **kwargs):
                if command[0] == 'git':
                    return subprocess.CompletedProcess(command, 0, stdout='source-identity\n')
                calls.append(command)
                for key in ['HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
                    self.assertTrue(Path(kwargs['env'][key]).is_relative_to(Path(command[command.index('--path') + 1]).parent / 'profiles'))
                data = b''
                if '--script' in command:
                    resource = command[command.index('--script') + 1]
                    expected = 'res://tests/building/test_' + entry + '_ui.gd'
                    capture = native and len(calls) == (3 if cache else 4)
                    if capture and entry == 'build_tiles':
                        expected = 'res://tests/diagnostics/capture_build_tiles_ui.gd'
                    self.assertEqual(resource, expected)
                    self.assertEqual('--headless' not in command, len(calls) > (1 if cache else 2))
                    self.assertEqual(command[command.index('--') + 1:], ['--visual-qa', '--fresh-review', '--skip-intro'])
                    selected_marker = 'BUILD_TILES_CAPTURE_RESULT' if capture and entry == 'build_tiles' else marker
                    data = (selected_marker + ' {"checks":1,"failures":[]}\n').encode() if payload != 'missing' else b''
                    if payload == 'duplicate':
                        data *= 2
                return subprocess.CompletedProcess(command, 0, stdout=data)
            argv = ['runner', '--output', str(output), '--lock', str(Path(directory) / 'lock')]
            if native:
                argv.append('--native')
            if cache:
                argv.extend(['--import-cache', str(root)])
            with mock.patch.object(runner, 'ROOT', root), mock.patch.object(runner.subprocess, 'run', side_effect=process), mock.patch.object(runner, 'native_display', return_value=mock.MagicMock(__enter__=lambda _: {'DISPLAY': ':synthetic'}, __exit__=lambda *_: False)), mock.patch('sys.argv', argv), mock.patch('builtins.print'):
                if payload == 'valid':
                    module.main()
                else:
                    with self.assertRaisesRegex(RuntimeError, 'Missing or invalid result'):
                        module.main()
            report = json.loads((output / 'summary.json').read_text())
            self.assertEqual(report['status'], 'passed' if payload == 'valid' else 'failed')
            self.assertFalse(report['player_save_used'])
            self.assertFalse(report['browser_verified'])
            if payload == 'valid':
                self.assertEqual(report['native_render_verified'], native)
                self.assertEqual(report['clean_import_verified'], not cache)
                self.assertEqual([r['log'] for r in report['records']], ([] if cache else ['import.log']) + ['headless.log'] + (['native.log', 'capture.log'] if native else []))
                self.assertEqual(report['source_commit'], 'source-identity')
                if cache:
                    receipt = json.loads((output / 'import-cache-receipt.json').read_text())
                    self.assertTrue(receipt['assets_and_import_metadata_verified'])
                    self.assertEqual(receipt['copied_only'], '.godot/imported')
                    self.assertFalse(receipt['clean_import_verified'])

    def test_entrypoints_preserve_headless_native_capture_and_cache_receipts(self):
        for entry in ['build_tiles', 'shell_segment']:
            for native, cache in [(False, False), (True, False), (True, True)]:
                with self.subTest(entry=entry, native=native, cache=cache):
                    self.exercise(entry, native, cache=cache)

    def test_missing_and_duplicate_results_remain_rejected(self):
        for entry in ['build_tiles', 'shell_segment']:
            for payload in ['missing', 'duplicate']:
                with self.subTest(entry=entry, payload=payload):
                    self.exercise(entry, payload=payload)
