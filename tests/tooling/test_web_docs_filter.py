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
                     "firebase/package-lock.json", "tools/build/build_web.py", ".github/workflows/ci.yml",
                     "tests/welcome_audio_qa.md", "docs/design/reference.svg"):
            with self.subTest(path=path):
                self.assertTrue(pr_runs(["docs/README.md", path]))

    def test_markdown_consumed_by_build_helpers_stays_eligible(self):
        inputs = set()
        for helper in (ROOT / "tools/build").glob("build*.py"):
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
                     "docs/art-audio/third-party/NOTICE.md", "tools/release/publish_itch.py",
                     "tools/ci/pr_ci_scope.py", "tools/ci/toolchain.json", ".github/workflows/ci.yml",
                     "docs/design/reference.svg", "docs/../game/main.md", "docs/qa\nname.md"):
            self.assertFalse(lightweight_diff(self.raw(path)), path)
            self.assertFalse(lightweight_diff(self.raw("README.md") + self.raw(path)), path)

    def test_tooling_tests_are_checked_without_unrelated_runtime(self):
        for path in ("tools/diagnostics/retained_handoff_route.py", "tools/diagnostics/current_handoff_route.py",
                     "tests/tooling/test_ci_checkout.py", "tests/tooling/test_engine_shards.py",
                     "tests/tooling/test_reuse_main_ci.py"):
            self.assertTrue(lightweight_diff(self.raw(path)), path)
            self.assertTrue(lightweight_diff(self.raw(path, "A", "000000")), path)
        for path in ("tests/tooling/source_paths.js", "tests/tooling/__init__.py",
                     "tests/tooling/helper.py", "tests/tooling/test_nested/helper.py",
                     "tests/fixtures/current.json", "tests/service/test_role_boundaries.gd",
                     "tools/diagnostics/cloud_flow_diagnostic.py",
                     "tests/run_integration_candidate.py", "tools/ci/engine_shards.py"):
            self.assertFalse(lightweight_diff(self.raw(path)), path)
            self.assertFalse(lightweight_diff(self.raw("tests/tooling/test_ci_checkout.py") + self.raw(path)), path)
        for status in ("D", "R100", "T"):
            self.assertFalse(lightweight_diff(self.raw("tests/tooling/test_ci_checkout.py", status)))
        self.assertFalse(lightweight_diff(self.raw("tests/tooling/test_ci_checkout.py", new="100755")))

    def test_rename_delete_mode_and_malformed_are_full(self):
        for raw in (self.raw("README.md", "D", new="000000"), self.raw("README.md", "R100"),
                    self.raw("README.md", "T"), self.raw("README.md", new="100755"),
                    self.raw("README.md", old="120000"), self.raw("README.md")[:-1],
                    b"unexpected\0README.md\0", self.raw("README.md").replace(b"a"*40,b"unknown")):
            self.assertFalse(lightweight_diff(raw))

    def test_actual_merge_tree_and_fail_closed_source_binding(self):
        for relative in ("README.md", "tests/tooling/test_ci_checkout.py"):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                env = os.environ | {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
                def git(*args):
                    return subprocess.check_output(["git", "-c", "core.autocrlf=false", "-c", "user.name=Fixture",
                                                   "-c", "user.email=fixture@invalid", *args], cwd=root, env=env, stderr=subprocess.DEVNULL)
                git("init", "-q")
                target.write_text("base\n")
                git("add", "."); git("commit", "-qm", "base")
                base = git("rev-parse", "HEAD").decode().strip()
                git("checkout", "-qb", "fixture")
                target.write_text("head\n")
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
                target.write_text("uncommitted\n")
                self.assertEqual(classify(context, event, git), "full")
                git("checkout", "--", relative);git("checkout", "-q", "--detach", head)
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

    def test_unit_guard_detects_missing_native_job_validator_mutant(self):
        # Use the real guard's unittest discovery, with an added tooling unit
        # module exercising the production release validator. Removing its
        # mandatory-job check must still fail, even without engine/browser jobs.
        test_source = '''import inspect, unittest
from qualification.reuse_main_ci import require_jobs, REQUIRED_JOBS
MUTATION
class AddedCoverageTest(unittest.TestCase):
    def test_missing_native_job_is_rejected(self):
        jobs = [dict(name=n, status="completed", conclusion="success")
                for n in REQUIRED_JOBS if n != "web / engine (0)"]
        with self.assertRaises(ValueError):
            require_jobs(jobs)
'''
        original = 'if len(names) != len(set(names)) or not REQUIRED_JOBS.issubset(names):'
        mutation = ('source = inspect.getsource(require_jobs)\n'
                    f'assert source.count({original!r}) == 1\n'
                    f'exec(source.replace({original!r}, "if False:"))')
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'test_added_coverage.py'
            env = os.environ | {"PYTHONPATH": str(ROOT / 'tools')}
            for code, expected in (('', 0), (mutation, 1)):
                target.write_text(test_source.replace('MUTATION', code))
                result = subprocess.run([os.sys.executable, '-m', 'unittest', 'discover',
                                         '-s', directory, '-p', 'test_*.py'],
                                        env=env, capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                if expected:
                    self.assertIn('ValueError not raised', result.stderr)

    def test_existing_fast_guard_detects_original_linux_socket_defect(self):
        from unittest.mock import patch
        from tests.tooling import test_retained_handoff_route as retained
        source = (ROOT / 'tools/diagnostics/retained_handoff_route.py').read_text()
        fixed = "folder = root/'tmp' if name == 'TMPDIR' else output/'disposable'/name"
        self.assertEqual(source.count(fixed), 1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'tools/diagnostics/retained_handoff_route.py'
            target.parent.mkdir(parents=True)
            for code, failures in ((source, 0), (source.replace(fixed, "folder = output/'disposable'/name"), 1)):
                target.write_text(code)
                result = unittest.TestResult()
                with patch.object(retained, 'ROOT', root):
                    retained.DisposablePathTests(
                        'test_original_linux_workspace_socket_fits_with_only_tmpdir_changed').run(result)
                self.assertFalse(result.errors, result.errors)
                self.assertEqual(len(result.failures), failures, result.failures)
                if failures:
                    self.assertIn('126 not less than 108', result.failures[0][1])

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
