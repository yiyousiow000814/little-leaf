"""Verify routing against an explicitly pinned model in a disposable profile."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from project_layout import source_path
FILES = ["scripts/cafe_navigation_candidate.gd", "tests/test_navigation_model_adapter_candidate.gd"]


def archive(repo, commit, paths, project):
    migrated = subprocess.run(["git", "-c", "safe.directory=" + repo.as_posix(),
                              "cat-file", "-e", commit + ":game/project.godot"],
                             cwd=repo, capture_output=True).returncode == 0
    paths = ["game/" + name if migrated and name.split("/")[0] in {"scripts", "data"} else name
             for name in paths]
    packed = subprocess.run(["git", "-c", "safe.directory=" + repo.as_posix(),
                             "archive", commit, *paths], cwd=repo, capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(packed)) as source:
        for member in source.getmembers():
            if member.name.startswith("game/"):member.name = member.name[5:]
            if member.name:source.extract(member, project, filter="data")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--model-repo", type=Path, required=True)
    parser.add_argument("--model-commit", required=True)
    parser.add_argument("--source-commit")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="little-leaf-adapter-saveguard-") as temporary:
        isolated = Path(temporary)
        project = isolated / "project"
        project.mkdir()
        archive(args.model_repo.resolve(), args.model_commit, ["scripts", "data"], project)
        if args.source_commit:
            archive(ROOT, args.source_commit, FILES, project)
        else:
            for name in FILES:
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source_path(ROOT, name).read_bytes())
        hashes = {p.relative_to(project).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(project.rglob("*")) if p.is_file()}
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="LittleLeaf adapter saveguard"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
        env = os.environ.copy()
        for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            profile = isolated / "profiles" / key.lower()
            profile.mkdir(parents=True)
            env[key] = str(profile)
        command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                   "--script", "res://tests/test_navigation_model_adapter_candidate.gd"]
        with (args.output / "engine.log").open("wb") as log:
            try:
                code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=60).returncode
            except subprocess.TimeoutExpired:
                code = 124
        log = (args.output / "engine.log").read_text(encoding="utf-8", errors="replace")
        marker = "NAVIGATION_ADAPTER_RESULT "
        results = [json.loads(line.split(marker, 1)[1]) for line in log.splitlines() if marker in line]
        writes = list((isolated / "profiles").rglob("*.json"))
        passed = code == 0 and len(results) == 1 and not results[0]["failures"] and not writes and "SCRIPT ERROR:" not in log
        receipt = {"source_commit": args.source_commit, "model_commit": args.model_commit,
                   "source_sha256": hashes, "exit_code": code, "result": results,
                   "status": "pass" if passed else "fail", "profile_json_writes": len(writes),
                   "production_enabled": False, "fps": "not_run",
                   "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   "log_sha256": hashlib.sha256((args.output / "engine.log").read_bytes()).hexdigest()}
        (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(log)
        return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
