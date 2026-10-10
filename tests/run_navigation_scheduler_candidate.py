"""Run only the inactive scheduler in a disposable, optionally frozen project."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from project_layout import source_path
FILES = ["scripts/cafe_navigation_candidate.gd",
         "scripts/cafe_navigation_scheduler_candidate.gd"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-commit", help="Extract exact Git source; otherwise use working files")
    parser.add_argument("--only-follower", action="store_true", help="Run only scheduler/follower consumption regressions")
    args = parser.parse_args()
    test = "test_navigation_follower_scheduler_candidate" if args.only_follower else "test_navigation_scheduler_candidate"
    files = FILES + ["tests/" + test + ".gd"]
    args.output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="little-leaf-scheduler-") as temporary:
        isolated = Path(temporary)
        project = isolated / "project"
        project.mkdir()
        if args.source_commit:
            migrated = subprocess.run(["git", "cat-file", "-e", args.source_commit + ":game/project.godot"],
                                      cwd=ROOT, capture_output=True).returncode == 0
            for name in files:
                tracked = "game/" + name if migrated and name.startswith("scripts/") else name
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(subprocess.run(["git", "show", args.source_commit + ":" + tracked],
                                                 cwd=ROOT, capture_output=True, check=True).stdout)
        else:
            for name in files:
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source_path(ROOT, name).read_bytes())
        hashes = {name: hashlib.sha256((project / name).read_bytes()).hexdigest() for name in files}
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="LittleLeaf Scheduler Synthetic"\n', encoding="utf-8")
        env = os.environ.copy()
        for name in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            profile = isolated / "profiles" / name.lower()
            profile.mkdir(parents=True)
            env[name] = str(profile)
        command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                   "--script", "res://tests/" + test + ".gd"]
        with (args.output / "engine.log").open("wb") as log_file:
            try:
                exit_code = subprocess.run(command, env=env, stdout=log_file,
                                           stderr=subprocess.STDOUT, timeout=90).returncode
            except subprocess.TimeoutExpired:
                exit_code = 124
        log = (args.output / "engine.log").read_text(encoding="utf-8", errors="replace")
        marker = "NAVIGATION_SCHEDULER_RESULT "
        results = [json.loads(line.split(marker, 1)[1]) for line in log.splitlines() if marker in line]
        writes = list((isolated / "profiles").rglob("*.json"))
        passed = (exit_code == 0 and len(results) == 1 and not results[0]["failures"]
                  and "SCRIPT ERROR:" not in log and not writes)
        receipt = {"source_commit": args.source_commit, "source_sha256": hashes,
                   "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   "godot": subprocess.run([args.godot, "--version"], capture_output=True,
                                           text=True).stdout.strip(), "command": command,
                   "status": "pass" if passed else "fail", "exit_code": exit_code,
                   "result": results, "profile_json_writes": len(writes),
                   "production_enabled": False, "fps": "not_run",
                   "log_sha256": hashlib.sha256((args.output / "engine.log").read_bytes()).hexdigest()}
        (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(log)
        return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
