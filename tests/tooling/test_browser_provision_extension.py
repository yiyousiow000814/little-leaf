"""Contract for checked Chromium provisioning on ordinary PR browser jobs."""
import importlib.util
import json
import re
from pathlib import Path
import tempfile
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
            self.assertEqual(len(uses), 7 if role == "browser" else 5, role)
            for line in uses:
                self.assertIn('"$RUNNER_TEMP/$CHROMIUM_PROVISION_RELATIVE', line)

    def test_independent_webkit_phase_and_probe_before_real_checks(self):
        recovery = self.jobs["browser"]
        webkit = self.step(recovery, "Install WebKit only")
        self.assertIn("install --with-deps webkit", webkit["run"])
        self.assertEqual(webkit["if"], "env.PR_LOCKED_CHROMIUM_PROVISION != 'true'")
        deps = self.step(recovery, "Install signed Ubuntu WebKit")
        binary = self.step(recovery, "Install pinned WebKit browser")
        for step in (deps, binary):
            self.assertEqual(step["if"], "env.PR_LOCKED_CHROMIUM_PROVISION == 'true'")
            self.assertNotIn("continue-on-error", step)
            self.assertNotIn("install --with-deps", step["run"])
        self.assertIn("recovery_webkit_provision.py", deps["run"])
        self.assertEqual(deps["timeout-minutes"], 5)
        self.assertIn("install webkit", binary["run"])
        self.assertIn("webkit-2359/pw_run.sh", binary["run"])
        self.assertIn("ffmpeg-1011", binary["run"])
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
                self.assertLess(steps.index(deps), steps.index(binary))
                self.assertLess(steps.index(binary), probe)
            self.assertLess(probe, steps.index(self.step(job, first_test)))
            self.assertIn("chromium-provision/", self.step(job, "Collect lane evidence")["run"])
        self.assertEqual(self.jobs["browser"]["env"]["CHROMIUM_PROVISION_RELATIVE"], "chromium-provision/recovery")
        self.assertEqual(self.jobs["compatibility"]["env"]["CHROMIUM_PROVISION_RELATIVE"], "chromium-provision/compatibility-${{ matrix.case }}")

    def test_webkit_apt_is_private_signed_bounded_and_fail_closed(self):
        path = ROOT / "tools/ci/recovery_webkit_provision.py"
        spec = importlib.util.spec_from_file_location("recovery_webkit_provision", path)
        provision = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(provision)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            private_config = provision.isolated_config(root)
            sources = (root / "ubuntu.sources").read_text()
            for text in ("https://archive.ubuntu.com/ubuntu", "https://security.ubuntu.com/ubuntu",
                         "noble noble-updates noble-backports", "noble-security",
                         "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"):
                self.assertIn(text, sources)
            self.assertNotIn("ec2.archive", sources)
            self.assertEqual(sources.count("Signed-By:"), 2)
            config = private_config.read_text()
            for text in ('Acquire::Check-Valid-Until "true"', 'Acquire::Retries "0"',
                         'Acquire::https::Verify-Peer "true"', 'Acquire::https::Verify-Host "true"',
                         'APT::Get::AllowUnauthenticated "false"', str(root / "conf.d"), str(root / "lists")):
                self.assertIn(text, config)
            argv = provision.root_apt(private_config, 23, "/usr/bin/apt-get", "update")
            self.assertEqual(argv[:6], ("sudo", "-n", "/usr/bin/timeout", "--kill-after=5s", "23", "/usr/bin/env"))
            self.assertIn("APT_CONFIG=" + str(private_config), argv)
        line = "Inst libsample [1:old] (1:new Noble [amd64])"
        self.assertEqual(provision.operations(line + " []"), {"libsample": {"from": "1:old", "to": "1:new"}})
        for bad in (line + " [broken]", line + "\n" + line, line + "\nRemv other [1]", "Purg other [1]"):
            with self.assertRaises(ValueError):
                provision.operations(bad)

    def test_webkit_refresh_only_retries_timeout_and_preserves_budget(self):
        from subprocess import CalledProcessError, TimeoutExpired
        from unittest.mock import Mock, call, patch
        from tools.ci import recovery_webkit_provision as provision

        cmd = ("apt-get", "update")
        expired = CalledProcessError(124, cmd)
        with patch.object(provision.time, "monotonic", return_value=200):
            phase = Mock()
            provision.refresh_webkit_indexes(phase)
            phase.assert_called_once_with("webkit-apt-refresh", 50, "update")

        # Simulate the first attempt also consuming its five-second kill grace.
        with patch.object(provision.time, "monotonic", side_effect=[200, 255]):
            phase = Mock(side_effect=[expired, None])
            provision.refresh_webkit_indexes(phase)
        self.assertEqual(phase.call_args_list, [call("webkit-apt-refresh", 50, "update"),
                                               call("webkit-apt-refresh-retry", 12, "update")])
        self.assertEqual(55 + 12 + provision.APT_CAPTURE_GRACE_SECONDS,
                         provision.REFRESH_BUDGET_SECONDS)

        for failure in (CalledProcessError(100, cmd, stderr="GPG signature invalid"),
                        CalledProcessError(100, cmd, stderr="Hash Sum mismatch"),
                        CalledProcessError(137, cmd), TimeoutExpired(cmd, 58)):
            with self.subTest(failure=failure), patch.object(provision.time, "monotonic", return_value=200):
                phase = Mock(side_effect=failure)
                with self.assertRaises(type(failure)) as caught:
                    provision.refresh_webkit_indexes(phase)
                self.assertIs(caught.exception, failure)
                phase.assert_called_once()

        for now, count in ((255, 2), (267, 1)):
            with self.subTest(now=now), patch.object(provision.time, "monotonic", side_effect=[200, now]):
                phase = Mock(side_effect=expired)
                with self.assertRaises(CalledProcessError):
                    provision.refresh_webkit_indexes(phase)
                self.assertEqual(phase.call_count, count)

    def test_webkit_download_retries_only_timeout_with_same_command_in_budget(self):
        from subprocess import CalledProcessError, TimeoutExpired
        from unittest.mock import Mock, patch
        from tools.ci import recovery_webkit_provision as provision

        install = ("install", "--no-remove", "--no-install-recommends")
        packages = ["libexample"]
        command = (*install, "--download-only", "-y", *packages)
        expired = CalledProcessError(124, command)

        first_success = Mock()
        with patch.object(provision.time, "monotonic", return_value=200):
            provision.fetch_webkit_packages(first_success, install, packages)
        first_success.assert_called_once_with("webkit-apt-fetch", 65, *command)

        phase = Mock(side_effect=[expired, None])
        with patch.object(provision.time, "monotonic", side_effect=[200, 265]):
            provision.fetch_webkit_packages(phase, install, packages)
        self.assertEqual(len(phase.call_args_list), 2)
        self.assertEqual(phase.call_args_list[0].args, ("webkit-apt-fetch", 65, *command))
        self.assertEqual(phase.call_args_list[1].args, ("webkit-apt-fetch-retry", 27, *command))
        self.assertEqual(65 + 27 + provision.APT_CAPTURE_GRACE_SECONDS, provision.FETCH_BUDGET_SECONDS)

        for failure in (CalledProcessError(100, command), CalledProcessError(137, command),
                        TimeoutExpired(command, 73)):
            with self.subTest(failure=failure), patch.object(provision.time, "monotonic", return_value=200):
                phase = Mock(side_effect=failure)
                with self.assertRaises(type(failure)):
                    provision.fetch_webkit_packages(phase, install, packages)
                phase.assert_called_once()

        phase = Mock(side_effect=expired)
        with patch.object(provision.time, "monotonic", side_effect=[200, 298]):
            with self.assertRaises(CalledProcessError):
                provision.fetch_webkit_packages(phase, install, packages)
        phase.assert_called_once()

        phase = Mock(side_effect=expired)
        with patch.object(provision.time, "monotonic", side_effect=[200, 265]):
            with self.assertRaises(CalledProcessError):
                provision.fetch_webkit_packages(phase, install, packages)
        self.assertEqual(phase.call_count, 2)


if __name__ == "__main__":
    unittest.main()
