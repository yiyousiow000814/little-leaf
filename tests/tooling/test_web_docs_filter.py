"""PR trigger, complete merge-diff classification and limited gate regressions.

All fixtures are local Git histories; these tests never run a build or publish.
"""
from pathlib import Path
import re
import unittest
import os
import subprocess
import tempfile
from ci.pr_ci_scope import classify, lightweight_diff, lightweight_gate, allowed

ROOT = Path(__file__).resolve().parents[2]


def pr_runs(changed):
    workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    block = workflow.split("  pull_request:\n", 1)[1].split("  push:", 1)[0]
    patterns = re.findall(r"^      - '([^']+)'$", block, re.M)
    if not patterns:
        return True  # All PRs now report guard/gate, including documentation.
    for path in changed:
        included = False
        for pattern in patterns:
            negative = pattern.startswith("!")
            glob = pattern[1:] if negative else pattern
            expression = re.escape(glob).replace(r"\*\*/", "(?:.*/)?").replace(r"\*\*", ".*").replace(r"\*", "[^/]*")
            if re.fullmatch(expression, path):
                included = not negative
        if included:
            return True
    return False


class WebDocsFilterTests(unittest.TestCase):
    def test_ordinary_docs_runs_guard(self):
        for changed in (["README.md"], ["docs/README.md"], ["docs/qa/review.md"],
                        ["README.md", "docs/archive/nested/receipt.md"]):
            with self.subTest(changed=changed):
                self.assertTrue(pr_runs(changed))

    def test_all_third_party_inputs_build(self):
        for path in ("docs/art-audio/third-party/CRAZYGAMES-SDK-NOTICE.md",
                     "docs/art-audio/third-party/GODOT-AA-LICENSE.txt", "docs/art-audio/third-party/new/NOTICE.md"):
            with self.subTest(path=path):
                self.assertTrue(pr_runs([path]))

    def test_mixed_docs_and_non_docs_build(self):
        for path in ("scripts/main.gd", "assets/NOTICE.md", "data/save-schema.json",
                     "firebase/package-lock.json", "tools/build_web.py", ".github/workflows/ci.yml",
                     "tests/welcome_audio_qa.md", "docs/design/reference.svg"):
            with self.subTest(path=path):
                self.assertTrue(pr_runs(["docs/README.md", path]))

    def test_markdown_consumed_by_build_helpers_stays_eligible(self):
        inputs = set()
        for helper in (ROOT / "tools").glob("build*.py"):
            inputs.update(re.findall(r'''["'](docs/[^"']+\.md)["']''', helper.read_text(encoding="utf-8")))
        self.assertIn("docs/art-audio/third-party/CRAZYGAMES-SDK-NOTICE.md", inputs)
        for path in inputs:
            with self.subTest(path=path):
                self.assertTrue(pr_runs([path]))
                self.assertFalse(allowed(path), "Consumed distribution input must never classify lightweight")



