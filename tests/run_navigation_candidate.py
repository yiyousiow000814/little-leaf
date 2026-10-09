"""Small headless synthetic-only navigation runner; never opens the game profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True, check=True).stdout.strip()
    paths = list((ROOT / "scripts").glob("*.gd")) + list((ROOT / "data").rglob("*"))
    paths += [ROOT / "tests/test_navigation_candidate.gd", Path(__file__)]
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(paths) if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="little-leaf-navigation-") as temporary:
        isolated = Path(temporary)
        project = isolated / "project"
        project.mkdir()
        shutil.copytree(ROOT / "scripts", project / "scripts")
        shutil.copytree(ROOT / "data", project / "data")
        (project / "tests").mkdir()
        shutil.copy2(ROOT / "tests/test_navigation_candidate.gd", project / "tests")
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="LittleLeaf Navigation Synthetic"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
        env = os.environ.copy()
        for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            profile = isolated / "profiles" / key.lower()
            profile.mkdir(parents=True)
            env[key] = str(profile)
        command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                   "--script", "res://tests/test_navigation_candidate.gd"]
        with (args.output / "navigation.log").open("wb") as log_file:
            try:
                completed = subprocess.run(command, env=env, stdout=log_file,
                                           stderr=subprocess.STDOUT, timeout=60)
                exit_code = completed.returncode
            except subprocess.TimeoutExpired:
                exit_code = 124
        log = (args.output / "navigation.log").read_text(encoding="utf-8", errors="replace")
        marker = "NAVIGATION_CANDIDATE_RESULT "
        payloads = [json.loads(line.split(marker, 1)[1]) for line in log.splitlines() if marker in line]
        passed = exit_code == 0 and len(payloads) == 1 and not payloads[0]["failures"]
        saves = list(isolated.rglob("*.json"))
        saves = [p for p in saves if "profiles" in p.parts]
        report = {"source_commit": commit, "source_sha256": hashes,
                  "command": command, "godot": subprocess.run([args.godot, "--version"],
                  capture_output=True, text=True).stdout.strip(), "exit_code": exit_code,
                  "status": "pass" if passed else "fail", "result": payloads,
                  "profile_json_writes": len(saves), "native_pixels": "not_run",
                  "browser": "not_run", "fps": "not_run", "production_enabled": False,
                  "log_sha256": hashlib.sha256((args.output / "navigation.log").read_bytes()).hexdigest()}
        (args.output / "receipt.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(log)
        print("Receipt:", args.output / "receipt.json")
        return 0 if passed and not saves else 1


if __name__ == "__main__":
    raise SystemExit(main())
