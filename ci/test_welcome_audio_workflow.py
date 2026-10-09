"""Offline checks for the bounded welcome-audio CI workflow; never launch tools."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/welcome-audio.yml"


class WelcomeAudioWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text()

    def test_branch_scoped_without_pull_request_or_release_trigger(self):
        triggers = self.text.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertEqual(triggers, "  push:\n    branches: [fix/10a-ready-welcome]\n  workflow_dispatch:")
        self.assertIn("if: github.ref == 'refs/heads/fix/10a-ready-welcome'", self.text)
        self.assertIn("permissions:\n  contents: read\n", self.text)
        self.assertNotIn("secrets.", self.text)

    def test_pinned_actions_and_exact_source_checkout(self):
        for action in re.findall(r"uses: (\S+)", self.text):
            self.assertRegex(action, r"^actions/(checkout|upload-artifact)@[0-9a-f]{40}$")
        self.assertIn("ref: ${{ github.sha }}", self.text)
        self.assertIn("persist-credentials: false", self.text)
        self.assertIn('test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD"', self.text)
        self.assertIn('test -z "$(git status --porcelain --untracked-files=no)"', self.text)

    def test_complete_engine_gate_precedes_exact_export_and_browser(self):
        engine = 'python3 tests/run_integration_candidate.py --output "$RUNNER_TEMP/welcome-audio-engine"'
        export = 'python3 ci/build_web.py --output "$RUNNER_TEMP/welcome-audio-web" --test-report "$RUNNER_TEMP/welcome-audio-engine/summary.json"'
        browser = 'node tests/welcome_audio_browser.js --source-root "$GITHUB_WORKSPACE" --web-build "$RUNNER_TEMP/welcome-audio-web/web"'
        self.assertLess(self.text.index(engine), self.text.index(export))
        self.assertLess(self.text.index(export), self.text.index(browser))
        self.assertNotIn("--only", self.text)
        self.assertNotIn("--local-tools", self.text)
        self.assertNotIn("continue-on-error", self.text)

    def test_pinned_bundled_browser_without_audio_or_sandbox_overrides(self):
        self.assertIn("--no-fund playwright@1.63.0", self.text)
        self.assertIn('playwright" install --with-deps chromium', self.text)
        self.assertIn("xvfb xauth tesseract-ocr tesseract-ocr-eng", self.text)
        for forbidden in ("CHROMIUM_CHANNEL", "executablePath", "--no-sandbox", "autoplay-policy", "media-engagement", "--mute-audio", "sysctl", "apparmor", "build_firebase", "build_crazygames", "deploy", "publish"):
            executable_lines = "\n".join(line for line in self.text.splitlines() if not line.startswith("#"))
            self.assertNotIn(forbidden, executable_lines)

    def test_offline_harness_and_guards_are_mandatory(self):
        self.assertIn("node tests/welcome_audio_test.js", self.text)
        self.assertIn("python3 ci/verify_prebaked_atlases.py", self.text)
        self.assertIn("python3 -m unittest discover -s ci -p 'test_*.py' -v", self.text)
        for file in ("browser", "helpers", "observer"):
            self.assertIn("node --check tests/welcome_audio_" + file + ".js", self.text)

    def test_failure_evidence_retained_without_disposable_profiles(self):
        upload = self.text.split("      - name: Retain", 1)[1]
        self.assertIn("if: always()", upload)
        self.assertIn("release-manifest.json", upload)
        self.assertIn("/welcome-audio-web/evidence/", upload)
        self.assertIn("if-no-files-found: error", upload)
        self.assertIn("retention-days: 7", upload)
        for forbidden in ("/project/", "/disposable-profile/", "node_modules", "user-data", "/web/\n"):
            self.assertNotIn(forbidden, upload)


if __name__ == "__main__":
    unittest.main()
