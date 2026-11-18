"""Contract for source-bound independent recovery gates; no browsers or services started."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml
from ci import verify_source_recovery as source
from qualification import reuse_main_ci

ROOT = Path(__file__).resolve().parents[2]


class SplitTests(unittest.TestCase):
    def test_each_result_gates_both_consumers_and_release(self):
        jobs = yaml.safe_load((ROOT/'.github/workflows/build-web.yml').read_text())['jobs']
        src, browser = jobs['source_recovery'], jobs['browser']
        self.assertEqual(src['needs'], 'guard')
        self.assertEqual(src['if'], "needs.guard.outputs.scope != 'lightweight'")
        self.assertEqual(browser['needs'], 'build')
        self.assertEqual(browser['strategy']['matrix']['lane'], ['play', 'save', 'recovery'])
        self.assertEqual(browser['strategy']['max-parallel'], 3)
        srcsteps = {s.get('name'): s for s in src['steps']}
        self.assertTrue(all('if' not in srcsteps[n] for n in srcsteps if n and n.startswith('Verify')))
        steps = {s.get('name'):s for s in browser['steps']}
        for name, selector, budget in [('Verify exported save diagnostic in sandboxed Chromium','save',5),
            ('Verify closed-connection recovery in actual exported WebKit game','recovery',9),
            ('Verify fresh tutorial and natural first payment in ordinary Web','play',6)]:
            self.assertEqual(steps[name]['if'], "matrix.lane == '%s'" % selector)
            self.assertEqual(steps[name]['timeout-minutes'], budget)
        for name in ('Install exact checksum-pinned Chrome for ordinary browser gates',
                     'Activate and verify the pinned Chrome channel'):
            self.assertEqual(steps[name]['if'], "matrix.lane != 'recovery'")
        self.assertFalse(any('download-artifact' in s.get('uses','') for s in src['steps']))
        for job in ('gate','firebase'):
            self.assertIn('source_recovery', jobs[job]['needs'])
            self.assertIn('browser', jobs[job]['needs'])
            receipts = [s for s in jobs[job]['steps'] if s.get('name') == "Download this run's exact source recovery receipts"]
            self.assertEqual(len(receipts), 1)
            self.assertEqual(receipts[0]['with']['artifact-ids'], '${{ needs.source_recovery.outputs.evidence_id }}')
            self.assertEqual(receipts[0]['with']['digest-mismatch'], 'error')
            self.assertIn('verify_source_recovery.py', json.dumps(jobs[job]['steps']))
        self.assertEqual(srcsteps['Retain exact source-only recovery evidence']['with']['if-no-files-found'], 'error')
        for label in ('web / source_recovery', 'web / browser (save)', 'web / browser (recovery)'):
            good = [dict(name=n, status='completed', conclusion='success') for n in reuse_main_ci.REQUIRED_JOBS]
            with self.subTest(missing=label), self.assertRaises(ValueError):
                reuse_main_ci.require_jobs([j for j in good if j['name'] != label])

    def test_source_receipts_reject_mixup_or_absence(self):
        with tempfile.TemporaryDirectory() as tmp:
            d=Path(tmp)
            for name in source.GATES:
                data=name.encode(); (d/name).write_bytes(data)
                (d/(name+'.json')).write_text(json.dumps(dict(source_commit='a',source_tree='t',
                    workflow_run='4',workflow_attempt='1',schema_version=1,status='passed',exit_code=0,
                    command=source.COMMANDS[name],log_sha256=hashlib.sha256(data).hexdigest())))
            grid=d/'pre-grid-archive-browser.json'
            grid.write_text(json.dumps(dict(passed=True,real_indexeddb=True,synthetic_cloud=True,
                                            player_saves_used=False,total_checks=1,checks=['synthetic'])))
            source.verify(d,'a','t','4','1')
            for ids in [('b','t','4','1'),('a','u','4','1'),('a','t','5','1'),('a','t','4','2')]:
                with self.subTest(ids=ids),self.assertRaises(ValueError):source.verify(d,*ids)
            (d/source.GATES[0]).write_bytes(b'changed')
            with self.assertRaises(ValueError):source.verify(d,'a','t','4','1')
            (d/source.GATES[0]).write_bytes(source.GATES[0].encode())
            grid.unlink()
            with self.assertRaises(FileNotFoundError):source.verify(d,'a','t','4','1')
