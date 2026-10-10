"""Capture real gameplay in a disposable synthetic profile; no FPS measurement."""
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or output == ROOT or ROOT in output.parents:
        parser.error("Use a new evidence directory outside the repository")
    engine = shutil.which(args.godot)
    if not engine:
        parser.error("Explicit Godot executable is unavailable")
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="customer-visit-capture-") as scratch:
        scratch = Path(scratch)
        project = scratch / "project"
        shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns(
            ".git", ".godot", "__pycache__", "*.log"))
        env = os.environ.copy()
        for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME",
                    "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
            profile = scratch / "synthetic-profile" / key
            profile.mkdir(parents=True)
            env[key] = str(profile)
        env["OUTFIT_OUTPUT"] = str(output)
        for phase, flags in [
            ("import", ["--headless", "--editor", "--import", "--quit"]),
            ("capture", ["--rendering-method", "gl_compatibility",
                         "--rendering-driver", "opengl3", "--minimized",
                         "--script", "res://tests/capture_customer_visit_outfits.gd",
                         "--", "--visual-qa", "--fresh-review", "--skip-intro"]),
        ]:
            result = subprocess.run(
                [engine, "--audio-driver", "Dummy", "--path", str(project), *flags],
                env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            log = result.stdout.decode("utf-8", errors="replace")
            (output / (phase + ".log")).write_text(log, encoding="utf-8")
            if result.returncode or "SCRIPT ERROR" in log:
                raise RuntimeError("Failed " + phase + "; see evidence log")
            if phase == "capture" and "CUSTOMER_VISIT_GAMEPLAY_CAPTURE_OK" not in log:
                raise RuntimeError("Missing completed capture marker")
        for filename in ["gameplay.png", "gameplay-detail.png", "capture.json"]:
            if not (output / filename).is_file():
                raise RuntimeError("Missing capture artifact: " + filename)
        hashes = {p.relative_to(project).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in project.rglob("*.gd")}
    (output / "source-receipt.json").write_text(json.dumps({
        "source_sha256": hashes, "player_saves_used": False,
        "disposable_project_removed": True, "performance_measurement": False,
    }, indent=2), encoding="utf-8")
    print("Customer visit gameplay capture passed: " + str(output))


if __name__ == "__main__":
    main()
