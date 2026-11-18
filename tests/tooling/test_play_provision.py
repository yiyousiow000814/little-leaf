"""Contracts for the independent, checked production Play PR lane."""
import json
from pathlib import Path
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
        route = play["env"]["PLAY_LOCKED_PROVISION"]
        for safe_input in ("github.event_name == 'pull_request'", "inputs.release_tag == ''",
                           "!inputs.firebase_preview", "!inputs.itch_preview", "!inputs.itch_test_entry",
                           "inputs.publication_receipt == ''"):
            self.assertIn(safe_input, route)
        steps = play["steps"]
        legacy = next(step for step in steps if step.get("name", "").startswith("Install shared"))
        checked = next(step for step in steps if step.get("name", "").startswith("Install only missing"))
        self.assertEqual(legacy["if"], "env.PLAY_LOCKED_PROVISION != 'true'")
        self.assertEqual(checked["if"], "env.PLAY_LOCKED_PROVISION == 'true'")
        download = next(step for step in steps if "download-artifact@" in step.get("uses", ""))
        self.assertEqual(download["with"]["artifact-ids"], "${{ needs.build.outputs.inputs_id }}")
        self.assertEqual(download["with"]["digest-mismatch"], "error")
        real = next(step for step in steps if step.get("name", "").startswith("Verify fresh tutorial"))
        self.assertNotIn("if", real)
        self.assertEqual(real["timeout-minutes"], 6)
        for required in ("--ocr-fixtures", "--web-build", "--layout-report", "--engine-report"):
            self.assertIn(required, real["run"])
        artifact = next(step for step in steps if "upload-artifact@" in step.get("uses", ""))
        self.assertEqual(artifact["with"]["name"], "little-leaf-browser-play-${{ github.sha }}-${{ github.run_attempt }}")


if __name__ == "__main__":
    unittest.main()
