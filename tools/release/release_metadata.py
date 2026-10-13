"""Validate release metadata without executing game code or accessing credentials."""
import argparse
from datetime import date
import json
from pathlib import Path
import re
import subprocess
if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build.project_layout import game_root

STABLE = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
# Project-specific hotfix releases, not SemVer prereleases: X.Y.Z < X.Y.Za.
NORMAL_RELEASE = STABLE + r"[a-z]?"
SHA_RELEASE = STABLE + r"-pre\.[0-9a-f]{8}"
RELEASE = r"(?:" + NORMAL_RELEASE + "|" + SHA_RELEASE + ")"
SOURCE_RELEASE = STABLE + r"-pre"


def resolved_version(value, source_commit):
    """A committed family marker becomes an opaque exact-source display name.

    Eight decimal-only/leading-zero hex digits remain an identity, never a
    SemVer numeric prerelease or an ordering key.
    """
    if re.fullmatch(SOURCE_RELEASE, value):
        if not re.fullmatch(r"[0-9a-f]{40}", source_commit or ""):
            raise ValueError("SHA prerelease requires the exact full source commit")
        return value + "." + source_commit[:8]
    if not re.fullmatch(NORMAL_RELEASE, value):
        raise ValueError("Expected normal release or committed X.Y.Z-pre family")
    return value


def projected_metadata(root, source_commit):
    """Only these two copied metadata inputs may differ from tested source."""
    root = game_root(root)
    value = version(root, source_commit=source_commit)
    project = (root / "project.godot").read_bytes()
    notes_bytes = (root / "data/release_notes.json").read_bytes()
    notes = json.loads(notes_bytes)
    if not re.fullmatch(SOURCE_RELEASE, notes['version']):
        return {}
    old = ('config/version="' + notes['version'] + '"').encode()
    if project.count(old) != 1:
        raise ValueError("Unique project version required for projection")
    notes['version'] = value
    return {'project.godot': project.replace(old, ('config/version="' + value + '"').encode()),
            'data/release_notes.json': (json.dumps(notes, ensure_ascii=False, indent=2) + '\n').encode()}


def release_key(value):
    """Strict numeric version ordering with an optional single lowercase hotfix."""
    if not re.fullmatch(NORMAL_RELEASE, value):
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


def version(root, tag="", source_commit=None):
    repository = root
    root = game_root(root)
    project = (root / "project.godot").read_text()
    matches = re.findall(r'^config/version="([^"]+)"$', project, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("project.godot must have one X.Y.Z or X.Y.Z[a-z] config/version")
    raw = matches[0]
    notes = json.loads((root / "data/release_notes.json").read_text())
    if notes.get("version") != raw:
        raise ValueError("project.godot and data/release_notes.json versions disagree")
    if type(notes.get("prerelease", False)) is not bool:
        raise ValueError("Release prerelease flag must be a boolean")
    if re.fullmatch(SOURCE_RELEASE, raw):
        if notes.get('prerelease') is not True:
            raise ValueError("SHA prerelease family requires prerelease=true")
        if source_commit is None:
            source_commit = subprocess.check_output(['git', '-C', str(repository), 'rev-parse', 'HEAD'], text=True).strip()
    value = resolved_version(raw, source_commit)
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
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--tag", default="")
    parser.add_argument("--source-commit", default=None)
    parser.add_argument("--require-main-ancestor", action="store_true")
    args = parser.parse_args()
    if args.require_main_ancestor:
        require_main_ancestor(args.root)
    print(version(args.root, args.tag, source_commit=args.source_commit))
