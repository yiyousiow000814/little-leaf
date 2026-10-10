"""Validate release metadata without executing game code or accessing credentials."""
import argparse
from datetime import date
import json
from pathlib import Path
import re
import subprocess
from project_layout import game_root

STABLE = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
# Project-specific hotfix releases, not SemVer prereleases: X.Y.Z < X.Y.Za.
RELEASE = STABLE + r"[a-z]?"


def release_key(value):
    """Strict numeric version ordering with an optional single lowercase hotfix."""
    if not re.fullmatch(RELEASE, value):
        raise ValueError("Expected X.Y.Z or X.Y.Za through X.Y.Zz")
    suffix = value[-1] if value[-1].isalpha() else ""
    numeric = value[:-1] if suffix else value
    return (*map(int, numeric.split(".")), ord(suffix) - ord("a") + 1 if suffix else 0)


def require_main_ancestor(root):
    # The workflow freshly fetches main into FETCH_HEAD. Newer reviewed commits
    # on main are fine; release a fixed tag rather than chasing a moving branch.
    result = subprocess.run(["git", "-C", str(root), "merge-base", "--is-ancestor", "HEAD", "FETCH_HEAD"],
                            capture_output=True)
    if result.returncode:
        raise ValueError("Release commit must already belong to main history")


def version(root, tag=""):
    root = game_root(root)
    project = (root / "project.godot").read_text()
    matches = re.findall(r'^config/version="([^"]+)"$', project, re.MULTILINE)
    if len(matches) != 1 or not re.fullmatch(RELEASE, matches[0]):
        raise ValueError("project.godot must have one X.Y.Z or X.Y.Z[a-z] config/version")
    value = matches[0]
    notes = json.loads((root / "data/release_notes.json").read_text())
    if notes.get("version") != value:
        raise ValueError("project.godot and data/release_notes.json versions disagree")
    if tag:
        if tag != "v" + value:
            raise ValueError("Release tag must be vX.Y.Z or vX.Y.Z[a-z] and match both project and release notes")
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
    args = parser.parse_args()
    if args.require_main_ancestor:
        require_main_ancestor(args.root)
    print(version(args.root, args.tag))
