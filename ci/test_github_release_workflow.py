"""Exercise release gates without tokens, network, or publication."""
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/github-release.yml"
SHA = "a" * 40
OBJECT = "b" * 40


def run_blocks():
    lines = WORKFLOW.read_text().splitlines()
    blocks = []
    for index, line in enumerate(lines):
        if line == "        run: |":
            body = []
            for item in lines[index + 1:]:
                if item and not item.startswith("          "):
                    break
                body.append(item[10:])
            blocks.append("\n".join(body) + "\n")
    return blocks


class MetadataGateTests(unittest.TestCase):
    def run_prepare(self, mutation=None, tag="v0.1.9", event="workflow_dispatch", version="0.1.9", tags=None):
        notes = {"schema_version": 1, "version": version, "status": "released",
                 "date": "2000-01-01", "new": ["Inbox letters."], "fixed": ["Save recovery."]}
        if mutation:
            notes.update(mutation)
        def git(args, text=True):
            command = args[1:]
            if command == ["rev-parse", "--verify", "refs/tags/" + tag]:
                return OBJECT
            if command == ["rev-parse", "--verify", "refs/tags/" + tag + "^{commit}"]:
                return SHA
            if command == ["show", SHA + ":project.godot"]:
                return 'config/version="' + version + '"'
            if command == ["show", SHA + ":data/release_notes.json"]:
                return json.dumps(notes)
            if command == ["tag", "--list"]:
                return tags if tags is not None else "v0.1.8\nv0.1.9-alpha-2\nv0.1.9\nv0.1.10"
            raise AssertionError("Unexpected git command: " + repr(command))
        source = run_blocks()[0].split("python3 - <<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "outputs"
            env = {"RELEASE_TAG": tag, "EVENT_NAME": event, "EVENT_SHA": "c" * 40,
                   "GITHUB_REPOSITORY": "owner/repo", "GITHUB_OUTPUT": str(output)}
            with patch.dict(os.environ, env), patch("subprocess.check_output", side_effect=git):
                exec(compile(source, "release-prepare", "exec"), {})
            return dict(line.split("=", 1) for line in output.read_text().splitlines())

    def test_exact_tag_source_and_stable_previous_tag(self):
        result = self.run_prepare()
        self.assertEqual(result["tag"], "v0.1.9")
        self.assertEqual(result["sha"], SHA)
        self.assertEqual(result["tag_object"], OBJECT)
        notes = base64.b64decode(result["notes"]).decode()
        self.assertIn("## New Features\n- Inbox letters.", notes)
        self.assertIn("## Bug Fixes\n- Save recovery.", notes)
        self.assertIn("------\n\n## Changelog", notes)
        self.assertIn("/compare/v0.1.8...v0.1.9", notes)

    def test_hotfix_changelog_uses_immediate_lower_release(self):
        versions = ["0.1.9", "0.1.10", "0.1.10a", "0.1.10b", "0.1.10c", "0.1.10z", "0.1.11"]
        tags = "\n".join("v" + value for value in reversed(versions))
        tags += "\nv0.1.10aa\nv0.1.10A\nv0.1.11-dev.1\nv00.1.11"
        for previous, value in zip(versions, versions[1:]):
            with self.subTest(version=value):
                result = self.run_prepare(tag="v" + value, version=value, tags=tags)
                notes = base64.b64decode(result["notes"]).decode()
                self.assertIn("/compare/v" + previous + "...v" + value, notes)
                self.assertEqual(result["sha"], SHA)

    def test_hotfix_metadata_remains_exact_and_released(self):
        for mutation in ({"version": "0.1.10"}, {"status": "draft"}):
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                self.run_prepare(mutation, tag="v0.1.10a", version="0.1.10a")

    def test_reject_mismatched_or_unreleased_metadata(self):
        for change in ({"version": "0.1.10"}, {"status": "draft"}, {"schema_version": 2},
                       {"date": "9999-01-01"}, {"new": [], "fixed": []},
                       {"new": "not a list"}, {"new": ["injected\nheading"]}):
            with self.subTest(change=change), self.assertRaises((ValueError, TypeError)):
                self.run_prepare(change)

    def test_reject_nonstable_or_injected_tag(self):
        for tag in ("v0.1.9-alpha-2", "v01.1.9", "main", "v0.1.9;echo unsafe", "v0.1.10A", "v0.1.10aa",
                    "v0.1.10a-dev.1", "v0.1.10a+build.1", "v0.1.10a\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.run_prepare(tag=tag)

    def test_reject_tag_moved_since_push(self):
        with self.assertRaisesRegex(ValueError, "triggering source"):
            self.run_prepare(event="push")


@unittest.skipUnless(shutil.which("bash"), "Bash is required for runner shell tests")
class PublicationGateTests(unittest.TestCase):
    def run_publish(self, scenario):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            log = root / "gh-calls.jsonl"
            gh = root / "gh"
            gh.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
mode = os.environ['SCENARIO']
log = Path(os.environ['MOCK_LOG'])
with log.open('a') as out:
    out.write(json.dumps(args) + '\\n')
if args[:2] == ['release', 'create']:
    sys.exit(0)
if any('/git/ref/tags/' in arg for arg in args):
    print('c' * 40 if mode == 'moved' else 'b' * 40)
    sys.exit(0)
if mode == 'existing':
    print('HTTP/2.0 200 OK')
    print('{}')
    sys.exit(0)
if mode == 'missing':
    print('HTTP/2.0 404 Not Found')
    sys.exit(1)
if mode == 'auth':
    print('HTTP/2.0 403 Forbidden')
    sys.exit(1)
sys.exit(1)
""")
            gh.chmod(0o755)
            summary = root / "summary"
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                       SCENARIO=scenario, MOCK_LOG=str(log), RUNNER_TEMP=str(root),
                       GITHUB_STEP_SUMMARY=str(summary), GH_REPO="owner/repo",
                       RELEASE_TAG="v0.1.9", SOURCE_SHA=SHA, TAG_OBJECT=OBJECT,
                       NOTES_BASE64=base64.b64encode(b"source-bound notes\n").decode(),
                       GH_TOKEN="synthetic-test-token")
            completed = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", run_blocks()[1]],
                                       env=env, capture_output=True, text=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return completed.returncode, [call for call in calls if call[:2] == ["release", "create"]]

    def test_existing_release_is_retained(self):
        code, writes = self.run_publish("existing")
        self.assertEqual(code, 0)
        self.assertEqual(writes, [])

    def test_only_explicit_absence_creates_verified_existing_tag_release(self):
        code, writes = self.run_publish("missing")
        self.assertEqual(code, 0)
        self.assertEqual(len(writes), 1)
        self.assertIn("--verify-tag", writes[0])
        self.assertIn(SHA, writes[0])
        self.assertIn("--notes-file", writes[0])

    def test_tag_change_auth_and_network_failure_never_publish(self):
        for scenario in ("moved", "auth", "network"):
            with self.subTest(scenario=scenario):
                code, writes = self.run_publish(scenario)
                self.assertNotEqual(code, 0)
                self.assertEqual(writes, [])


if __name__ == "__main__":
    unittest.main()
