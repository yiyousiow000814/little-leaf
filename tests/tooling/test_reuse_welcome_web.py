"""Focused artifact qualification regressions; no network, engine or browser."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from tools.reuse_welcome_web import qualify, reuse, verify_equivalence


class ReuseWelcomeWebTests(unittest.TestCase):
    def setUp(self):
        self.repo = "owner/repo"
        self.sha = "a" * 40
        self.run = {"id": 123, "repository": {"full_name": self.repo},
                    "path": ".github/workflows/ci.yml", "status": "completed",
                    "conclusion": "success", "run_attempt": 2, "head_sha": "b" * 40,
                    "referenced_workflows": [{"sha": self.sha,
                        "path": self.repo + "/.github/workflows/build-web.yml@" + self.sha}]}
        self.artifact = {"id": 456, "expired": False,
                         "name": f"little-leaf-web-{self.sha}-2", "workflow_run": {"id": 123}}

    def check(self, run=None, artifact=None):
        return qualify(run or self.run, artifact or self.artifact, self.repo, self.sha, 123, 456)

    def test_successful_exact_merge_source(self):
        self.assertEqual(self.check()["artifact_name"], self.artifact["name"])

    def test_failed_pending_other_run_or_repository_rejected(self):
        for key, value in [("status", "in_progress"), ("conclusion", "failure"),
                           ("id", 999), ("repository", {"full_name": "other/repo"}),
                           ("path", ".github/workflows/welcome-audio.yml"), ("run_attempt", 0)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.check(run={**self.run, key: value})

    def test_head_sha_alone_cannot_authorize_different_built_source(self):
        run = copy.deepcopy(self.run)
        run["head_sha"] = self.sha
        run["referenced_workflows"][0]["sha"] = "c" * 40
        with self.assertRaises(ValueError):
            self.check(run=run)

    def test_missing_or_foreign_reusable_workflow_rejected(self):
        for refs in ([], [{"sha": self.sha, "path": "other/repo/.github/workflows/build-web.yml@main"}]):
            with self.subTest(refs=refs), self.assertRaises(ValueError):
                self.check(run={**self.run, "referenced_workflows": refs})

    def test_expired_other_source_attempt_variant_id_or_run_rejected(self):
        for key, value in [("expired", True), ("expired", None), ("id", 999),
                           ("name", f"little-leaf-web-{self.sha}-1"),
                           ("name", f"little-leaf-web-{'c' * 40}-2"),
                           ("name", f"little-leaf-crazygames-{self.sha}-2"),
                           ("workflow_run", {"id": 999})]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.check(artifact={**self.artifact, key: value})

    def test_head_checkout_records_separate_merge_source_and_verifies_download(self):
        self.run["html_url"] = "https://github.com/owner/repo/actions/runs/123"
        head = "b" * 40
        binding = {"source_commit": head, "built_source_commit": self.sha}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with patch("subprocess.check_output", side_effect=[head, json.dumps(self.run),
                       json.dumps(self.artifact)]), patch("tools.reuse_welcome_web.verify_equivalence", return_value="d" * 40) as equivalent:
                selection = reuse(self.repo, 123, 456, root, root / "output")
            equivalent.assert_called_once_with(root.resolve(), head, self.sha)
            self.assertEqual(selection["source_commit"], head)
            self.assertEqual(selection["built_source_commit"], self.sha)
            self.assertFalse((root / "output/artifact-reuse.json").exists())
            with patch("subprocess.check_output", side_effect=[head, json.dumps(binding)]) as read:
                receipt = reuse(self.repo, 123, 456, root, root / "output", phase="verify")
            self.assertEqual(read.call_args.args[0][-1], self.sha)
            self.assertEqual(receipt["binding"], binding)
            self.assertEqual(receipt["artifact_id"], 456)

    def test_changed_source_stops_before_artifact_selection(self):
        self.run["html_url"] = "https://github.com/owner/repo/actions/runs/123"
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with patch("subprocess.check_output", side_effect=["b" * 40, json.dumps(self.run),
                       json.dumps(self.artifact)]), patch("tools.reuse_welcome_web.verify_equivalence", side_effect=ValueError("changed source")), self.assertRaises(ValueError):
                reuse(self.repo, 123, 456, root, root / "output")
            self.assertFalse((root / "output").exists())

    def test_real_git_same_tree_acceptance_and_changed_tree_rejection(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.check_output(["git", "-c", "user.name=Offline QA", "-c",
                    "user.email=qa@example.invalid", "-C", str(root), *args], text=True).strip()
            git("init", "-q")
            (root / "fixture").write_text("synthetic source")
            git("add", "."); git("commit", "-qm", "Synthetic H")
            head = git("rev-parse", "HEAD")
            git("commit", "--allow-empty", "-qm", "Synthetic same-tree M")
            built = git("rev-parse", "HEAD")
            self.assertNotEqual(head, built)
            self.assertEqual(verify_equivalence(root, head, built), git("rev-parse", head + "^{tree}"))
            (root / "fixture").write_text("changed source")
            git("add", "."); git("commit", "-qm", "Synthetic changed M")
            with self.assertRaisesRegex(ValueError, "source trees must be identical"):
                verify_equivalence(root, head, git("rev-parse", "HEAD"))

    def test_failed_run_stops_before_download(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with patch("subprocess.check_output", side_effect=[self.sha,
                       json.dumps({**self.run, "conclusion": "failure"}), json.dumps(self.artifact)]), \
                    patch("subprocess.run") as download, self.assertRaises(ValueError):
                reuse(self.repo, 123, 456, root, root / "output")
            download.assert_not_called()
            self.assertFalse((root / "output").exists())


if __name__ == "__main__":
    unittest.main()
