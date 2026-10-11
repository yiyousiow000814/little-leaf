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

    def run_synthetic(self, windows=False, script_run=None):
        commands = []
        def run(command, **kwargs):
            if command[0] == 'git':
                return subprocess.CompletedProcess(command, 0, stdout='synthetic-source\n')
            commands.append((command, kwargs['env'].copy()))
            script = '--script' in command
            output = script_run(command, kwargs['env']) if script and script_run else b'FLOOR_CLAIM_RETRY_RESULT {"checks":1,"failures":[]}\n'
            return subprocess.CompletedProcess(command, 0, stdout=output if script else b'')
        self.runner.os = types.SimpleNamespace(name='nt' if windows else 'posix', environ={})
        self.runner.msvcrt = types.SimpleNamespace(LK_LOCK=1, locking=mock.Mock())
        if os.name == 'nt':
            self.runner.fcntl = types.SimpleNamespace(LOCK_EX=2, flock=mock.Mock())
        with mock.patch('sys.argv', self.argv), mock.patch.object(self.runner.subprocess, 'run', side_effect=run), mock.patch('builtins.print'):
            self.runner.main()
        report = json.loads((self.output / 'summary.json').read_text())
        self.assertEqual(report['status'], 'passed')
        self.assertFalse(report['disposable_fixture_retained'])
        self.assertFalse(report['player_save_used'])
        self.assertIn('scripts/cafe_web_save.gd', report['source_sha256'])
        for command, env in commands:
            self.assertEqual(command[1:4], ['--headless', '--audio-driver', 'Dummy'])
            self.assertNotIn('--fixed-fps', command, 'Unreviewed suites must keep their original pacing')
            for key in ['HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
                self.assertTrue(Path(env[key]).is_relative_to(self.root / 'qa-project'))
                self.assertNotIn('\\', env[key])
            if windows:
                self.assertEqual(len({env[key] for key in ['HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']}), 1)
                self.assertTrue(env['APPDATA'].endswith('/windows-data'))
        if windows:
            self.runner.msvcrt.locking.assert_called_once()
        return report

    def select(self, *names):
        self.output = Path(self.temp.name) / ('output-' + names[0])
        for name in names:
            (self.root / 'tests' / (name.replace('staff-start', 'test_staff_start') + '.gd')).touch()
        self.argv = ['runner', '--output', str(self.output), '--only', *names, '--lock', str(Path(self.temp.name) / 'lock')]

    def test_autosave_and_intro_reject_ordinary_save_names(self):
        for script in ['test_autosave_feedback', 'test_autosave_feedback_adversarial', 'test_autosave_feedback_ui',
                       'test_no_bottom_notifications', 'test_hud_layout', 'test_startup_retry',
                       'test_starter_geometry', 'test_intro_lifecycle_headless', 'test_intro_cli_bypass']:
            with self.subTest(script=script):
                self.select(script)
                def write_save(command, env):
                    (Path(env['APPDATA']) / 'little_leaf_cafe_layout_motion_v15.json').write_text('{}')
                    return (dict(self.runner.SUITES)[script] + ' {"checks":1,"failures":[]}\n').encode()
                with self.assertRaisesRegex(RuntimeError, 'Unexpected regular save filename'):
                    self.run_synthetic(windows=True, script_run=write_save)
                self.assertEqual(json.loads((self.output / 'summary.json').read_text())['status'], 'failed')

    def test_litter_requires_complete_matching_results_and_minimum_checks(self):
        for index, (checks, failures, evidence_checks) in enumerate([
                (56, [], 56), (55, [], 55), (56, None, 56), (56, [], 57), (56, [], None)]):
            with self.subTest(checks=checks, failures=failures, evidence_checks=evidence_checks):
                self.select('test_customer_litter')
                self.output = self.output.with_name('litter-' + str(index))
                self.argv[2] = str(self.output)
                def litter_result(command, env):
                    payload = {'checks': checks, **({'failures': failures} if failures is not None else {})}
                    if evidence_checks is not None:
                        Path(env['LL_LITTER_EVIDENCE']).write_text(json.dumps({**payload, 'checks': evidence_checks}))
                    return (json.dumps(payload) + '\n').encode()
                if index == 0:
                    self.run_synthetic(windows=True, script_run=litter_result)
                else:
                    with self.assertRaises((RuntimeError, FileNotFoundError)):
                        self.run_synthetic(windows=True, script_run=litter_result)

    def test_intro_and_tutorial_flags_preserve_the_intended_entry_paths(self):
        expected = {
            'test_intro_lifecycle_headless': ['--visual-qa', '--fresh-review', '--skip-tutorial'],
            'test_intro_cli_bypass': ['--visual-qa', '--fresh-review', '--skip-tutorial', '--skip-intro'],
            'test_interactive_tutorial': ['--visual-qa', '--fresh-review', '--skip-intro'],
            'test_autosave_feedback': ['--skip-intro'],
            'test_autosave_feedback_adversarial': ['--skip-intro'],
        }
        self.select(*expected)
        def check_flags(command, env):
            script = Path(command[command.index('--script') + 1]).stem
            flags = command[command.index('--') + 1:]
            self.assertEqual(flags, expected[script])
            return (dict(self.runner.SUITES)[script] + ' {"checks":1,"failures":[]}\n').encode()
        self.run_synthetic(windows=True, script_run=check_flags)

    def test_staff_starts_share_ordered_generated_saves(self):
        self.select('staff-start')
        nested = self.root / 'tests/staff'
        nested.mkdir()
        (self.root / 'tests/test_staff_start.gd').rename(nested / 'test_staff_start.gd')
        cases, profiles = [], set()
        def staff_start(command, env):
            self.assertEqual(command[command.index('--script') + 1], 'res://tests/staff/test_staff_start.gd')
            case = env['LL_START_CASE']
            cases.append(case)
            profiles.add(env['APPDATA'])
            save_dir = Path(env['APPDATA']) / 'Godot/app_userdata/Little Leaf Cafe'
            save_dir.mkdir(parents=True, exist_ok=True)
            save_file = save_dir / 'little_leaf_cafe_layout_motion_v15.json'
            expected = {'saved-load': 'roundtrip', 'standalone-load': 'standalone', 'bad-load': 'not a valid cafe'}
            if case in expected:
                self.assertEqual(save_file.read_text(), expected[case])
            else:
                self.assertFalse(save_file.exists())
                for fixture in ['roundtrip', 'standalone']:
                    (save_dir / ('staff-start-' + fixture + '.json')).write_text(fixture)
            self.assertEqual('--fresh-review' in command, case == 'fresh')
            return b'STAFF_START_RESULT {"checks":1,"failures":[]}\n'
        self.run_synthetic(windows=True, script_run=staff_start)
        self.assertEqual(cases, ['empty-profile', 'fresh', 'saved-load', 'standalone-load', 'bad-load'])
        self.assertEqual(len(profiles), 1)

    def test_nested_suite_preserves_id_receipts_and_cli(self):
        nested = self.root / 'tests/service'
        nested.mkdir()
        (self.root / 'tests/test_floor_claim_retry.gd').rename(nested / 'test_floor_claim_retry.gd')
        def check_resource(command, env):
            self.assertEqual(command[command.index('--script') + 1],
                             'res://tests/service/test_floor_claim_retry.gd')
            self.assertTrue(env['LL_UI_RESULT'].endswith('test_floor_claim_retry-result.json'))
            return b'FLOOR_CLAIM_RETRY_RESULT {"checks":1,"failures":[]}\n'
        report = self.run_synthetic(script_run=check_resource)
        self.assertEqual(report['records'][-1]['test'], 'test_floor_claim_retry')
        self.assertEqual(report['records'][-1]['log'], 'test_floor_claim_retry.log')

    def test_duplicate_resource_and_missing_selected_suite_fail_before_staging(self):
        nested = self.root / 'tests/service'
        nested.mkdir()
        duplicate = nested / 'test_floor_claim_retry.gd'
        duplicate.touch()
        with mock.patch('sys.argv', self.argv), mock.patch.object(self.runner, 'stage_project') as stage:
            with self.assertRaises(SystemExit), mock.patch('sys.stderr'):
                self.runner.main()
            stage.assert_not_called()
        duplicate.unlink()
        (self.root / 'tests/test_floor_claim_retry.gd').unlink()
        with mock.patch('sys.argv', self.argv), mock.patch.object(self.runner, 'stage_project') as stage:
            with self.assertRaises(SystemExit), mock.patch('sys.stderr'):
                self.runner.main()
            stage.assert_not_called()

    def test_canonical_map_covers_existing_suites_and_rejects_duplicate_ids(self):
        resources = self.runner.suite_resources(ROOT)
        self.assertEqual(set(resources), {name for name, _ in self.runner.SUITES} | {'staff-start'})
        with mock.patch.object(self.runner, 'SUITES', self.runner.SUITES + [self.runner.SUITES[0]]):
            with self.assertRaisesRegex(ValueError, 'Duplicate canonical suite ID'):
                self.runner.suite_resources(ROOT)

    def test_posix_dummy_audio_and_disposable_profile_cleanup(self):
        self.run_synthetic()

    def test_windows_lock_and_shared_normalized_data_directory(self):
        self.run_synthetic(windows=True)

    def test_unpaced_ui_does_not_change_other_suites(self):
        self.argv.append('--unpaced-ui')
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
        self.assertIn('node tests/rendering/web_performance_lifecycle.js', workflow)
        browser = workflow.split('  browser:\n', 1)[1].split('  firebase:\n', 1)[0]
        self.assertLess(browser.index('Install shared pinned browser tools'), browser.index('Verify compensation history'))
        self.assertIn('PLAYWRIGHT_CHROMIUM_CHANNEL: chrome', browser)
        self.assertIn('RUNTIME_BROWSER: webkit', browser)
        self.assertIn('lane: [play, recovery]', browser)
        self.assertIn('lane: [compatibility]', browser)
        self.assertIn('max-parallel: 5', workflow)
        self.assertIn('max-parallel: 2', browser)
        play = browser.split('  compatibility:\n', 1)[0]
        self.assertIn('needs: build', play)
        self.assertNotIn('old-web-build', play)
        self.assertIn('needs: [build, historical]', browser)
        self.assertIn('case: [old_opened_after_new, already_open_old]', browser)
        self.assertIn('--case ${{ matrix.case }}', browser)
        self.assertIn('little-leaf-browser-${{ matrix.lane }}-${{ matrix.case }}-', browser)
        self.assertNotIn('Verify compensation history', play)
        self.assertIn("matrix.case == 'old_opened_after_new'", browser)
        self.assertNotIn('inbox_pid', workflow)
        self.assertEqual(workflow.count('node tests/rendering/wall_compatibility_parallel.js --merge'), 2)
        gate = workflow.split('  gate:\n', 1)[1]
        self.assertLess(gate.index('actions/checkout@'), gate.index('--merge'))
        firebase = workflow.split('  firebase:\n', 1)[1].split('  gate:\n', 1)[0]
        self.assertLess(firebase.index('--merge'), firebase.index('tools/build_firebase.py'))
        self.assertEqual(workflow.count('python3 tools/build_web.py --output'), 1)
        self.assertEqual(workflow.count('python3 tools/build_crazygames.py --validated-web-build'), 1)
        self.assertIn('needs: [guard, engine]', workflow)
        self.assertIn('needs: [guard, engine, historical, build, browser, compatibility, firebase]', workflow)
        self.assertIn('"$BUILD" "$BROWSER" "$COMPATIBILITY";', workflow)
        self.assertIn('test "$result" = success || exit 1', workflow)
        self.assertNotIn('continue-on-error:', workflow)

if __name__ == '__main__':
    unittest.main()
