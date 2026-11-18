"""Verify the ordinary PR pilot never changes the complete qualification contract."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import yaml

from tools.ci import engine_shards as shards

ROOT = Path(__file__).resolve().parents[2]


class NineEngineShardsTests(unittest.TestCase):
    def test_ordinary_pr_only_fanout_and_literal_non_pr_matrix(self):
        jobs = yaml.safe_load((ROOT / '.github/workflows/build-web.yml').read_text())['jobs']
        guard, engine, build = (jobs[k] for k in ('guard', 'engine', 'build'))
        selection = next(s for s in guard['steps'] if s.get('id') == 'engine_plan')
        self.assertEqual(selection['env']['ORDINARY_PR'], jobs['play']['env']['PLAY_LOCKED_PROVISION'])
        self.assertEqual(guard['outputs']['engine_count'], '${{ steps.engine_plan.outputs.count }}')
        self.assertEqual(guard['outputs']['engine_matrix'], '${{ steps.engine_plan.outputs.matrix }}')
        self.assertEqual(engine['strategy']['matrix']['shard'], '${{ fromJSON(needs.guard.outputs.engine_matrix) }}')
        self.assertEqual(engine['strategy']['max-parallel'], '${{ fromJSON(needs.guard.outputs.engine_count) }}')
        self.assertEqual(engine['needs'], 'guard')
        self.assertEqual(build['needs'], ['guard', 'preflight', 'engine'])
        for job, verb in ((engine, 'run'), (build, 'merge')):
            command = next(s for s in job['steps'] if 'engine_shards.py ' + verb in s.get('run', ''))
            self.assertEqual(command['env']['ENGINE_COUNT'], '${{ needs.guard.outputs.engine_count }}')
            self.assertIn('--count "$ENGINE_COUNT"', command['run'])
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / 'out'
            for event, count in (('true', 9), ('false', 5)):
                subprocess.run(['bash', '-c', selection['run']], check=True,
                               env={**os.environ, 'ORDINARY_PR': event, 'GITHUB_OUTPUT': str(dest)})
                output = dict(row.split('=', 1) for row in dest.read_text().splitlines())
                self.assertEqual(int(output['count']), count)
                self.assertEqual(json.loads(output['matrix']), list(range(count)))
                dest.unlink()
            refused = subprocess.run(['bash', '-c', selection['run']], capture_output=True,
                                    env={**os.environ, 'ORDINARY_PR': '', 'GITHUB_OUTPUT': str(dest)})
            self.assertNotEqual(refused.returncode, 0)
            self.assertFalse(dest.exists())

    def test_five_runner_weights_unchanged_and_nine_runner_assignment_is_complete(self):
        names = shards.suite_names()
        stable = json.loads((ROOT / 'tools/ci/engine_suite_times.json').read_text())['seconds']
        pilot = json.loads((ROOT / 'tools/ci/engine_suite_times_pr9.json').read_text())['seconds']
        self.assertEqual(shards.plan(5), shards.plan(5, names, stable))
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(set(pilot), set(names))
        bins = shards.plan(9)
        self.assertEqual(len(bins), 9)
        self.assertEqual(sorted(sum(bins, [])), sorted(names))
        self.assertTrue(all(bins))
        self.assertEqual(sum('staff-start' in b for b in bins), 1)
        for count in (6, 7, 8, 10):
            with self.assertRaises(ValueError):
                shards.plan(count)

    def test_nine_reports_require_all_imports_staff_and_current_attempt(self):
        names = shards.suite_names()
        assignments = shards.plan(9)
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(
                os.environ, {'GITHUB_RUN_ID': 'piloted', 'GITHUB_RUN_ATTEMPT': '2'}):
            folder = Path(directory)
            paths = []
            for i, suites in enumerate(assignments):
                work = folder / str(i)
                work.mkdir()
                path = work / 'summary.json'
                rows = [{
                    'test': name, 'checks': 0 if name == 'import' else 1,
                    'exit_code': 0, 'failures': [], 'diagnostics': [],
                } for name in sorted(shards.expected_records(suites) | {'import'})]
                packet = {
                    'status': 'passed', 'source_commit': 'exact', 'source_sha256': {'source': 'bound'},
                    'player_save_used': False, 'workflow_run': 'piloted', 'workflow_attempt': '2',
                    'shard': {'index': i, 'count': 9, 'suites': suites}, 'records': rows,
                    'total_checks': len(rows) - 1, 'disposable_fixture_retained': False,
                }
                path.write_text(json.dumps(packet))
                (work / 'import.log').write_text(str(i))
                paths.append(path)
            refused = folder / 'must-not-exist'
            for invalid in (paths[:-1], paths[:-1] + [paths[0]]):
                with self.assertRaises(ValueError):
                    shards.merge_reports(invalid, 9, 'exact', refused)
            staff_shard = next(i for i, suite in enumerate(assignments) if 'staff-start' in suite)
            path = paths[staff_shard]
            original = path.read_text()
            for mutation in (
                    lambda p: p.update(workflow_attempt='1'),
                    lambda p: p.update(source_commit='foreign'),
                    lambda p: p['shard'].update(count=5),
                    lambda p: p.update(records=[r for r in p['records'] if r['test'] != 'import']),
                    lambda p: p.update(records=[r for r in p['records'] if r['test'] != 'staff-start-bad-load']),
                    lambda p: next(r for r in p['records'] if r['test'] == 'import')['diagnostics'].append('ERROR: unsafe import')):
                packet = json.loads(original)
                mutation(packet)
                path.write_text(json.dumps(packet))
                with self.assertRaises(ValueError):
                    shards.merge_reports(paths, 9, 'exact', refused)
                self.assertFalse(refused.exists())
            path.write_text(original)
            dest = folder / 'accepted'
            result = shards.merge_reports(paths, 9, 'exact', dest)
            self.assertEqual({r['test'] for r in result['records']}, shards.expected_records(names) | {'import'})
            self.assertEqual(sum(r['test'] == 'import' for r in result['records']), 1)
            self.assertEqual({p.read_text() for p in dest.glob('*import.log')}, {str(i) for i in range(9)})
            self.assertEqual(result['workflow_attempt'], '2')
            self.assertNotIn('shard', result)


if __name__ == '__main__':
    unittest.main()