class PrScopeTests(unittest.TestCase):
    def raw(self, path, status="M", old="100644", new="100644"):
        return (f":{old} {new} {'a'*40} {'b'*40} {status}\0{path}\0").encode()

    def test_nonempty_regular_allowed_changes_only(self):
        for path in ("README.md", "docs/qa/review.md", "tools/diagnostics/diagnose_itch_status.py", "tests/tooling/test_release.py"):
            self.assertTrue(lightweight_diff(self.raw(path)))
            self.assertTrue(lightweight_diff(self.raw(path, "A", "000000")))
        self.assertFalse(lightweight_diff(b""))
        for path in ("game/scripts/main.gd", "platform/web/local.js", "assets/NOTICE.md",
                     "docs/art-audio/third-party/NOTICE.md", "tools/publish_itch.py",
                     "tools/ci/pr_ci_scope.py", "tools/ci/toolchain.json", ".github/workflows/ci.yml",
                     "docs/design/reference.svg", "docs/../game/main.md", "docs/qa\nname.md"):
            self.assertFalse(lightweight_diff(self.raw(path)), path)
            self.assertFalse(lightweight_diff(self.raw("README.md") + self.raw(path)), path)

    def test_rename_delete_mode_and_malformed_are_full(self):
        for raw in (self.raw("README.md", "D", new="000000"), self.raw("README.md", "R100"),
                    self.raw("README.md", "T"), self.raw("README.md", new="100755"),
                    self.raw("README.md", old="120000"), self.raw("README.md")[:-1],
                    b"unexpected\0README.md\0", self.raw("README.md").replace(b"a"*40,b"unknown")):
            self.assertFalse(lightweight_diff(raw))

    def test_actual_merge_tree_and_fail_closed_source_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = os.environ | {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
            def git(*args):
                return subprocess.check_output(["git", "-c", "core.autocrlf=false", "-c", "user.name=Fixture",
                                               "-c", "user.email=fixture@invalid", *args], cwd=root, env=env, stderr=subprocess.DEVNULL)
            git("init", "-q")
            (root / "README.md").write_text("base\n")
            git("add", "."); git("commit", "-qm", "base")
            base = git("rev-parse", "HEAD").decode().strip()
            git("checkout", "-qb", "fixture")
            (root / "README.md").write_text("head\n")
            git("commit", "-qam", "docs")
            head = git("rev-parse", "HEAD").decode().strip()
            git("checkout", "-q", "--detach", base);git("merge", "--no-ff", "-qm", "merge", "fixture")
            merge = git("rev-parse", "HEAD").decode().strip()
            event = {"pull_request": {"base": {"sha": base}, "head": {"sha": head}}}
            context = {"GITHUB_EVENT_NAME": "pull_request", "GITHUB_SHA": merge,
                       "RELEASE_TAG": "", "FIREBASE_PREVIEW": "false", "ITCH_PREVIEW": "false"}
            self.assertEqual(classify(context, event, git), "lightweight")
            for key, value in (("GITHUB_EVENT_NAME", "push"), ("GITHUB_EVENT_NAME", "workflow_dispatch"),
                               ("GITHUB_SHA", head), ("RELEASE_TAG", "v0.1.11"),
                               ("FIREBASE_PREVIEW", "true"), ("ITCH_PREVIEW", "true")):
                self.assertEqual(classify(context | {key: value}, event, git), "full")
            self.assertEqual(classify(context, {}, git), "full")
            self.assertEqual(classify(context, event, lambda *a: (_ for _ in ()).throw(OSError("history unavailable"))), "full")
            (root / "README.md").write_text("uncommitted\n")
            self.assertEqual(classify(context, event, git), "full")
            git("checkout", "--", "README.md");git("checkout", "-q", "--detach", head)
            self.assertEqual(classify(context | {"GITHUB_SHA": head}, event, git), "full")

    def test_lightweight_aggregate_rejects_false_qualification(self):
        env = {"CI_SCOPE": "lightweight", "GITHUB_EVENT_NAME": "pull_request", "RELEASE_TAG": "",
               "FIREBASE_PREVIEW": "false", "ITCH_PREVIEW": "false", "GUARD": "success"}
        jobs = ("ENGINE", "HISTORICAL", "BUILD", "BROWSER", "COMPATIBILITY", "FIREBASE")
        env.update({job: "skipped" for job in jobs})
        self.assertTrue(lightweight_gate(env))
        for job in jobs:
            for state in ("success", "failure", "cancelled", ""):
                self.assertFalse(lightweight_gate(env | {job: state}))
        for key, value in (("GUARD", "failure"), ("CI_SCOPE", "full"), ("GITHUB_EVENT_NAME", "push"),
                           ("RELEASE_TAG", "v0.1.11"), ("FIREBASE_PREVIEW", "true"),
                           ("ITCH_PREVIEW", "true"), ("WEB_ARTIFACT", "123"),
                           ("FIREBASE_ARTIFACT", "123"), ("FIREBASE_MANIFEST", "abc")):
            self.assertFalse(lightweight_gate(env | {key: value}))

    def test_workflow_preserves_full_gate_and_all_guard_checks(self):
        workflow = (ROOT / ".github/workflows/build-web.yml").read_text(encoding="utf-8")
        for job in ("engine", "historical", "build"):
            self.assertIn(f"  {job}:\n    if: needs.guard.outputs.scope != 'lightweight'", workflow)
        self.assertIn("    if: always()\n    needs: [guard, engine, historical, build, browser, compatibility, firebase]", workflow)
        self.assertIn("python3 tools/ci/pr_ci_scope.py --check-lightweight-gate", workflow)
        self.assertIn('for result in "$GUARD" "$ENGINE" "$HISTORICAL" "$BUILD" "$BROWSER" "$COMPATIBILITY"; do test "$result" = success || exit 1; done', workflow)
        self.assertIn('test -n "$WEB_ARTIFACT"', workflow)
        self.assertIn("python3 -m unittest discover -s tests/tooling -t . -p 'test_*.py' -v", workflow)


if __name__ == "__main__":
    unittest.main()
