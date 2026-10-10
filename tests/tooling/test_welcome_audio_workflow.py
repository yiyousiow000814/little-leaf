"""Offline checks for the bounded welcome-audio CI workflow; never launch tools."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/welcome-audio.yml"


class WelcomeAudioWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text()

    def test_diagnostics_have_only_manual_triggers(self):
        for filename in ("welcome-audio.yml", "final-startup-compare.yml"):
            text = (WORKFLOW.parent / filename).read_text(encoding="utf-8")
            triggers = text.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
            self.assertEqual(re.findall(r"^  ([a-z_]+):", triggers, re.M), ["workflow_dispatch"])
            self.assertNotRegex(text, r"if:.*(?:github.head_ref|github.ref ==)")
        self.assertIn("permissions:\n  contents: read\n", self.text)
        self.assertNotIn("secrets.", self.text)

    def test_pinned_actions_and_exact_source_checkout(self):
        for action in re.findall(r"uses: (\S+)", self.text):
            self.assertRegex(action, r"^actions/(checkout|upload-artifact|download-artifact)@[0-9a-f]{40}$")
        self.assertIn("ref: ${{ github.sha }}", self.text)
        self.assertIn("persist-credentials: false", self.text)
        self.assertIn('test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD"', self.text)
        self.assertIn('test -z "$(git status --porcelain --untracked-files=no)"', self.text)

    def test_successful_artifact_preflight_precedes_browser_without_rebuild(self):
        preflight = self.text.index("python3 tools/reuse_welcome_web.py")
        browser = self.text.index("node tests/welcome_audio_browser.js --source-root")
        selected_download = self.text.index("actions/download-artifact@")
        verified_download = self.text.index("python3 tools/reuse_welcome_web.py --phase verify")
        self.assertLess(preflight, selected_download)
        self.assertLess(selected_download, verified_download)
        self.assertLess(verified_download, browser)
        self.assertIn("artifact-ids: ${{ steps.selected_web.outputs.artifact_id }}", self.text)
        self.assertIn("run-id: ${{ steps.selected_web.outputs.run_id }}", self.text)
        self.assertIn("digest-mismatch: error", self.text)
        for forbidden in ("tests/run_integration_candidate.py", "tools/build_web.py", "tools/install_tools.py", "continue-on-error"):
            self.assertNotIn(forbidden, self.text)
        self.assertIn("actions: read", self.text)
        for input_name in ("web_run_id", "web_artifact_id"):
            self.assertIn("inputs." + input_name, self.text)

    def test_pinned_bundled_browser_without_audio_or_sandbox_overrides(self):
        self.assertIn("--no-fund playwright@1.63.0", self.text)
        self.assertIn('playwright" install --with-deps chromium', self.text)
        self.assertIn("xvfb xauth tesseract-ocr tesseract-ocr-eng", self.text)
        for forbidden in ("CHROMIUM_CHANNEL", "executablePath", "--no-sandbox", "autoplay-policy", "media-engagement", "--mute-audio", "sysctl", "apparmor", "build_firebase", "build_crazygames", "deploy", "publish"):
            executable_lines = "\n".join(line for line in self.text.splitlines() if not line.startswith("#"))
            self.assertNotIn(forbidden, executable_lines)

    def test_offline_harness_and_guards_are_mandatory(self):
        self.assertIn("node tests/welcome_audio_test.js", self.text)
        self.assertIn("python3 tools/verify_prebaked_atlases.py", self.text)
        self.assertIn("python3 -m unittest tests.tooling.test_welcome_audio_workflow tests.tooling.test_reuse_welcome_web -v", self.text)
        for file in ("browser", "helpers", "observer"):
            self.assertIn("node --check tests/welcome_audio_" + file + ".js", self.text)

    def test_failure_evidence_retained_without_disposable_profiles(self):
        upload = self.text.split("      - name: Retain", 1)[1]
        self.assertIn("if: always()", upload)
        self.assertIn("release-manifest.json", upload)
        self.assertIn("artifact-reuse.json", upload)
        self.assertIn("/welcome-audio-web/evidence/", upload)
        self.assertIn("if-no-files-found: error", upload)
        self.assertIn("retention-days: 7", upload)
        for forbidden in ("/project/", "/disposable-profile/", "node_modules", "user-data", "/web/\n"):
            self.assertNotIn(forbidden, upload)


if __name__ == "__main__":
    unittest.main()
