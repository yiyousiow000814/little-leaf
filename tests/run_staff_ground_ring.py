"""Focused native staff-ring fixture; disposable project and profile, Dummy audio."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--game", action="store_true", help="Actual Main renderer with synthetic startup instead of isolated painter")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / "project"
    shutil.copytree(ROOT / "game", project, ignore=shutil.ignore_patterns(".godot"))
    (project / "tests").mkdir()
    fixture = "test_staff_ground_ring_game.gd" if args.game else "test_staff_ground_ring.gd"
    shutil.copy2(ROOT / "tests" / fixture, project / "tests" / fixture)
    env = os.environ.copy()
    for key in ["APPDATA", "LOCALAPPDATA", "HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME"]:
        destination = output / "profile" / key
        destination.mkdir(parents=True)
        env[key] = str(destination)
    env["STAFF_RING_OUTPUT"] = str(output)
    common = [args.godot, "--path", str(project), "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility"]
    with (output / "import.log").open("w", encoding="utf-8") as log:
        imported = subprocess.run(common + ["--headless", "--editor", "--quit"], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=90)
    if imported.returncode:
        raise SystemExit("Disposable import failed; inspect import.log")
    command = common + ["--quit-after", "300", "--script", "res://tests/" + fixture]
    with (output / "native.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=60)
    text = (output / "native.log").read_text(encoding="utf-8")
    prefix = "STAFF_GROUND_RING_GAME_RESULT " if args.game else "STAFF_GROUND_RING_RESULT "
    line = next((line for line in text.splitlines() if line.startswith(prefix)), None)
    hashes = {str(p.relative_to(project)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in project.rglob("*.gd")}
    receipt = {"source_sha256": hashes, "command": command, "exit_code": result.returncode,
               "result": json.loads(line[len(prefix):]) if line else None,
               "captures": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in output.glob("*.png")}}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"receipt": str(output / "receipt.json"), "result": receipt["result"]}))
    if result.returncode or line is None or "SCRIPT ERROR" in text or receipt["result"]["failures"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
