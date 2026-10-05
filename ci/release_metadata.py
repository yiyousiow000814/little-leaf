"""Validate release metadata without executing game code or accessing credentials."""
import argparse
from datetime import date
import json
from pathlib import Path
import re
import subprocess

STABLE = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
DIAGNOSTIC_VERSION = "0.1.9-alpha-1"
DIAGNOSTIC_TAG = "v" + DIAGNOSTIC_VERSION
DIAGNOSTIC_BRANCH = "release/0.1.8-save-diagnostic"
DIAGNOSTIC_BASE_TAG = "v0.1.8"
DIAGNOSTIC_BASE_SHA = "9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc"
DIAGNOSTIC_FIX_VERSION = "0.1.9-alpha-2"
DIAGNOSTIC_FIX_TAG = "v" + DIAGNOSTIC_FIX_VERSION
DIAGNOSTIC_FIX_BASE_SHA = "cee67c6720e3ec428d3e769bbb97de2a7780e5a9"


def release_kind(tag):
    if tag in (DIAGNOSTIC_TAG, DIAGNOSTIC_FIX_TAG):
        return "diagnostic"
    if re.fullmatch("v" + STABLE, tag):
        return "stable"
    raise ValueError("Expected a stable vX.Y.Z tag or an exact approved diagnostic tag (v0.1.9-alpha-1 or v0.1.9-alpha-2)")


def diagnostic_base(tag):
    if tag == DIAGNOSTIC_FIX_TAG:
        return DIAGNOSTIC_TAG, DIAGNOSTIC_FIX_BASE_SHA
    if tag == DIAGNOSTIC_TAG:
        return DIAGNOSTIC_BASE_TAG, DIAGNOSTIC_BASE_SHA
    raise ValueError("No approved diagnostic source route for this tag")


def git_value(root, *arguments):
    result = subprocess.run(["git", "-C", str(root), *arguments], capture_output=True, text=True)
    if result.returncode:
        raise ValueError("Required release source ref or history is missing")
    return result.stdout.strip()


def require_reviewed_source(root, tag):
    if release_kind(tag) == "stable":
        require_main_ancestor(root)
        return
    head = git_value(root, "rev-parse", "HEAD")
    base_tag, base_sha = diagnostic_base(tag)
    base = git_value(root, "rev-parse", base_tag + "^{commit}")
    branch = git_value(root, "rev-parse", "refs/remotes/origin/" + DIAGNOSTIC_BRANCH)
    tagged = git_value(root, "rev-parse", tag + "^{commit}")
    parents = git_value(root, "show", "-s", "--format=%P", "HEAD").split()
    if base != base_sha or parents != [base_sha]:
        raise ValueError("Diagnostic must be one reviewed squash commit directly on the pinned " + base_tag + " source")
    if branch != head or tagged != head:
        raise ValueError("Diagnostic tag must equal the reviewed maintenance branch tip and checked-out source")


def fetch_reviewed_source(root, tag):
    # Only these fixed source routes exist. Never accept a branch/ref override.
    if release_kind(tag) == "stable":
        refs = ["main"]
    else:
        base_tag, _ = diagnostic_base(tag)
        refs = [
            "refs/heads/" + DIAGNOSTIC_BRANCH + ":refs/remotes/origin/" + DIAGNOSTIC_BRANCH,
            "refs/tags/" + base_tag + ":refs/tags/" + base_tag,
            "refs/tags/" + tag + ":refs/tags/" + tag,
        ]
    subprocess.run(["git", "-C", str(root), "fetch", "--no-tags", "origin", *refs], check=True)
    require_reviewed_source(root, tag)


def require_main_ancestor(root):
    # The workflow freshly fetches main into FETCH_HEAD. Newer reviewed commits
    # on main are fine; release a fixed tag rather than chasing a moving branch.
    result = subprocess.run(["git", "-C", str(root), "merge-base", "--is-ancestor", "HEAD", "FETCH_HEAD"],
                            capture_output=True)
    if result.returncode:
        raise ValueError("Release commit must already belong to main history")


def version(root, tag=""):
    project = (root / "project.godot").read_text()
    matches = re.findall(r'^config/version="([^"]+)"$', project, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("project.godot must have exactly one config/version")
    release_kind("v" + matches[0])
    value = matches[0]
    notes = json.loads((root / "data/release_notes.json").read_text())
    if notes.get("version") != value:
        raise ValueError("project.godot and data/release_notes.json versions disagree")
    if tag:
        release_kind(tag)
        if tag != "v" + value:
            raise ValueError("Release tag must match both project and release notes")
        if notes.get("status") != "released":
            raise ValueError("Release notes must be marked released before publishing")
        if date.fromisoformat(notes["date"]) > date.today():
            raise ValueError("Release notes date must not be in the future (UTC runner)")
        if not notes.get("new") and not notes.get("fixed"):
            raise ValueError("Release notes must describe the release")
    return value


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--tag", default="")
    parser.add_argument("--require-main-ancestor", action="store_true")
    parser.add_argument("--fetch-reviewed-source", action="store_true",
                        help="Fetch and verify the fixed main or one-off diagnostic source route")
    args = parser.parse_args()
    release_version = version(args.root, args.tag)
    if args.fetch_reviewed_source:
        fetch_reviewed_source(args.root, args.tag)
    if args.require_main_ancestor:
        require_main_ancestor(args.root)
    print(release_version)
