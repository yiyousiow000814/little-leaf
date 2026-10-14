"""Run the shared immutable tag shell gate offline; pin both publication consumers."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/ci.yml'
BASH = shutil.which('bash')
if os.name == 'nt':
    # The Windows system bash may be a WSL relay without a Linux runtime.
    # Use the existing Git Bash for this Unix-shell fixture; never install one.
    git_binary=shutil.which('git')
    candidate=Path(git_binary).resolve().parents[1]/'bin/bash.exe' if git_binary else None
    BASH=str(candidate) if candidate and candidate.is_file() else None


@unittest.skipUnless(BASH, 'A working Bash is required for runner shell tests')
class ItchTagGateTests(unittest.TestCase):
    def gate(self, tag, ref_type='tag'):
        workflow = WORKFLOW.read_text()
        source = workflow.split('  common_tag:', 1)[1].split('        run: |\n', 1)[1].split('      - name:', 1)[0]
        source = '\n'.join(line[10:] for line in source.splitlines())
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            git = root / 'git'
            git.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$FETCH_LOG"\n',newline='\n')
            git.chmod(0o755)
            log = root / 'fetch.log'
            fixture_bin=root.as_posix()
            if os.name=='nt':fixture_bin='/'+root.drive[0].lower()+fixture_bin[2:]
            env = dict(os.environ, PATH=folder + os.pathsep + os.environ['PATH'],
                       RELEASE_TAG=tag, REF_TYPE=ref_type, FETCH_LOG='fetch.log',FIXTURE_BIN=fixture_bin,GITHUB_RUN_ATTEMPT='1')
            # Git Bash initializes PATH itself. Prepend the fixture afterwards,
            # and use a relative log in the disposable cwd on both platforms.
            script='PATH="$FIXTURE_BIN:$PATH"\nexport PATH\n'+source
            result = subprocess.run([BASH, '-e', '-o', 'pipefail', '-c', script],
                                    cwd=folder,env=env, capture_output=True, text=True)
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

    def test_release_reuses_full_qualification_and_exact_source(self):
        source = WORKFLOW.read_text()
        for guard in ["tags: ['v*']", 'github.event.created && !github.event.deleted',
                      '--require-main-ancestor', 'python3 tools/qualification/reuse_main_ci.py',
                      'python3 tools/release/common_tag.py create',
                      'little-leaf-common-release-${{ github.sha }}-1']:
            self.assertIn(guard, source)
        publishing=(ROOT/'.github/workflows/release-itch.yml').read_text()
        qualification=(ROOT/'.github/workflows/release-firebase.yml').read_text()
        for guard in ['workflows: [Check and build Web]',
                      "github.event.workflow_run.conclusion == 'success'",
                      'uses: ./.github/workflows/stage-firebase.yml',
                      "common_tag_run_id: ${{ format('{0}', github.event.workflow_run.id) }}"]:
            self.assertIn(guard,qualification)
        for guard in ['workflows: [Qualify Firebase release]',
                      "github.event.workflow_run.conclusion == 'success'",
                      "github.event.workflow_run.event == 'workflow_run'",
                      "startsWith(github.event.workflow_run.display_title, 'Firebase common tag v')",
                      "FIREBASE_RUN: ${{ github.event_name == 'workflow_dispatch' && inputs.qualified_run_id || github.event.workflow_run.id }}",
                      'coordinator/tools/release/common_firebase.py --run "$FIREBASE_RUN" --platform itch',
                      'ref: ${{ steps.common.outputs.source_sha }}',
                      'RELEASE_TAG: ${{ steps.common.outputs.release_tag }}',
                      'RELEASE_SHA: ${{ steps.common.outputs.source_sha }}',
                      '--tag "$RELEASE_TAG" --sha "$RELEASE_SHA"',
                      '--firebase-variant "$RUNNER_TEMP/common-firebase/variant"',
                      '--staging-origin "$RUNNER_TEMP/common-firebase/origin.json"',
                      'Missing BUTLER_API_KEY','tools/release/publish_itch.py']:
            self.assertIn(guard,publishing)
        self.assertNotIn('common_tag.py consume',publishing)
        self.assertNotIn('reuse_main_ci.py',publishing)
        build = (ROOT / '.github/workflows/build-web.yml').read_text()
        for gate in ['tools/ci/preflight.py', 'run_integration_candidate.py',
                     'tools/build/build_web.py', 'connection_recovery_browser.js',
                     'wall_compatibility_browser.js', 'save_log_browser.js']:
            self.assertIn(gate, build)


if __name__ == '__main__':
    unittest.main()
