"""Adversarial coverage and source binding checks; no engine/browser execution."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('engine_shards', ROOT / 'tools/engine_shards.py')
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)


class EngineShardTests(unittest.TestCase):
    def setUp(self):
        environment = mock.patch.dict('os.environ', {'GITHUB_RUN_ID': 'local', 'GITHUB_RUN_ATTEMPT': 'local'})
        environment.start()
        self.addCleanup(environment.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.names = ['one', 'two', 'three', 'staff-start']
        self.timing = {'one': 80, 'two': 40, 'three': 30, 'staff-start': 10}
        self.assignments = shards.plan(2, self.names, self.timing)
        self.paths = []
        for index, names in enumerate(self.assignments):
            folder = self.root / str(index)
            folder.mkdir()
            path = folder / 'summary.json'
            report = {'status': 'passed', 'source_commit': 'same-source',
                      'player_save_used': False, 'source_sha256': {'source': 'digest'},
                      'workflow_run': 'local', 'workflow_attempt': 'local',
                      'shard': {'index': index, 'count': 2, 'suites': names},
                      'disposable_fixture_retained': False,
                      'records': [{'test': name, 'checks': 1 if name != 'import' else 0,
                                   'exit_code': 0, 'failures': [], 'diagnostics': []}
                                  for name in sorted(shards.expected_records(names) | {'import'})]}
            report['total_checks'] = sum(row['checks'] for row in report['records'])
            path.write_text(json.dumps(report))
            self.paths.append(path)

    def merge(self):
        with mock.patch.object(shards, 'suite_names', return_value=self.names), mock.patch.object(shards, 'plan', return_value=self.assignments):
            return shards.merge_reports(self.paths, 2, 'same-source', self.root / 'merged')

    def mutate(self, apply):
        report = json.loads(self.paths[1].read_text())
        apply(report)
        self.paths[1].write_text(json.dumps(report))

    def test_balanced_complete_plan_and_new_suites(self):
        plan = shards.plan(5)
        flattened = sum(plan, [])
        self.assertEqual(set(flattened), set(shards.suite_names()))
        self.assertEqual(len(flattened), len(set(flattened)))
        self.assertIn('new-suite', sum(shards.plan(2, self.names + ['new-suite'], self.timing), []))
        with self.assertRaises(ValueError): shards.plan(6)

    def test_staff_starts_remain_together_and_complete(self):
        result = self.merge()
        self.assertEqual({r['test'] for r in result['records']}, shards.expected_records(self.names) | {'import'})
        self.assertEqual(len([r for r in result['records'] if r['test'] == 'import']), 1)
        self.assertEqual(result['total_checks'], 8)

    def test_missing_shard_fails(self):
        self.paths.pop()
        with self.assertRaisesRegex(ValueError, 'mandatory'): self.merge()

    def test_wrong_source_and_run_fail(self):
        for key, value in [('source_commit', 'other'), ('workflow_attempt', 'other'), ('player_save_used', True), ('source_sha256', {'source': 'other'})]:
            original = self.paths[1].read_text()
            with self.subTest(key=key):
                self.mutate(lambda r: r.update({key: value}))
                with self.assertRaises(ValueError): self.merge()
            self.paths[1].write_text(original)

    def test_skipped_failed_duplicate_and_missing_suite_fail(self):
        changes = [lambda r: r.update(status='failed'),
                   lambda r: r['records'].pop(),
                   lambda r: r['records'].append(r['records'][0]),
                   lambda r: r['records'][0].update(exit_code=1),
                   lambda r: r['shard'].update(index=0)]
        for change in changes:
            original = self.paths[1].read_text()
            self.mutate(change)
            with self.assertRaises(ValueError): self.merge()
            self.paths[1].write_text(original)

    def test_error_in_deduplicated_import_cannot_disappear(self):
        self.mutate(lambda r: next(row for row in r['records'] if row['test'] == 'import')['diagnostics'].append('ERROR: synthetic import failure'))
        with self.assertRaisesRegex(ValueError, 'diagnostics'): self.merge()


if __name__ == '__main__':
    unittest.main()
