"""Run the real itch tag shell gate offline; pin the full-build safety contract."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/release-itch.yml'


@unittest.skipUnless(shutil.which('bash'), 'Bash is required for runner shell tests')
class ItchTagGateTests(unittest.TestCase):
    def gate(self, tag, ref_type='tag'):
        workflow = WORKFLOW.read_text()
        source = workflow.split('        run: |\n', 1)[1].split('      - name:', 1)[0]
        source = '\n'.join(line[10:] for line in source.splitlines())
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            git = root / 'git'
            git.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$FETCH_LOG"\n')
            git.chmod(0o755)
            log = root / 'fetch.log'
            env = dict(os.environ, PATH=folder + os.pathsep + os.environ['PATH'],
                       RELEASE_TAG=tag, REF_TYPE=ref_type, FETCH_LOG=str(log))
            result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', source],
                                    env=env, capture_output=True, text=True)
            return result.returncode, log.read_text() if log.exists() else ''

    def test_numeric_and_every_single_lowercase_hotfix(self):
        for suffix in [''] + list('abcdefghijklmnopqrstuvwxyz'):
            with self.subTest(suffix=suffix):
                code, fetch = self.gate('v0.1.10' + suffix)
                self.assertEqual(code, 0)
                self.assertEqual(fetch, 'fetch --no-tags origin main\n')

    def test_malformed_and_nontag_never_fetch(self):
        for tag in ['v0.1.10A', 'v0.1.10aa', 'v0.1.10a1', 'v0.1.10-a',
                    'v0.1.10a-dev.1', 'v0.1.10a+build.1', 'v01.1.10a',
                    '0.1.10a', 'v0.1.10a\n', 'v0.1.10a; echo injected']:
            with self.subTest(tag=tag):
                code, fetch = self.gate(tag)
                self.assertNotEqual(code, 0)
                self.assertEqual(fetch, '')
        self.assertNotEqual(self.gate('v0.1.10a', ref_type='branch')[0], 0)

    def test_release_still_requires_full_build_and_exact_source(self):
        source = WORKFLOW.read_text()
        for guard in ["tags: ['v*']", 'github.event.created && !github.event.deleted',
                      '--require-main-ancestor', 'needs: [gate, build]',
                      'uses: ./.github/workflows/build-web.yml',
                      'ref: ${{ needs.gate.outputs.sha }}',
                      'artifact-ids: ${{ needs.build.outputs.artifact_id }}',
                      'digest-mismatch: error', 'Missing BUTLER_API_KEY',
                      'python3 ci/publish_itch.py']:
            self.assertIn(guard, source)
        build = (ROOT / '.github/workflows/build-web.yml').read_text()
        for gate in ['unittest discover', 'run_integration_candidate.py',
                     'ci/build_web.py', 'connection_recovery_browser.js',
                     'wall_compatibility_browser.js', 'save_log_browser.js']:
            self.assertIn(gate, build)


if __name__ == '__main__':
    unittest.main()
