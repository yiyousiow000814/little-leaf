import sys
"""Run real-scene bottom-notification removal checks with a disposable profile.

Usage: python3 tests/run_no_bottom_notifications.py
       python3 tests/run_no_bottom_notifications.py --rendered --output /tmp/leaf-captures
Rendered mode requires a working native display; captures are written to --output.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from project_layout import stage_project
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--rendered", action="store_true")
parser.add_argument("--output", type=Path, default=ROOT / "evidence/no-bottom-notifications")
parser.add_argument("--lock", type=Path, default=Path(os.environ.get(
    "LL_ENGINE_LOCK", str(ROOT.parent / ".little-leaf-engine.lock"))))
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
with args.lock.open("a") as lock, tempfile.TemporaryDirectory(prefix="little-leaf-no-bottom-") as temporary:
    fcntl.flock(lock, fcntl.LOCK_EX)
    temporary = Path(temporary)
    project = temporary / "project"
    stage_project(ROOT, project, tests=True, ignore=shutil.ignore_patterns(
        ".git", ".godot", "qa-project", "evidence", "__pycache__", "build", "builds",
        "export", "exports", "export_templates", "dist", "*.log", "*.zip"))
    env = os.environ.copy()
    for name in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME"):
        directory = temporary / "profile" / name.lower()
        directory.mkdir(parents=True, exist_ok=True)
        env[name] = str(directory)
    godot = os.environ.get("GODOT_BIN", "godot")
    commands = [
        ("import", ["--headless", "--editor", "--import", "--quit"]),
        ("no-bottom-notifications", ([] if args.rendered else ["--headless"]) + [
            "--script", "res://tests/test_no_bottom_notifications.gd", "--",
            "--visual-qa", "--skip-intro", "--fresh-review"] +
            (["--capture-dir=" + str(output)] if args.rendered else [])),
    ]
    report = None
    for label, flags in commands:
        result = subprocess.run([godot, "--path", str(project), *flags], env=env,
                                capture_output=True, text=True, timeout=180)
        text = result.stdout + result.stderr
        (output / (label + ".log")).write_text(text)
        print(text, end="", flush=True)
        if result.returncode or "SCRIPT ERROR:" in text:
            raise SystemExit(result.returncode or 1)
        if label != "import":
            prefix = "NO_BOTTOM_NOTIFICATIONS_RESULT "
            records = [json.loads(line[len(prefix):]) for line in text.splitlines() if line.startswith(prefix)]
            if len(records) != 1 or not records[0]["checks"] or records[0]["failures"]:
                raise SystemExit("Missing, duplicate or failed bottom-removal regression")
            report = records[0]
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
