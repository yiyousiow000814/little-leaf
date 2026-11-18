"""Exercise the reviewed architecture-document allowlist and its fail-closed boundaries."""
import unittest

from tools.ci.pr_ci_scope import classify, lightweight_diff, lightweight_gate


ARCHITECTURE_FILES = (
    "docs/architecture-performance/README.md",
    "docs/architecture-performance/architecture-contract.md",
    "docs/architecture-performance/current-function-atlas.mmd",
    "docs/architecture-performance/generate-function-atlas.py",
    "docs/architecture-performance/performance-workload-ledger.xlsx",
    "docs/architecture-performance/target-workflow.mmd",
)
BASE, HEAD, MERGE = ("1" * 40, "2" * 40, "3" * 40)
NORMAL_ENV = {
    "GITHUB_EVENT_NAME": "pull_request",
    "GITHUB_SHA": MERGE,
    "FIREBASE_PREVIEW": "false",
    "ITCH_PREVIEW": "false",
}
EVENT = {"pull_request": {"base": {"sha": BASE}, "head": {"sha": HEAD}}}


def record(path, before="000000", after="100644", status="A"):
    old_sha = "0" * 40 if before == "000000" else "a" * 40
    new_sha = "0" * 40 if after == "000000" else "b" * 40
    return f":{before} {after} {old_sha} {new_sha} {status}\0{path}\0".encode()


def mock_git(diff, parents=f"{MERGE} {BASE} {HEAD}", dirty=b""):
    def git(*command):
        if command == ("rev-parse", "HEAD"):
            return MERGE.encode()
        if command == ("rev-list", "--parents", "-n", "1", "HEAD"):
            return parents.encode()
        if command == ("status", "--porcelain", "--untracked-files=no"):
            return dirty
        if command == ("diff", "--raw", "--no-abbrev", "-z", "--no-renames",
                       "--no-ext-diff", "--no-textconv", BASE, "HEAD", "--"):
            return diff
        raise AssertionError(f"Unexpected Git command: {command}")

    return git


class ArchitectureDocsScopeTest(unittest.TestCase):
    def test_all_six_reviewed_deliverables_are_lightweight_on_pr(self):
        for mode in ("A", "M"):
            diff = b"".join(record(path, before="000000" if mode == "A" else "100644",
                                   status=mode) for path in ARCHITECTURE_FILES)
            with self.subTest(mode=mode):
                self.assertTrue(lightweight_diff(diff))
                self.assertEqual(classify(NORMAL_ENV, EVENT, mock_git(diff)), "lightweight")

    def test_only_exact_additional_paths_and_no_mixed_runtime_change(self):
        docs = record(ARCHITECTURE_FILES[-1])
        for path in ("docs/architecture-performance/another.mmd",
                     "docs/architecture-performance/another.xlsx",
                     "docs/architecture-performance/helper.py",
                     "docs/current-function-atlas.mmd",
                     "docs/architecture-performance/../architecture-performance/target-workflow.mmd",
                     "docs/architecture-performance/target-workflow.MMD",
                     "game/scripts/main.gd",
                     "tools/ci/pr_ci_scope.py",
                     ".github/workflows/build-web.yml"):
            with self.subTest(path=path):
                self.assertEqual(classify(NORMAL_ENV, EVENT, mock_git(docs + record(path))), "full")

    def test_executable_symlink_deletion_rename_malformed_or_empty_fail_closed(self):
        path = ARCHITECTURE_FILES[3]
        for diff in (record(path, after="100755"),
                     record(path, after="120000"),
                     record(path, before="100644", after="000000", status="D"),
                     record(path, before="100644", status="R100"),
                     record(path, before="100644", after="000000", status="D") + record(ARCHITECTURE_FILES[-1]),
                     record(path)[:-1], b""):
            with self.subTest(diff=diff[:16]):
                self.assertEqual(classify(NORMAL_ENV, EVENT, mock_git(diff)), "full")

    def test_releases_previews_and_unverified_checkouts_stay_full(self):
        diff = record(ARCHITECTURE_FILES[3])
        for changes in ({"GITHUB_EVENT_NAME": "push"}, {"GITHUB_EVENT_NAME": "workflow_dispatch"},
                        {"RELEASE_TAG": "v0.1.11"}, {"FIREBASE_PREVIEW": "true"},
                        {"ITCH_PREVIEW": "true"}, {"FIREBASE_PREVIEW": None},
                        {"GITHUB_SHA": HEAD}):
            with self.subTest(changes=changes):
                self.assertEqual(classify({**NORMAL_ENV, **changes}, EVENT, mock_git(diff)), "full")
        self.assertEqual(classify(NORMAL_ENV, EVENT, mock_git(diff, parents=f"{MERGE} {HEAD} {BASE}")), "full")
        self.assertEqual(classify(NORMAL_ENV, EVENT, mock_git(diff, dirty=b" M game/main.tscn")), "full")

    def test_lightweight_gate_requires_all_heavy_jobs_skipped_and_no_artifact(self):
        env = dict(NORMAL_ENV, CI_SCOPE="lightweight", GUARD="success",
                   ENGINE="skipped", HISTORICAL="skipped", BUILD="skipped",
                   BROWSER="skipped", COMPATIBILITY="skipped", FIREBASE="skipped")
        self.assertTrue(lightweight_gate(env))
        for changes in ({"WEB_ARTIFACT": "123"}, {"FIREBASE_ARTIFACT": "123"},
                        {"FIREBASE_MANIFEST": "digest"}, {"BROWSER": "success"},
                        {"GUARD": "failure"}, {"GITHUB_EVENT_NAME": "push"}):
            with self.subTest(changes=changes):
                self.assertFalse(lightweight_gate({**env, **changes}))


if __name__ == "__main__":
    unittest.main()
