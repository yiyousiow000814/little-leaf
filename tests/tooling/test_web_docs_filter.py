"""Small changed-path cases for the PR filter; never run a build.

GitHub evaluates patterns in order, with a later positive restoring a match.
This test matcher supports only the literal, * and ** patterns used here.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def pr_runs(changed):
    workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    block = workflow.split("  pull_request:\n", 1)[1].split("  push:", 1)[0]
    patterns = re.findall(r"^      - '([^']+)'$", block, re.M)
    if not patterns:
        raise AssertionError("PR path filters required")
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
    def test_ordinary_docs_only_skip(self):
        for changed in (["README.md"], ["docs/README.md"], ["docs/qa/review.md"],
                        ["README.md", "docs/archive/nested/receipt.md"]):
            with self.subTest(changed=changed):
                self.assertFalse(pr_runs(changed))

    def test_all_third_party_inputs_build(self):
        for path in ("docs/art-audio/third-party/CRAZYGAMES-SDK-NOTICE.md",
                     "docs/art-audio/third-party/GODOT-AA-LICENSE.txt", "docs/art-audio/third-party/new/NOTICE.md"):
            with self.subTest(path=path):
                self.assertTrue(pr_runs([path]))

    def test_mixed_docs_and_non_docs_build(self):
        for path in ("scripts/main.gd", "assets/NOTICE.md", "data/save-schema.json",
                     "firebase/package-lock.json", "ci/build_web.py", ".github/workflows/ci.yml",
                     "tests/welcome_audio_qa.md", "docs/design/reference.svg"):
            with self.subTest(path=path):
                self.assertTrue(pr_runs(["docs/README.md", path]))

    def test_markdown_consumed_by_build_helpers_stays_eligible(self):
        inputs = set()
        for helper in (ROOT / "ci").glob("build*.py"):
            inputs.update(re.findall(r'''["'](docs/[^"']+\.md)["']''', helper.read_text(encoding="utf-8")))
        self.assertIn("docs/art-audio/third-party/CRAZYGAMES-SDK-NOTICE.md", inputs)
        for path in inputs:
            with self.subTest(path=path):
                self.assertTrue(pr_runs([path]))


if __name__ == "__main__":
    unittest.main()
