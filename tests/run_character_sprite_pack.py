"""Focused silent native import test, entirely within a disposable project/profile."""
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
    parser.add_argument("--headless", action="store_true", help="Import/ownership checks only; no pixel acceptance")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / "project"
    (project / "scripts").mkdir(parents=True)
    (project / "tests").mkdir()
    sources = {"scripts/character_sprite_pack.gd": ROOT / "game/scripts/character_sprite_pack.gd", "tests/test_character_sprite_pack.gd": ROOT / "tests/test_character_sprite_pack.gd"}
    hashes = {}
    for target, source in sources.items():
        shutil.copy2(source, project / target)
        hashes[target] = hashlib.sha256(source.read_bytes()).hexdigest()
    (project / "project.godot").write_text('[application]\nconfig/name="LittleLeafSpritePackSynthetic"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    env = os.environ.copy()
    for key in ["APPDATA", "LOCALAPPDATA", "HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME"]:
        destination = output / "profile" / key
        destination.mkdir(parents=True)
        env[key] = str(destination)
    env["CHARACTER_PACK_OUTPUT"] = str(output)
    command = [args.godot, "--path", str(project), "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", "--quit-after", "180", "--script", "res://tests/test_character_sprite_pack.gd"]
    if args.headless:
        command.insert(1, "--headless")
    with (output / "native.log").open("w", encoding="utf-8") as log_file:
        result = subprocess.run(command, env=env, stdout=log_file, stderr=subprocess.STDOUT, timeout=60)
    log = (output / "native.log").read_text(encoding="utf-8")
    prefix = "CHARACTER_SPRITE_PACK_RESULT "
    line = next((line for line in log.splitlines() if line.startswith(prefix)), None)
    receipt = {"source_sha256": hashes, "command": command, "exit_code": result.returncode, "result": json.loads(line[len(prefix):]) if line else None, "captures": {}}
    for name in ["baseline.png", "candidate.png"]:
        path = output / name
        if path.exists(): receipt["captures"][name] = hashlib.sha256(path.read_bytes()).hexdigest()
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt))
    if result.returncode or line is None or "SCRIPT ERROR" in log or receipt["result"]["failures"]:
        raise SystemExit(1)

if __name__ == "__main__":
    main()
