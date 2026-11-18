"""Contract for checked Chromium provisioning on ordinary PR browser jobs."""
import json
import re
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]


class BrowserProvisionExtensionTests(unittest.TestCase):
    def setUp(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-web.yml").read_text())
        self.jobs = workflow["jobs"]
        self.route = self.jobs["play"]["env"]["PLAY_LOCKED_PROVISION"]

    @staticmethod
    def step(job, prefix):
        return next(step for step in job["steps"] if step.get("name", "").startswith(prefix))

    def test_ordinary_pr_selection_matches_validated_play_without_a_fallback(self):
        for role in ("browser", "compatibility"):
            with self.subTest(role=role):
                job = self.jobs[role]
                self.assertEqual(job["env"]["PR_LOCKED_CHROMIUM_PROVISION"], self.route)
                self.assertEqual(self.step(job, "Install shared pinned")["if"],
                                 "env.PR_LOCKED_CHROMIUM_PROVISION != 'true'")
                for prefix in ("Install pinned Playwright driver", "Install only missing pinned",
                               "Verify headed Chrome sandbox"):
                    self.assertEqual(self.step(job, prefix)["if"],
                                     "env.PR_LOCKED_CHROMIUM_PROVISION == 'true'")
                self.assertIn("playwright@1.63.0", self.step(job, "Install pinned Playwright driver")["run"])
                self.assertIn('play_provision.py candidate "$RUNNER_TEMP/$CHROMIUM_PROVISION_RELATIVE/package-transaction.json"',
                              self.step(job, "Install only missing pinned")["run"])
                self.assertNotIn("continue-on-error", json.dumps(job))

    def test_runner_context_is_unavailable_at_job_env_scope(self):
        # GitHub resolves jobs.<id>.env before assigning a runner. Steps can use RUNNER_TEMP.
        runner_context = re.compile(r"\$\{\{(?:(?!\}\}).)*?\brunner\s*(?:\.|\[)", re.I | re.S)
        for name, job in self.jobs.items():
            for key, value in job.get("env", {}).items():
                with self.subTest(job=name, key=key):
                    self.assertNotRegex(str(value), runner_context)
        for role in ("browser", "compatibility"):
            uses = [line for step in self.jobs[role]["steps"] for line in step.get("run", "").splitlines()
                    if "$CHROMIUM_PROVISION_RELATIVE" in line]
            self.assertEqual(len(uses), 5, role)
            for line in uses:
                self.assertIn('"$RUNNER_TEMP/$CHROMIUM_PROVISION_RELATIVE', line)

    def test_independent_webkit_phase_and_probe_before_real_checks(self):
        recovery = self.jobs["browser"]
        webkit = self.step(recovery, "Install WebKit only")
        self.assertIn("install --with-deps webkit", webkit["run"])
        self.assertNotIn("if", webkit)
        shell = (ROOT / "tools/ci/verify_locked_chromium.sh").read_text()
        for required in ("chrome-ldd.txt", "ocr-ldd.txt", "grep -Fx eng", "fc-match sans-serif",
                         "xvfb-run -a node tools/ci/play_canary.cjs"):
            self.assertIn(required, shell)
        for role, first_test in (("browser", "Verify cloud recovery"), ("compatibility", "Verify compensation")):
            job = self.jobs[role]
            steps = job["steps"]
            probe = steps.index(self.step(job, "Verify headed Chrome sandbox"))
            self.assertLess(steps.index(self.step(job, "Activate and verify")), probe)
            if role == "browser":
                self.assertLess(steps.index(webkit), probe)
            self.assertLess(probe, steps.index(self.step(job, first_test)))
            self.assertIn("chromium-provision/", self.step(job, "Collect lane evidence")["run"])
        self.assertEqual(self.jobs["browser"]["env"]["CHROMIUM_PROVISION_RELATIVE"], "chromium-provision/recovery")
        self.assertEqual(self.jobs["compatibility"]["env"]["CHROMIUM_PROVISION_RELATIVE"], "chromium-provision/compatibility-${{ matrix.case }}")


if __name__ == "__main__":
    unittest.main()
