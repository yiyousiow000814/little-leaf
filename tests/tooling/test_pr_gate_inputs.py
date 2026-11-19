"""Compact handoff must preserve original diagnostics and reject mismatched evidence."""
import json
from pathlib import Path
import tempfile
import unittest

import yaml

from tools.ci.pr_gate_inputs import REQUIRED, transfer


ROOT = Path(__file__).resolve().parents[2]
BINDING = {
    'GITHUB_EVENT_NAME': 'pull_request',
    'GITHUB_SHA': 'a' * 40,
    'GITHUB_RUN_ID': '11',
    'GITHUB_RUN_ATTEMPT': '2',
    'FULL_ARTIFACT_ID': '97',
    'FULL_ARTIFACT_DIGEST': 'b' * 64,
}
ALLOWED = {
    'current': {'engine-evidence/*.json', 'engine-evidence/*.log', 'web-build/evidence/',
                'web-build/web/release-manifest.json', 'crazygames-stage.json'},
    'historical': {'old-engine-evidence/*.json', 'old-engine-evidence/*.log',
                   'old-web-build/evidence/', 'old-web-build/web/release-manifest.json'},
}


class PrGateInputsTests(unittest.TestCase):
    def test_original_binding_and_required_content(self):
        for lane, required in REQUIRED.items():
            with tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                for name in required:
                    file = root / name
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_text(name)
                transfer(root, lane, 'record', BINDING)
                transfer(root, lane, 'verify', BINDING)
                for key, mismatch in {
                    'GITHUB_EVENT_NAME': 'push',
                    'GITHUB_SHA': 'c' * 40,
                    'GITHUB_RUN_ID': '12',
                    'GITHUB_RUN_ATTEMPT': '1',
                    'FULL_ARTIFACT_ID': '98',
                    'FULL_ARTIFACT_DIGEST': 'c' * 64,
                }.items():
                    with self.subTest(lane=lane, key=key):
                        with self.assertRaises(ValueError):
                            transfer(root, lane, 'verify', BINDING | {key: mismatch})
                        with self.assertRaises(ValueError):
                            transfer(root, lane, 'verify', BINDING | {key: ''})
                for name in required:
                    with self.subTest(lane=lane, file=name):
                        file = root / name
                        file.write_text('tampered')
                        with self.assertRaises(ValueError):
                            transfer(root, lane, 'verify', BINDING)
                        file.unlink()
                        with self.assertRaises(ValueError):
                            transfer(root, lane, 'verify', BINDING)
                        with tempfile.NamedTemporaryFile(dir=root) as other:
                            file.symlink_to(other.name)
                            with self.assertRaises(ValueError):
                                transfer(root, lane, 'verify', BINDING)
                        file.unlink()
                        file.write_text(name)
                target = root / f'pr-gate-{lane}.json'
                data = json.loads(target.read_text())
                data['lane'] = 'wrong-lane'
                target.write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    transfer(root, lane, 'verify', BINDING)
                target.unlink()
                with self.assertRaises(ValueError):
                    transfer(root, lane, 'verify', BINDING)

    def test_explicit_pr_route_producer_ids_and_diagnostic_inventory(self):
        jobs = yaml.safe_load((ROOT / '.github/workflows/build-web.yml').read_text())['jobs']
        gate = jobs['gate']['steps']
        archive = next(step for step in gate if step.get('id') == 'gate_evidence')['with']['path']
        for lane, producer in [('current', 'build'), ('historical', 'historical')]:
            job = jobs[producer]
            steps = job['steps']
            upload = next(step for step in steps if step.get('id') == 'compact')
            self.assertEqual(upload['if'], "needs.guard.outputs.ordinary_pr == 'true'")
            paths = {p.removeprefix('${{ runner.temp }}/') for p in upload['with']['path'].splitlines()}
            self.assertEqual(paths, ALLOWED[lane] | {f'pr-gate-{lane}.json'})
            diagnostics = {p.removeprefix('${{ runner.temp }}/') for p in archive.splitlines()}
            prefix = 'old-' if lane == 'historical' else ''
            self.assertEqual(
                {p for p in diagnostics if p.startswith((prefix + 'engine-evidence/', prefix + 'web-build/'))},
                {p for p in paths if p.endswith(('*.json', '*.log', '/evidence/'))},
            )
            self.assertEqual(job['outputs']['compact_id'], '${{ steps.compact.outputs.artifact-id }}')
            original = next(step for step in steps if step.get('id') == 'inputs')
            self.assertEqual(original['if'], 'always()')
            self.assertIn(prefix + 'web-build/web/\n', original['with']['path'])
            receipt = steps[steps.index(upload) - 1]
            self.assertEqual(receipt['if'], upload['if'])
            self.assertEqual(receipt['env'], {
                'FULL_ARTIFACT_ID': '${{ steps.inputs.outputs.artifact-id }}',
                'FULL_ARTIFACT_DIGEST': '${{ steps.inputs.outputs.artifact-digest }}',
            })
            download = next(step for step in gate if step.get('name') == f'Collect exact {lane} compact gate inputs')
            self.assertEqual(download['with']['artifact-ids'], '${{ needs.' + producer + '.outputs.compact_id }}')
            self.assertEqual(download['with']['digest-mismatch'], 'error')
            self.assertIn("needs.guard.outputs.ordinary_pr == 'true'", download['if'])
            verify = gate[gate.index(download) + 1]
            self.assertEqual(verify['env'], {
                'FULL_ARTIFACT_ID': '${{ needs.' + producer + '.outputs.inputs_id }}',
                'FULL_ARTIFACT_DIGEST': '${{ needs.' + producer + '.outputs.inputs_digest }}',
            })
            fallback = gate[gate.index(verify) + 1]
            self.assertEqual(fallback['if'],
                             f"always() && needs.{producer}.result == 'success' && needs.guard.outputs.ordinary_pr != 'true'")
            self.assertLess(gate.index(verify), next(i for i, step in enumerate(gate) if step.get('id') == 'sibling_verify'))

    def test_producers_have_no_other_consumers_of_compact_inputs(self):
        jobs = yaml.safe_load((ROOT / '.github/workflows/build-web.yml').read_text())['jobs']
        for name in ('play', 'compatibility', 'browser', 'firebase', 'crazygames'):
            steps = jobs[name]['steps']
            self.assertNotIn('compact_id', str(steps), name)
            self.assertNotIn('pr_gate_inputs', str(steps), name)


if __name__ == '__main__':
    unittest.main()
