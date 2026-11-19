"""Only exact #397 HEAD, tree and normalized game tar. No configuration/activation changes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent
COMMIT = "ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
TREE = "03632a0d56e4294f5664859656c8809541766d1b"
ARCHIVE_SHA = "5a236669cca594a1437b289f4b4b8a933a204ddab064844485d2868ce8ee1406"
MTIME = "2000-01-01T00:00:00Z"


def require(ok, why):
    if not ok:
        raise ValueError(why)


def hexhash(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def verify_identity(repo, binding):
    require((binding["commit"], binding["tree"], binding["archive_sha256"]) == (COMMIT, TREE, ARCHIVE_SHA),
            "Unexpected reviewed source binding")
    require(git(repo, "rev-parse", "HEAD").decode().strip() == COMMIT, "Official checkout HEAD must be exact")
    require(git(repo, "rev-parse", "HEAD^{tree}").decode().strip() == TREE, "Checkout tree does not match")
    require(binding["reviewed_game_files"], "Missing reviewed game files")
    for path, digest in binding["reviewed_game_files"].items():
        require(re.fullmatch(r"game/[A-Za-z0-9._/-]+", path) and ".." not in Path(path).parts, "Unreviewed path")
        require(hashlib.sha256(git(repo, "show", f"{TREE}:{path}")).hexdigest() == digest, "Reviewed source bytes changed")


def extract_verified(repo, binding, target):
    verify_identity(repo, binding)
    require(not target.exists() and not target.is_relative_to(repo), "Staging must be fresh and external")
    with TemporaryDirectory(dir=target.parent) as scratch:
        tar = Path(scratch) / "project.tar"
        git(repo, "archive", "--format=tar", "--mtime=" + MTIME, "-o", str(tar), TREE, "game")
        archive_sha = hexhash(tar)
        require(archive_sha == ARCHIVE_SHA, "Archive policy/content drift")
        target.mkdir()
        with tarfile.open(tar, "r:") as archive:
            archive.extractall(target, filter="data")
    for path,digest in binding["reviewed_game_files"].items():
        require(hexhash(target / path) == digest, "Extracted postimage mismatch")
    return archive_sha


