"""Run the pinned historical CLI only through lock acquisition in isolated Git repos.

The old script is read from Git at test time, never copied into the source tree.
No engine, browser, export, saved game, or historical evidence is consumed.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

import build_firebase

ROOT = Path(__file__).resolve().parents[2]


class StopAfterLock(Exception):
    pass


@unittest.skipIf(os.name == 'nt', 'The pinned historical CLI and CI runner use fcntl')
class HistoricalEngineLockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        contract = json.loads((ROOT / 'tests/fixtures/wall-compatibility/contract.json').read_text())
        cls.old_commit = contract['old_commit']
        cls.old_source = subprocess.check_output([
            'git', '-C', str(ROOT), 'show',
            cls.old_commit + ':tests/run_integration_candidate.py'], text=True)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='historical-lock-regression-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'checkout'
        self.repo.mkdir()
        self.runner_temp = self.base / 'runner-temp'
        self.runner_temp.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        (self.repo / '.gitignore').write_bytes((ROOT / '.gitignore').read_bytes())
        (self.repo / 'tracked.txt').write_text('synthetic unchanged source\n')
        self.git('add', '.gitignore', 'tracked.txt')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-qm', 'Synthetic fixture')
        old = self.repo / '.compatibility-old'
        (old / 'tests').mkdir(parents=True)
        file = old / 'tests/run_integration_candidate.py'
        file.write_text(self.old_source)
        self.runner = types.ModuleType('historical_engine_lock_fixture')
        self.runner.__file__ = str(file)
        exec(compile(self.old_source, str(file), 'exec'), self.runner.__dict__)
        self.assertEqual(self.git('status', '--porcelain'), '')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True).strip()

    def acquire_lock(self, explicit=None, environment_lock=None):
        args = [self.runner.__file__, '--output', str(self.runner_temp / 'engine-evidence')]
        if explicit is not None:
            args += ['--lock', str(explicit)]
        env = os.environ.copy()
        env.pop('LL_ENGINE_LOCK', None)
        if environment_lock is not None:
            env['LL_ENGINE_LOCK'] = str(environment_lock)
        # The actual historical CLI creates and locks its real file first.
        # Stop at the very next operation, before copying a project or running Godot.
        with patch.object(sys, 'argv', args), patch.dict(os.environ, env, clear=True), \
                patch.object(self.runner.tempfile, 'TemporaryDirectory', side_effect=StopAfterLock):
            with self.assertRaises(StopAfterLock):
                self.runner.main()

    def test_historical_default_dirties_parent_checkout(self):
        self.acquire_lock()
        self.assertTrue((self.repo / '.little-leaf-engine.lock').is_file())
        self.assertEqual(self.git('status', '--porcelain'), '?? .little-leaf-engine.lock')
        print('Historical default lock reproduces: ?? .little-leaf-engine.lock')

    def test_explicit_runner_temp_lock_keeps_checkout_clean(self):
        lock = self.runner_temp / 'old-engine.lock'
        self.acquire_lock(explicit=lock)
        self.assertTrue(lock.is_file())
        self.assertFalse((self.repo / '.little-leaf-engine.lock').exists())
        self.assertEqual(self.git('status', '--porcelain'), '')
        print('Explicit RUNNER_TEMP lock: checkout remains clean; lock remains outside checkout')

    def test_explicit_lock_overrides_environment_without_creating_parent_lock(self):
        lock = self.runner_temp / 'old-engine.lock'
        inherited = self.repo / 'inherited-engine.lock'
        self.acquire_lock(explicit=lock, environment_lock=inherited)
        self.assertTrue(lock.is_file())
        self.assertFalse(inherited.exists())
        self.assertEqual(self.git('status', '--porcelain'), '')

    def assert_dirty_source_blocked(self, file, content):
        target = self.repo / file
        target.write_text(content)
        before = self.git('status', '--porcelain')
        args = ['build_firebase.py', '--validated-web-build', 'missing-build',
                '--output', str(self.runner_temp / 'staged'), '--public-config', 'missing-config']
        with patch.object(sys, 'argv', args), patch.object(build_firebase, 'ROOT', self.repo), \
                patch.object(build_firebase, 'validate_web_gate') as gate, \
                patch.object(build_firebase, 'stage') as stage:
            with self.assertRaisesRegex(RuntimeError, 'Commit/review all source before staging'):
                build_firebase.main()
        gate.assert_not_called()
        stage.assert_not_called()
        self.assertEqual(target.read_text(), content)
        self.assertEqual(self.git('status', '--porcelain'), before)
        self.assertFalse((self.runner_temp / 'staged').exists())

    def test_dirty_tracked_source_still_blocks_staging(self):
        self.assert_dirty_source_blocked('tracked.txt', 'changed source\n')

    def test_dirty_untracked_source_still_blocks_staging(self):
        self.assert_dirty_source_blocked('untracked.txt', 'new source\n')

    def test_workflow_uses_explicit_external_lock_and_retains_source_guard(self):
        workflow = (ROOT / '.github/workflows/build-web.yml').read_text()
        command = next(line.strip() for line in workflow.splitlines()
                       if line.strip().startswith('python3 .compatibility-old/tests/run_integration_candidate.py'))
        self.assertEqual(command, 'python3 .compatibility-old/tests/run_integration_candidate.py '
                         '--output "$RUNNER_TEMP/old-engine-evidence" --lock "$RUNNER_TEMP/old-engine.lock"')
        self.assertIn('ref: ' + self.old_commit, workflow)
        self.assertIn("git('status','--porcelain')", (ROOT / 'tools/build_firebase.py').read_text())
        self.assertNotIn('.little-leaf-engine.lock', (ROOT / '.gitignore').read_text())
        self.assertNotIn('git clean', workflow)
        self.assertNotIn('git reset', workflow)


if __name__ == '__main__':
    unittest.main()
