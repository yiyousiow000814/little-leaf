from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class StartupWorkflowTests(unittest.TestCase):
    def test_installer_environment_applies_before_control_execution(self):
        text = (ROOT / '.github/workflows/ci.yml').read_text()
        install = text.index('- name: Install checksum-pinned control engine and template')
        run = text.index('- name: Freshly test and export the immutable pre-baked control')
        self.assertLess(install, run)
        self.assertIn('ci/install_tools.py godot', text[install:run])
        self.assertNotIn('run_integration_candidate.py', text[install:run])
        execution = text[run:text.index('- name: Retain same-run baseline export')]
        self.assertNotIn('ci/install_tools.py', execution)
        self.assertIn('--test-report "$RUNNER_TEMP/control-engine/summary.json"', execution)
    def test_both_artifacts_are_same_run_and_extra_jobs_are_scoped(self):
        text = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertEqual(text.count("github.head_ref == 'perf/background-cache-startup-10a'"), 2)
        self.assertIn('needs: [web, startup-control]', text)
        self.assertIn('artifact-ids: ${{ needs.web.outputs.artifact_id }}', text)
        self.assertIn('artifact-ids: ${{ needs.startup-control.outputs.artifact_id }}', text)
        self.assertNotIn('run-id:', text)
        self.assertIn('baseline-1 candidate-1 candidate-2 baseline-2', text)
        self.assertIn('--source-root "$source"', text)
