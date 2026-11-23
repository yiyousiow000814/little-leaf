"""Contracts for the independent, checked production Play PR lane."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import yaml

from tools.ci import play_provision

ROOT = Path(__file__).resolve().parents[2]


class PlayProvisionTests(unittest.TestCase):
    def setUp(self):
        self.lock = json.loads(play_provision.LOCK.read_text())
        self.present = {p: "image" for p in play_provision.PREINSTALLED}

    def test_runner_must_have_known_nonlocked_dependencies(self):
        self.present["libnss3"] = None
        with self.assertRaisesRegex(ValueError, "libnss3"):
            play_provision.plan(self.present, self.lock)

    def test_runner_os_or_architecture_is_not_guessed(self):
        for codename, arch in (("bookworm", "x86_64"), ("noble", "aarch64")):
            with patch.object(play_provision.platform, "freedesktop_os_release",
                              return_value={"VERSION_CODENAME": codename}), patch.object(
                                  play_provision.platform, "machine", return_value=arch), patch.object(
                                      play_provision, "installed") as installed:
                with self.assertRaisesRegex(ValueError, "Expected Ubuntu Noble amd64"):
                    play_provision.main("candidate", "unused.json")
                installed.assert_not_called()

    def test_only_required_missing_packages_and_transitives(self):
        self.present.update({p: "preserve" for p in self.lock})
        self.present.update({"xfonts-scalable": None, "xfonts-utils": None,
                             "xfonts-encodings": None, "libjpeg8": None})
        self.assertEqual(play_provision.plan(self.present, self.lock),
                         ["xfonts-encodings", "xfonts-scalable", "xfonts-utils"])

    def test_bad_hash_is_rejected_before_package_inspection(self):
        def curl(*args, **_):
            self.assertEqual(args[0], "curl")
            self.assertTrue(args[-1].startswith(play_provision.ORIGIN))
            Path(args[-2]).write_bytes(b"bad package")

        with TemporaryDirectory() as d, patch.object(play_provision, "run", side_effect=curl) as run:
            with self.assertRaisesRegex(ValueError, "checksum"):
                play_provision.fetch_package("tesseract-ocr", self.lock["tesseract-ocr"], Path(d))
            self.assertEqual(run.call_count, 1)

    def test_transient_errors_retry_same_url_and_only_timeout_can_resume(self):
        name = "tesseract-ocr"
        package = b"pinned complete package bytes"
        spec = dict(self.lock[name], sha256=hashlib.sha256(package).hexdigest())
        for code in (28, 52):
            with self.subTest(code=code), TemporaryDirectory() as d:
                calls = []

                def simulate(*args, **kwargs):
                    if args[0] == "dpkg-deb":
                        return subprocess.CompletedProcess(
                            args, 0, {"Package": name, "Version": spec["version"], "Architecture": "amd64"}[args[-1]])
                    calls.append(args)
                    self.assertEqual(args[-1], play_provision.ORIGIN + spec["file"])
                    self.assertNotIn("--location", args)
                    dest = Path(args[-2])
                    if len(calls) == 1:
                        self.assertNotIn("--continue-at", args)
                        dest.write_bytes(package[:8])
                        raise subprocess.CalledProcessError(code, args)
                    if code == 28:
                        self.assertEqual(args[args.index("--continue-at") + 1], "-")
                        self.assertEqual(dest.read_bytes(), package[:8])
                        with dest.open("ab") as stream:
                            stream.write(package[8:])
                    else:
                        self.assertNotIn("--continue-at", args)
                        self.assertFalse(dest.exists())
                        dest.write_bytes(package)
                    self.assertLessEqual(kwargs["timeout"], 56)

                with patch.object(play_provision, "run", side_effect=simulate):
                    self.assertEqual(play_provision.fetch_package(name, spec, Path(d)).read_bytes(), package)
                self.assertEqual(len(calls), 2)

    def test_empty_timeout_restarts_under_remaining_budget_and_no_third_attempt(self):
        def curl(*args, **kwargs):
            self.assertNotIn("--continue-at", args)
            raise subprocess.CalledProcessError(28, args)

        with TemporaryDirectory() as d, patch.object(play_provision, "run", side_effect=curl) as run, patch.object(
            play_provision.time, "monotonic", side_effect=[100, 144]
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                play_provision.fetch_package("tesseract-ocr", self.lock["tesseract-ocr"], Path(d), deadline=150)
        self.assertEqual(len(run.call_args_list), 2)
        budgets = [float(args[args.index("--max-time") + 1]) for args, _ in run.call_args_list]
        self.assertEqual(budgets, [45.0, 6.0])

    def test_nontransient_error_and_expired_budget_fail_before_retry(self):
        for code in (22, 33, 60):  # HTTP status, invalid range, TLS verification.
            with TemporaryDirectory() as d, patch.object(
                play_provision, "run", side_effect=subprocess.CalledProcessError(code, "curl")
            ) as run:
                with self.assertRaises(subprocess.CalledProcessError):
                    play_provision.fetch_package("tesseract-ocr", self.lock["tesseract-ocr"], Path(d))
                self.assertEqual(run.call_count, 1)
        with TemporaryDirectory() as d, patch.object(play_provision, "run") as run:
            with self.assertRaisesRegex(TimeoutError, "budget exhausted"):
                play_provision.fetch_package("tesseract-ocr", self.lock["tesseract-ocr"], Path(d), deadline=0)
            run.assert_not_called()

    def test_retry_result_still_requires_full_pinned_hash(self):
        attempts = []

        def curl(*args, **_):
            self.assertEqual(args[0], "curl")  # Failure must occur before dpkg-deb.
            attempts.append(args)
            Path(args[-2]).write_bytes(b"bad package")
            if len(attempts) == 1:
                raise subprocess.CalledProcessError(28, args)

        with TemporaryDirectory() as d, patch.object(play_provision, "run", side_effect=curl):
            with self.assertRaisesRegex(ValueError, "checksum"):
                play_provision.fetch_package("tesseract-ocr", self.lock["tesseract-ocr"], Path(d))
        self.assertEqual(len(attempts), 2)

    def test_package_url_and_transaction_fail_closed(self):
        spec = dict(self.lock["tesseract-ocr"], file="//elsewhere.invalid/p.deb")
        with TemporaryDirectory() as d, patch.object(play_provision, "run") as run:
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                play_provision.fetch_package("tesseract-ocr", spec, Path(d))
            run.assert_not_called()
        play_provision.verify_simulation("Inst one (1 local)\n", ["one"])
        for changes in ("Remv one [1]\n", "Inst one (1 local)\nInst other (1 archive)\n"):
            with self.assertRaisesRegex(ValueError, "Unexpected"):
                play_provision.verify_simulation(changes, ["one"])

    def test_restored_package_revalidates_digest_and_metadata_before_install(self):
        name = "tesseract-ocr"
        package = b"verified package"
        spec = dict(self.lock[name], sha256=hashlib.sha256(package).hexdigest())
        with TemporaryDirectory() as tmp:
            bundle, dest = Path(tmp) / "bundle", Path(tmp) / "dest"
            bundle.mkdir()
            dest.mkdir()
            item = bundle / Path(spec["file"]).name
            item.write_bytes(package)

            def inspect(*args, **kwargs):
                self.assertEqual(args[0], "dpkg-deb")
                fields = {"Package": name, "Version": spec["version"], "Architecture": "amd64"}
                return subprocess.CompletedProcess(args, 0, fields[args[-1]])

            with patch.object(play_provision, "run", side_effect=inspect) as run:
                output = play_provision.fetch_package(name, spec, dest, bundle=bundle)
                self.assertEqual(output.read_bytes(), package)
                self.assertEqual(run.call_count, 3)
                item.write_bytes(b"corruption")
                with self.assertRaisesRegex(ValueError, "checksum"):
                    play_provision.fetch_package(name, spec, dest, bundle=bundle)
                self.assertEqual(run.call_count, 3)  # No network fallback on corrupt bytes.
                if os.name == "posix":
                    item.unlink()
                    item.symlink_to(output)
                    with self.assertRaisesRegex(ValueError, "regular bundle file"):
                        play_provision.fetch_package(name, spec, dest, bundle=bundle)
                    self.assertEqual(run.call_count, 3)

    def test_missing_bundle_package_uses_existing_bounded_cold_fetch(self):
        name = "tesseract-ocr"
        package = b"verified cold bytes"
        spec = dict(self.lock[name], sha256=hashlib.sha256(package).hexdigest())
        with TemporaryDirectory() as tmp:
            root = Path(tmp)

            def download(pkg, url, dest, deadline):
                self.assertEqual((pkg, url, deadline), (name, play_provision.ORIGIN + spec["file"], 123.0))
                dest.write_bytes(package)

            fields = {"Package": name, "Version": spec["version"], "Architecture": "all"}
            with patch.object(play_provision, "download_pinned_package", side_effect=download) as fetch, patch.object(
                play_provision, "run", side_effect=lambda *args, **kw: subprocess.CompletedProcess(args, 0, fields[args[-1]])
            ):
                received = play_provision.fetch_package(name, spec, root, 123.0, root / "missing")
            self.assertEqual(received.read_bytes(), package)
            fetch.assert_called_once()

    def test_prefetch_only_publishes_complete_verified_candidates(self):
        with TemporaryDirectory() as tmp:
            bundle = Path(tmp) / "bundle"
            lock = {"verified": {}, "stalled": {}, "empty": {}, "http_error": {}}

            def fetch(name, spec, stage, deadline):
                f = stage / (name + ".deb")
                f.write_bytes(b"complete" if name == "verified" else b"partial")
                if name == "stalled":
                    raise TimeoutError
                if name == "empty":
                    raise subprocess.CalledProcessError(52, ("curl", "same-origin"))
                if name == "http_error":
                    raise subprocess.CalledProcessError(22, ("curl", "same-origin"))
                return f

            with patch.object(play_provision, "fetch_package", side_effect=fetch), patch.object(
                play_provision, "run"
            ) as run:
                play_provision.prefetch(lock, bundle)
                run.assert_not_called()  # No package installer in preflight.
            self.assertEqual([p.name for p in bundle.iterdir()], ["verified.deb"])
            self.assertEqual((bundle / "verified.deb").read_bytes(), b"complete")
            with patch.object(play_provision, "fetch_package", side_effect=ValueError("checksum")):
                with self.assertRaisesRegex(ValueError, "checksum"):
                    play_provision.prefetch({"corrupt": {}}, Path(tmp) / "bad-bundle")

            # Digest or dpkg metadata errors still fail closed, not a missing-file fallback.
            fault = subprocess.CalledProcessError(2, ("dpkg-deb", "bad-header"))
            with patch.object(play_provision, "fetch_package", side_effect=fault):
                with self.assertRaises(subprocess.CalledProcessError):
                    play_provision.prefetch({"unreadable": {}}, Path(tmp) / "bad-metadata")

    def test_prefetch_prioritizes_the_four_observed_transport_blockers(self):
        with TemporaryDirectory() as tmp, patch.object(play_provision, "fetch_package") as fetch, patch.object(
            play_provision.concurrent.futures, "ThreadPoolExecutor"
        ) as executor:
            names = []
            executor.return_value.__enter__.return_value.map.side_effect = lambda callback, order: names.extend(order) or []
            play_provision.prefetch(self.lock, Path(tmp) / "bundle")
            self.assertEqual(names[:4], ["fonts-wqy-zenhei", "fonts-freefont-ttf", "fonts-unifont", "tesseract-ocr-eng"])
            self.assertEqual(set(names), set(self.lock))
            fetch.assert_not_called()

    def test_bundle_receipt_is_exact_attempt_only_and_never_relaxes_validation(self):
        jobs = yaml.safe_load((ROOT / ".github/workflows/build-web.yml").read_text())["jobs"]
        preflight, build = jobs["preflight"], jobs["build"]
        self.assertEqual(preflight["if"], "needs.guard.outputs.scope == 'full' && needs.guard.outputs.ordinary_pr == 'true'")
        packages = jobs["browser_packages"]
        self.assertEqual(packages["needs"], "guard")
        self.assertEqual(packages["if"], "needs.guard.outputs.scope == 'full' && needs.guard.outputs.locked_browser == 'true'")
        self.assertIn("browser_packages", build["needs"])
        self.assertIn("needs.browser_packages.result == 'success'", build["if"])
        plan = next(s for s in jobs["guard"]["steps"] if s.get("id") == "engine_plan")
        ordinary_pr = plan["env"]["ORDINARY_PR"]
        ordinary = ordinary_pr.replace("github.event_name == 'pull_request'",
            "(github.event_name == 'pull_request' || (github.event_name == 'push' && github.ref == 'refs/heads/main'))", 1)
        self.assertEqual(plan["env"]["LOCKED_BROWSER"], ordinary)
        self.assertEqual(build["outputs"]["locked_browser"], "${{ needs.guard.outputs.locked_browser }}")
        bind = next(s for s in packages["steps"] if s.get("id") == "bind")
        self.assertIn('git rev-parse HEAD', bind["run"])
        self.assertIn('"$GITHUB_SHA" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT"', bind["run"])
        require = next(s for s in build["steps"] if s.get("name", "").startswith("Require the current exact"))
        self.assertEqual(require["if"], "needs.guard.outputs.locked_browser == 'true'")
        self.assertEqual(require["env"]["PACKAGE_BINDING"], "${{ needs.browser_packages.outputs.binding }}")
        self.assertEqual(require["run"], 'test "$PACKAGE_BINDING" = "$GITHUB_SHA:$GITHUB_RUN_ID:$GITHUB_RUN_ATTEMPT"')
        produced = next(step for step in packages["steps"] if step.get("id") == "browser_packages")
        self.assertEqual(produced["with"]["name"], "little-leaf-pinned-chromium-${{ github.sha }}-${{ github.run_attempt }}")
        self.assertEqual(packages["outputs"]["browser_packages_id"], "${{ steps.browser_packages.outcome == 'success' && steps.browser_packages.outputs.artifact-id || '' }}")
        self.assertEqual(build["outputs"]["browser_packages_id"], "${{ needs.browser_packages.outputs.browser_packages_id }}")
        self.assertEqual(build["outputs"]["browser_packages_binding"], "${{ needs.browser_packages.outputs.binding }}")
        for name in ("play", "browser", "compatibility"):
            route = "LOCKED_BROWSER_PROVISION"
            self.assertEqual(jobs[name]["env"][route], "${{ needs.build.outputs.locked_browser }}")
            with self.subTest(job=name):
                steps = jobs[name]["steps"]
                restore = next(s for s in steps if s.get("name", "").startswith("Restore exact-attempt"))
                install = next(s for s in steps if "play_provision.py candidate" in s.get("run", ""))
                self.assertLess(steps.index(restore), steps.index(install))
                self.assertIn(f"env.{route} == 'true'", restore["if"])
                self.assertIn("format('{0}:{1}:{2}', github.sha, github.run_id, github.run_attempt)", restore["if"])
                self.assertEqual(restore["with"]["artifact-ids"], "${{ needs.build.outputs.browser_packages_id }}")
                self.assertEqual(restore["with"]["digest-mismatch"], "error")
                self.assertNotIn("continue-on-error", restore)
                self.assertNotIn("continue-on-error", install)
                self.assertIn('"$RUNNER_TEMP/pinned-chromium-packages"', install["run"])

    def test_play_independent_but_mandatory_on_both_qualification_paths(self):
        workflow = (ROOT / ".github/workflows/build-web.yml").read_text()
        jobs = yaml.safe_load(workflow)["jobs"]
        play = jobs["play"]
        self.assertEqual(play["name"], "browser (play)")
        self.assertEqual(jobs["browser"]["name"], "browser (recovery)")
        self.assertEqual(play["needs"], "build")
        self.assertIn("play", jobs["gate"]["needs"])
        self.assertIn("play", jobs["firebase"]["needs"])
        for step in jobs["gate"]["steps"]:
            if step.get("name", "").startswith(("Accept explicitly", "Require every")):
                self.assertEqual(step["env"]["PLAY"], "${{ needs.play.result }}")
        self.assertNotIn("continue-on-error", json.dumps(play))
        self.assertIn('"$BUILD" "$PLAY" "$BROWSER"', workflow)
        route = play["env"]["ORDINARY_PR"]
        for safe_input in ("github.event_name == 'pull_request'", "inputs.release_tag == ''",
                           "!inputs.firebase_preview", "!inputs.itch_preview", "!inputs.itch_test_entry",
                           "inputs.publication_receipt == ''"):
            self.assertIn(safe_input, route)
        steps = play["steps"]
        legacy = next(step for step in steps if step.get("name", "").startswith("Install shared"))
        checked = next(step for step in steps if step.get("name", "").startswith("Install only missing"))
        self.assertEqual(legacy["if"], "env.LOCKED_BROWSER_PROVISION != 'true'")
        self.assertEqual(checked["if"], "env.LOCKED_BROWSER_PROVISION == 'true'")
        download = next(step for step in steps if "download-artifact@" in step.get("uses", "") and
                        step.get("with", {}).get("artifact-ids", "").endswith("outputs.inputs_id }}"))
        self.assertEqual(download["with"]["artifact-ids"], "${{ needs.build.outputs.inputs_id }}")
        self.assertEqual(download["with"]["digest-mismatch"], "error")
        real = next(step for step in steps if step.get("name", "").startswith("Verify fresh tutorial"))
        self.assertNotIn("if", real)
        self.assertEqual(real["timeout-minutes"], 6)
        for required in ("--ocr-fixtures", "--web-build", "--layout-report", "--engine-report"):
            self.assertIn(required, real["run"])
        artifact = next(step for step in steps if "upload-artifact@" in step.get("uses", ""))
        self.assertEqual(artifact["with"]["name"], "little-leaf-browser-play-${{ github.sha }}-${{ github.run_attempt }}")

    @unittest.skipUnless(os.name == "posix" and shutil.which("bash") and shutil.which("timeout"), "Linux shell contract")
    def test_play_provision_requires_both_parallel_commands(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-web.yml").read_text())
        steps = workflow["jobs"]["play"]["steps"]
        step = next(step for step in steps if step.get("name", "").startswith("Install only missing"))
        with TemporaryDirectory() as d:
            root = Path(d)
            for command, other, status in (("npm", "python3", "DRIVER_STATUS"), ("python3", "npm", "PACKAGE_STATUS")):
                stub = root / command
                stub.write_text("#!/bin/bash\n"
                                f'touch "$RUNNER_TEMP/{command}.marker"\n'
                                f'for i in {{1..100}}; do [[ -e "$RUNNER_TEMP/{other}.marker" ]] && exit "${status}"; sleep .025; done\n'
                                "exit 99\n")
                stub.chmod(0o700)
            for driver_status, package_status in ((0, 0), (41, 0), (0, 42), (41, 42)):
                with self.subTest(driver=driver_status, packages=package_status):
                    env = {**os.environ, "PATH": f"{root}:{os.environ['PATH']}", "RUNNER_TEMP": d,
                           "DRIVER_STATUS": str(driver_status), "PACKAGE_STATUS": str(package_status)}
                    for marker in root.glob("*.marker"):
                        marker.unlink()
                    result = subprocess.run(["bash", "-c", step["run"]], env=env, capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, int(bool(driver_status or package_status)), result.stderr)
                    if result.returncode:
                        self.assertIn(f"driver={driver_status} packages={package_status}", result.stderr)
                    self.assertEqual(len(list(root.glob("*.marker"))), 2)


if __name__ == "__main__":
    unittest.main()
