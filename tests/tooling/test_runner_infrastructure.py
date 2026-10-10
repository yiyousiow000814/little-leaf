"""Synthetic runner contracts; never launch an engine or read player profiles."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]

class RunnerInfrastructureTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('isolated_candidate_runner', ROOT / 'tests/run_integration_candidate.py')
        self.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.runner)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'source'
        (self.root / 'scripts').mkdir(parents=True)
        (self.root / 'tests').mkdir()
        (self.root / 'scripts/cafe_web_save.gd').write_text('const STAGING_FILE="/tmp/little_leaf_vault_staging.json"\n')
        (self.root / 'tests/test_floor_claim_retry.gd').write_text('# Synthetic fixture only\n')
        self.runner.ROOT = self.root
        self.output = Path(self.temp.name) / 'output'
        self.argv = ['runner', '--output', str(self.output), '--only', 'test_floor_claim_retry', '--lock', str(Path(self.temp.name) / 'lock')]

    def run_synthetic(self, windows=False):
        commands = []
        def run(command, **kwargs):
            if command[0] == 'git':
                return subprocess.CompletedProcess(command, 0, stdout='synthetic-source\n')
            commands.append((command, kwargs['env']))
            script = '--script' in command
            return subprocess.CompletedProcess(command, 0, stdout=b'FLOOR_CLAIM_RETRY_RESULT {"checks":1,"failures":[]}\n' if script else b'')
        self.runner.os = types.SimpleNamespace(name='nt' if windows else 'posix', environ={})
        self.runner.msvcrt = types.SimpleNamespace(LK_LOCK=1, locking=mock.Mock())
        with mock.patch('sys.argv', self.argv), mock.patch.object(self.runner.subprocess, 'run', side_effect=run), mock.patch('builtins.print'):
            self.runner.main()
        report = json.loads((self.output / 'summary.json').read_text())
        self.assertEqual(report['status'], 'passed')
        self.assertFalse(report['disposable_fixture_retained'])
        self.assertFalse(report['player_save_used'])
        self.assertIn('scripts/cafe_web_save.gd', report['source_sha256'])
        for command, env in commands:
            self.assertEqual(command[1:4], ['--headless', '--audio-driver', 'Dummy'])
            for key in ['HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
                self.assertTrue(Path(env[key]).is_relative_to(self.root / 'qa-project'))
                self.assertNotIn('\\', env[key])
            if windows:
                self.assertEqual(len({env[key] for key in ['HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']}), 1)
                self.assertTrue(env['APPDATA'].endswith('/windows-data'))
        if windows:
            self.runner.msvcrt.locking.assert_called_once()
        return report

    def test_posix_dummy_audio_and_disposable_profile_cleanup(self):
        self.run_synthetic()

    def test_windows_lock_and_shared_normalized_data_directory(self):
        self.run_synthetic(windows=True)

    def test_historical_workflow_keeps_lock_outside_parent_checkout(self):
        workflow = (ROOT / '.github/workflows/build-web.yml').read_text()
        commands = [shlex.split(line.strip()) for line in workflow.splitlines()
                    if line.strip().startswith('python3 .compatibility-old/tests/run_integration_candidate.py ')]
        self.assertEqual(len(commands), 1)
        self.assertNotIn('--only', commands[0])
        workspace = Path(self.temp.name) / 'checkout'
        workspace.mkdir()
        historical_root = workspace / '.compatibility-old'
        self.root.rename(historical_root)
        self.root = self.runner.ROOT = historical_root
        runner_temp = Path(self.temp.name) / 'runner-temp'
        runner_temp.mkdir()
        self.output = runner_temp / 'old-engine-evidence'
        self.argv = ['runner', *[part.replace('$RUNNER_TEMP', str(runner_temp))
                                 for part in commands[0][2:]]]
        self.run_synthetic()
        self.assertFalse((workspace / '.little-leaf-engine.lock').exists())
        self.assertTrue((runner_temp / 'old-engine.lock').is_file())

    def test_symlink_fixture_root_is_rejected(self):
        outside = Path(self.temp.name) / 'outside'
        outside.mkdir()
        (self.root / 'qa-project').symlink_to(outside, target_is_directory=True)
        with mock.patch('sys.argv', self.argv), self.assertRaisesRegex(RuntimeError, 'cannot be a symlink'):
            self.runner.main()
        self.assertEqual(list(outside.iterdir()), [])

    def test_escaped_fixture_is_rejected_before_copying(self):
        outside = Path(self.temp.name) / 'outside'
        outside.mkdir()
        with mock.patch('sys.argv', self.argv), mock.patch.object(self.runner.tempfile, 'TemporaryDirectory') as temporary, mock.patch.object(self.runner.shutil, 'copytree') as copy:
            temporary.return_value.__enter__.return_value = str(outside)
            with self.assertRaisesRegex(RuntimeError, 'escaped its reviewed root'):
                self.runner.main()
            copy.assert_not_called()

class WorkflowInfrastructureTests(unittest.TestCase):
    def test_parallel_gates_keep_lifecycle_browser_channels_and_single_exports(self):
        workflow = (ROOT / '.github/workflows/build-web.yml').read_text()
        self.assertIn('node tests/web_performance_lifecycle.js', workflow)
        browser = workflow.split('  browser:\n', 1)[1].split('  firebase:\n', 1)[0]
        self.assertLess(browser.index('Install shared pinned browser tools'), browser.index('Verify compensation history'))
        self.assertIn('PLAYWRIGHT_CHROMIUM_CHANNEL: chrome', browser)
        self.assertIn('RUNTIME_BROWSER: webkit', browser)
        self.assertIn('lane: [play, compatibility, recovery]', browser)
        self.assertIn('max-parallel: 4', workflow)
        self.assertIn('max-parallel: 3', browser)
        self.assertEqual(workflow.count('python3 tools/build_web.py --output'), 1)
        self.assertEqual(workflow.count('python3 tools/build_crazygames.py --validated-web-build'), 1)
        self.assertIn('needs: [guard, engine]', workflow)
        self.assertIn('needs: [guard, engine, historical, build, browser, firebase]', workflow)
        self.assertIn('test "$result" = success || exit 1', workflow)
        self.assertNotIn('continue-on-error:', workflow)

if __name__ == '__main__':
    unittest.main()
