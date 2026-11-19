"""#389 staging adapted to require exact official HEAD + deterministic #397 game-tree tar."""
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


def verify_identity(repo, binding, tree_proof=False):
    require((binding["commit"], binding["tree"], binding["archive_sha256"]) == (COMMIT, TREE, ARCHIVE_SHA),
            "Unexpected reviewed source binding")
    if not tree_proof:
        require(git(repo, "rev-parse", "HEAD").decode().strip() == COMMIT, "Official checkout HEAD must be exact")
    require(git(repo, "rev-parse", "HEAD^{tree}").decode().strip() == TREE, "Checkout tree does not match")
    require(binding["reviewed_game_files"], "Missing reviewed game files")
    for path, digest in binding["reviewed_game_files"].items():
        require(re.fullmatch(r"game/[A-Za-z0-9._/-]+", path) and ".." not in Path(path).parts, "Unreviewed path")
        require(hashlib.sha256(git(repo, "show", f"{TREE}:{path}")).hexdigest() == digest, "Reviewed source bytes changed")


def extract_verified(repo, binding, target, tree_proof=False):
    verify_identity(repo, binding, tree_proof=tree_proof)
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


def stage(repo, commit, tree, target, binding_path=None, probe_path=None):
    require((commit, tree) == (COMMIT, TREE), "Unexpected requested source identity")
    binding = json.loads((binding_path or HERE / "input.json").read_text())
    archive_sha = extract_verified(repo, binding, target)
    project = target / "game"
    cfg = project / "project.godot"
    before = hexhash(cfg)
    data = cfg.read_text()
    autoload = r"^\[autoload\]\s*$"
    row = 'LLNativeDrawProbe="*res://ll_native_draw_probe.gd"'
    require(row not in data and not (project / "ll_native_draw_probe.gd").exists(), "Ambiguous new autoload")
    if re.search(autoload, data, flags=re.M):
        data = re.sub(autoload, r"\g<0>"+"\n"+row, data, count=1, flags=re.M)
    else:
        data += "\n[autoload]\n\n" + row + "\n"
    cfg.write_text(data)
    probe = project / "ll_native_draw_probe.gd"
    shutil.copyfile(probe_path or HERE / "native_draw_probe.gd", probe)
    receipt = {
        "source": {"commit": commit, "tree": tree, "allowed_project_paths": ["game"], "archive_sha256":archive_sha},
        "staged_project": "game",
        "diagnostic_patch": {"project_before_sha256":before, "project_after_sha256":hexhash(cfg), "probe_sha256":hexhash(probe)},
        "scope": "diagnostic-only extraction; no launch, import or FPS result"
    }
    (target / "diagnostic-source.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return project


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    for n in ("repo", "commit", "tree", "output"):
        p.add_argument("--" + n, type=Path if n in ("repo", "output") else str, required=True)
    p.add_argument("--binding", type=Path)
    p.add_argument("--probe", type=Path)
    a = p.parse_args()
    print(stage(a.repo.resolve(), a.commit, a.tree, a.output.resolve(), a.binding, a.probe))
